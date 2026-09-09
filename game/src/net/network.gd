extends Node

## Autoload "Net" — multiplayer (prototype tier), two flavors sharing one
## client-authoritative LAN-trust netcode (no prediction/rewind — correct at
## ~1ms, NOT the shipping §20.2 architecture):
##
## - LAN listen-server (host is a player, everyone broadcast-synced):
##     host:  godot4 --path game -- --server
##     join:  godot4 --path game -- --client <ip>
## - Dedicated lobby server (matchmaker + relay — the server never loads the
##   arena or simulates anything; each matched pair loads its OWN local
##   arena and exchanges rpc_id-targeted state, so concurrent 1v1s are
##   isolated because no third peer ever receives their traffic):
##     serve: godot4 --headless --path game -- --dedicated
##     join:  godot4 --path game -- --lobby <ip> --name <username>
##
## Offline play (no CLI args, no menu action) is untouched.

signal kill_reported(killer_id: int, victim_id: int)
signal roster_updated(roster: Array)
signal challenge_received(from_id: int, from_name: String)
signal challenge_ended(reason: String)
signal net_error(message: String)

enum Mode { OFFLINE, LAN, LOBBY, DEDICATED }

const ARENA := "res://maps/graybox_corridor.tscn"
const LOBBY_SCENE := "res://src/lobby/lobby.tscn"
const MENU_SCENE := "res://src/menu/main_menu.tscn"
const DEFAULT_SERVER := "play.airfuel-game.com"  # blank JOIN SERVER field / bare --lobby
# NOTE: must stay a DNS-only (grey-cloud) record — Cloudflare's proxy can't
# carry the game's UDP. The bare domain is Proxied and serves the homepage.
const PORT := 27555
const MAX_PEERS := 8  # legacy LAN listen-server cap; the lobby cap is config
const PLAYER_SCENE := preload("res://src/player/player.tscn")
const SERVER_CONFIG := preload("res://src/net/default_server.tres")

var mode := Mode.OFFLINE
var active := false
var is_host := false
var players: Dictionary = {}  # peer id -> AirfuelPlayer (lobby match: just the pair)
var scores: Dictionary = {}  # peer id -> kills (LAN: all peers tally; lobby: server-fed)

# Lobby client state
var my_name := ""
var last_error := ""  # cached for the menu (a failure may land mid-scene-change)
var match_opponent := 0  # peer id; nonzero exactly while in a lobby match
var match_names: Dictionary = {}  # peer id -> username (both duelists)
var last_roster: Array = []  # cache so the lobby scene can render on entry
var last_match_result: Dictionary = {}  # {won, forfeit, text} for the lobby banner

var autoduel := false  # --autoduel: headless test aid (auto challenge/accept)

# Dedicated-server state (peer 1 only)
var cfg: ServerConfig = SERVER_CONFIG
var roster: Dictionary = {}  # peer id -> {name, wins, losses, match_id}
var matches: Dictionary = {}  # match id -> {a, b, kills: {peer id: int}}
var next_match_id := 1
var pending_challenges: Dictionary = {}  # challenger id -> {target, time_left}

var _autoduel_sent := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	autoduel = "--autoduel" in args
	if "--dedicated" in args:
		host_dedicated()
	elif "--server" in args:
		host()
	elif args.find("--client") != -1:
		join(_arg_value(args, "--client", "127.0.0.1"))
	elif args.find("--lobby") != -1:
		join_lobby(
			_arg_value(args, "--lobby", DEFAULT_SERVER), _arg_value(args, "--name", "player")
		)


func _arg_value(args: PackedStringArray, flag: String, fallback: String) -> String:
	var i := args.find(flag)
	if i != -1 and i + 1 < args.size() and not args[i + 1].begins_with("--"):
		return args[i + 1]
	return fallback


func host() -> void:
	if active:
		return
	await _load_arena()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PEERS)
	if err != OK:
		_fail(
			(
				"Couldn't host on udp/%d (%s) — is a server already running?"
				% [PORT, error_string(err)]
			)
		)
		_teardown_to_menu()
		return
	_clear_session_signals()
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = true
	mode = Mode.LAN
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("Airfuel net: hosting on udp/%d" % PORT)
	_spawn_player(1)


func join(ip: String) -> void:
	if active:
		return
	if not _resolve_or_fail(ip):
		return
	await _load_arena()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		_fail("Couldn't start a client for %s (%s)." % [ip, error_string(err)])
		_teardown_to_menu()
		return
	_clear_session_signals()
	multiplayer.multiplayer_peer = peer
	active = true
	mode = Mode.LAN
	multiplayer.connected_to_server.connect(
		func() -> void:
			print("Airfuel net: joined %s as peer %d" % [ip, multiplayer.get_unique_id()])
	)
	multiplayer.connection_failed.connect(
		func() -> void:
			_fail("Couldn't reach %s on udp/%d — no host answered." % [ip, PORT])
			_teardown_to_menu.call_deferred()
	)
	multiplayer.server_disconnected.connect(
		func() -> void:
			_fail("Host disconnected.")
			_teardown_to_menu.call_deferred()
	)
	print("Airfuel net: connecting to %s:%d..." % [ip, PORT])


## Dedicated lobby server: matchmaker + relay only. Never loads the arena,
## never spawns a body — stays on whatever scene booted (headless menu).
func host_dedicated() -> void:
	if active:
		return
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, cfg.max_peers)
	if err != OK:
		_fail("Couldn't host lobby on udp/%d (%s) — port in use?" % [PORT, error_string(err)])
		return
	_clear_session_signals()
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = true
	mode = Mode.DEDICATED
	multiplayer.peer_connected.connect(
		func(id: int) -> void: print("Airfuel lobby: peer %d connected" % id)
	)
	multiplayer.peer_disconnected.connect(_on_lobby_peer_disconnected)
	print(
		(
			"Airfuel lobby: dedicated server on udp/%d (%d peers max, first to %d)"
			% [PORT, cfg.max_peers, cfg.duel_win_kills]
		)
	)


func join_lobby(ip: String, username: String) -> void:
	if active:
		return
	if not _resolve_or_fail(ip):
		return
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		_fail("Couldn't start a client for %s (%s)." % [ip, error_string(err)])
		return
	_clear_session_signals()
	multiplayer.multiplayer_peer = peer
	active = true
	mode = Mode.LOBBY
	my_name = username
	multiplayer.connected_to_server.connect(
		func() -> void:
			print("Airfuel lobby: joined %s as peer %d" % [ip, multiplayer.get_unique_id()])
			register.rpc_id(1, my_name)
			get_tree().change_scene_to_file(LOBBY_SCENE)
	)
	multiplayer.connection_failed.connect(
		func() -> void:
			_fail(
				(
					(
						"Couldn't reach %s on udp/%d — server down, wrong IP, "
						+ "or the port isn't forwarded."
					)
					% [ip, PORT]
				)
			)
			_teardown_to_menu.call_deferred()
	)
	multiplayer.server_disconnected.connect(
		func() -> void:
			_fail("Server disconnected.")
			_teardown_to_menu.call_deferred()
	)
	print("Airfuel lobby: connecting to %s:%d..." % [ip, PORT])


## Full lobby-client teardown: close the peer, drop match state, back to menu.
func leave_lobby() -> void:
	_teardown_to_menu()


## Blocking DNS pre-check: a hostname that doesn't resolve would otherwise
## surface as create_client's generic ERR_CANT_CREATE ("error 20") — catch
## it first and name the actual problem.
func _resolve_or_fail(address: String) -> bool:
	if address.is_valid_ip_address():
		return true
	var resolved := IP.resolve_hostname(address)
	if resolved.is_valid_ip_address():
		return true
	_fail(
		(
			(
				"Couldn't find server '%s' — the name doesn't resolve. Check the "
				+ "address (and that its DNS record exists)."
			)
			% address
		)
	)
	return false


## User-facing connection failure: cache + print + signal. The menu shows
## `last_error` on entry (the failure may land mid-scene-change) and live
## via `net_error` while it's the current scene.
func _fail(message: String) -> void:
	last_error = message
	push_error("Airfuel net: " + message)
	net_error.emit(message)


## Drop every session signal connection Net owns on the multiplayer
## singleton. Without this, a retry after a failed/dropped session would
## stack a second set of lambdas and double-fire (stale captured ip, double
## scene change). Net is the only subscriber to these signals.
func _clear_session_signals() -> void:
	for sig: Signal in [
		multiplayer.connected_to_server,
		multiplayer.connection_failed,
		multiplayer.server_disconnected,
		multiplayer.peer_connected,
		multiplayer.peer_disconnected
	]:
		for c: Dictionary in sig.get_connections():
			sig.disconnect(c.callable)


## Shared client teardown (leave, connection failure, server drop): free any
## bodies, reset all session state, and land on the menu — without reloading
## the menu if it's already the current scene (keeps typed fields + the
## just-shown error intact).
func _teardown_to_menu() -> void:
	for p: Node in players.values():
		if is_instance_valid(p):
			p.queue_free()
	players.clear()
	scores.clear()
	match_opponent = 0
	match_names.clear()
	last_roster = []
	last_match_result = {}
	_autoduel_sent = false
	active = false
	is_host = false
	mode = Mode.OFFLINE
	_clear_session_signals()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var cur := get_tree().current_scene
	if cur == null or cur.scene_file_path != MENU_SCENE:
		get_tree().change_scene_to_file(MENU_SCENE)


## ---- Lobby protocol (server = peer 1; all reliable) ----

@rpc("any_peer", "call_remote", "reliable")
func register(username: String) -> void:
	if mode != Mode.DEDICATED:
		return
	var id := multiplayer.get_remote_sender_id()
	roster[id] = {name = _unique_name(username), wins = 0, losses = 0, match_id = 0}
	print("Airfuel lobby: peer %d registered as '%s'" % [id, roster[id].name])
	_broadcast_roster()


func _unique_name(raw: String) -> String:
	var base := raw.strip_edges().left(cfg.max_name_length)
	if base.is_empty():
		base = "player"
	var candidate := base
	var suffix := 2
	while roster.values().any(func(r: Dictionary) -> bool: return r.name == candidate):
		candidate = "%s%d" % [base, suffix]
		suffix += 1
	return candidate


func _broadcast_roster() -> void:
	var arr: Array = []
	for id: int in roster:
		var r: Dictionary = roster[id]
		arr.append(
			{id = id, name = r.name, wins = r.wins, losses = r.losses, in_match = r.match_id != 0}
		)
	roster_sync.rpc(arr)


@rpc("authority", "call_remote", "reliable")
func roster_sync(arr: Array) -> void:
	last_roster = arr
	roster_updated.emit(arr)
	# Headless test aid: the highest-id idle peer challenges the lowest, once.
	if autoduel and not _autoduel_sent and match_opponent == 0:
		var idle: Array = arr.filter(func(e: Dictionary) -> bool: return not e.in_match)
		if idle.size() >= 2:
			var ids: Array = idle.map(func(e: Dictionary) -> int: return e.id)
			ids.sort()
			if multiplayer.get_unique_id() == ids.back():
				_autoduel_sent = true
				request_challenge.rpc_id(1, ids.front())


@rpc("any_peer", "call_remote", "reliable")
func request_challenge(target_id: int) -> void:
	if mode != Mode.DEDICATED:
		return
	var from := multiplayer.get_remote_sender_id()
	if (
		from == target_id
		or not roster.has(from)
		or not roster.has(target_id)
		or roster[from].match_id != 0
		or roster[target_id].match_id != 0
		or pending_challenges.has(from)
		or _is_challenge_target(target_id)
		or _is_challenge_target(from)
	):
		challenge_result.rpc_id(from, false, "unavailable")
		return
	pending_challenges[from] = {target = target_id, time_left = cfg.challenge_timeout}
	challenge_offer.rpc_id(target_id, from, roster[from].name)


func _is_challenge_target(id: int) -> bool:
	return pending_challenges.values().any(func(c: Dictionary) -> bool: return c.target == id)


@rpc("authority", "call_remote", "reliable")
func challenge_offer(from_id: int, from_name: String) -> void:
	if autoduel:
		challenge_reply.rpc_id(1, from_id, true)
		return
	challenge_received.emit(from_id, from_name)


@rpc("any_peer", "call_remote", "reliable")
func challenge_reply(challenger_id: int, accept: bool) -> void:
	if mode != Mode.DEDICATED:
		return
	var target := multiplayer.get_remote_sender_id()
	var pending: Dictionary = pending_challenges.get(challenger_id, {})
	if pending.get("target", 0) != target:
		return  # expired or never existed; the challenger was already told
	pending_challenges.erase(challenger_id)
	if accept and roster[challenger_id].match_id == 0 and roster[target].match_id == 0:
		_start_match(challenger_id, target)
	else:
		challenge_result.rpc_id(challenger_id, false, "declined")


@rpc("authority", "call_remote", "reliable")
func challenge_result(_accepted: bool, reason: String) -> void:
	challenge_ended.emit(reason)


## Challenge timeouts tick server-side only.
func _process(delta: float) -> void:
	if mode != Mode.DEDICATED or pending_challenges.is_empty():
		return
	for from: int in pending_challenges.keys():
		pending_challenges[from].time_left -= delta
		if pending_challenges[from].time_left <= 0.0:
			var target: int = pending_challenges[from].target
			pending_challenges.erase(from)
			challenge_result.rpc_id(from, false, "timeout")
			challenge_withdrawn.rpc_id(target)


@rpc("authority", "call_remote", "reliable")
func challenge_withdrawn() -> void:
	challenge_ended.emit("withdrawn")


## ---- Match lifecycle ----


func _start_match(a: int, b: int) -> void:
	var mid := next_match_id
	next_match_id += 1
	matches[mid] = {a = a, b = b, kills = {a: 0, b: 0}}
	roster[a].match_id = mid
	roster[b].match_id = mid
	match_start.rpc_id(a, b, roster[b].name, 0)
	match_start.rpc_id(b, a, roster[a].name, 1)
	print("Airfuel lobby: match %d — %s vs %s" % [mid, roster[a].name, roster[b].name])
	_broadcast_roster()


## Client side: load a private local arena and spawn exactly the pair.
## side 0 = challenger (−z end), side 1 = challenged (+z end).
@rpc("authority", "call_remote", "reliable")
func match_start(opponent_id: int, opponent_name: String, side: int) -> void:
	match_opponent = opponent_id
	var my_id := multiplayer.get_unique_id()
	match_names = {my_id: my_name, opponent_id: opponent_name}
	await _load_arena()
	scores = {my_id: 0, opponent_id: 0}
	_spawn_player(my_id, side)
	_spawn_player(opponent_id, 1 - side)


## Sent by the VICTIM's authority (mirrors the LAN report_kill flow).
@rpc("any_peer", "call_remote", "reliable")
func report_match_kill(killer_id: int) -> void:
	if mode != Mode.DEDICATED:
		return
	var victim := multiplayer.get_remote_sender_id()
	var mid: int = roster.get(victim, {}).get("match_id", 0)
	if mid == 0 or not matches.has(mid):
		return
	var m: Dictionary = matches[mid]
	if killer_id != m.a and killer_id != m.b:
		return
	m.kills[killer_id] += 1
	if m.kills[killer_id] >= cfg.duel_win_kills:
		_end_match(mid, killer_id, false)
	else:
		match_score.rpc_id(m.a, killer_id, victim, m.kills.duplicate())
		match_score.rpc_id(m.b, killer_id, victim, m.kills.duplicate())


@rpc("authority", "call_remote", "reliable")
func match_score(killer_id: int, victim_id: int, kills: Dictionary) -> void:
	scores = kills
	kill_reported.emit(killer_id, victim_id)  # HUD feed/banner, as in LAN
	if killer_id == multiplayer.get_unique_id():
		for p: Node in get_tree().get_nodes_in_group("player"):
			if p.is_multiplayer_authority():
				p.round_reset(true)
				return


func _end_match(mid: int, winner_id: int, forfeit: bool) -> void:
	var m: Dictionary = matches[mid]
	matches.erase(mid)
	for id: int in [m.a, m.b]:
		if roster.has(id):
			roster[id].match_id = 0
			if id == winner_id:
				roster[id].wins += 1
			else:
				roster[id].losses += 1
	var final: Dictionary = m.kills
	for id: int in [m.a, m.b]:
		if roster.has(id):
			match_over.rpc_id(id, winner_id, forfeit, final)
	print(
		(
			"Airfuel lobby: match %d over, winner %s%s"
			% [
				mid,
				roster.get(winner_id, {}).get("name", str(winner_id)),
				" (forfeit)" if forfeit else ""
			]
		)
	)
	_broadcast_roster()


## Client side: tear the duel down and return to the lobby scene.
@rpc("authority", "call_remote", "reliable")
func match_over(winner_id: int, forfeit: bool, kills: Dictionary) -> void:
	var my_id := multiplayer.get_unique_id()
	var opp := match_opponent
	last_match_result = {
		won = winner_id == my_id,
		forfeit = forfeit,
		text =
		(
			"%s %d — %d vs %s"
			% [
				"WON" if winner_id == my_id else "LOST",
				int(kills.get(my_id, 0)),
				int(kills.get(opp, 0)),
				match_names.get(opp, "?")
			]
		),
	}
	for p: Node in players.values():
		if is_instance_valid(p):
			p.queue_free()
	players.clear()
	scores.clear()
	match_opponent = 0
	match_names.clear()
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_lobby_peer_disconnected(id: int) -> void:
	print("Airfuel lobby: peer %d disconnected" % id)
	var mid: int = roster.get(id, {}).get("match_id", 0)
	roster.erase(id)
	pending_challenges.erase(id)
	for from: int in pending_challenges.keys():
		if pending_challenges[from].target == id:
			pending_challenges.erase(from)
			challenge_result.rpc_id(from, false, "unavailable")
	if mid != 0 and matches.has(mid):
		var m: Dictionary = matches[mid]
		var survivor: int = m.b if m.a == id else m.a
		_end_match(mid, survivor, true)
	else:
		_broadcast_roster()


## Username for a peer id in the current lobby match ("YOU" handled by HUD).
func display_name(id: int) -> String:
	return match_names.get(id, "P%d" % (id % 1000))


## Switch to the arena (from menu or startup), then strip its offline Player
## so per-peer spawns are the only players. Peer creation happens AFTER this,
## so no spawn rpc can arrive while the menu is still the current scene.
func _load_arena() -> void:
	await get_tree().process_frame
	if get_tree().current_scene == null or get_tree().current_scene.scene_file_path != ARENA:
		get_tree().change_scene_to_file(ARENA)
		while get_tree().current_scene == null or get_tree().current_scene.scene_file_path != ARENA:
			await get_tree().process_frame
	var offline := get_tree().current_scene.get_node_or_null("Player")
	if offline != null:
		offline.free()
	# PvP arena: no practice dummies in LAN sessions
	for dummy: Node in get_tree().get_nodes_in_group("target"):
		dummy.free()


func _on_peer_connected(id: int) -> void:
	print("Airfuel net: peer %d connected" % id)
	for existing_id: int in players:
		_spawn_remote.rpc_id(id, existing_id)
	_spawn_remote.rpc(id)
	_spawn_player(id)


func _on_peer_disconnected(id: int) -> void:
	print("Airfuel net: peer %d disconnected" % id)
	_despawn_remote.rpc(id)
	_despawn_player(id)


## index -1 (LAN default) = spawn order, i.e. players.size() at spawn time;
## lobby matches pass the server-assigned side explicitly.
func _spawn_player(id: int, index: int = -1) -> void:
	if players.has(id):
		return
	var p := PLAYER_SCENE.instantiate() as CharacterBody3D
	p.name = str(id)
	p.set_multiplayer_authority(id)
	p.transform = _spawn_transform_for_index(index if index >= 0 else players.size())
	get_tree().current_scene.add_child(p)
	players[id] = p
	print(
		(
			"Airfuel net: spawned player %d at %s (mine: %s, cam: %s)"
			% [
				id,
				p.global_position,
				p.is_multiplayer_authority(),
				(p.get_node("Head/Camera3D") as Camera3D).current
			]
		)
	)


## Spawns alternate ends (even index: -z facing +z, odd: +z facing -z) and
## spread laterally for 3+ players. Index = spawn order (players.size() at
## spawn time), which the server-driven roster keeps identical on all peers.
func _spawn_transform_for_index(index: int) -> Transform3D:
	var x := float(index / 2 * 8)
	if index % 2 == 0:
		return Transform3D(Basis(Vector3.UP, PI), Vector3(x, 2.6, -430.0))
	return Transform3D(Basis(), Vector3(x, 2.6, 430.0))


func _despawn_player(id: int) -> void:
	if players.has(id):
		players[id].queue_free()
		players.erase(id)


## Broadcast by a dying player's authority: every peer tallies the kill
## identically (and re-emits it as kill_reported for the HUD's feed/banner);
## the killer's peer also resets its own player (kills reset the round —
## both duelists respawn).
@rpc("any_peer", "call_local", "reliable")
func report_kill(killer_id: int, victim_id: int) -> void:
	scores[killer_id] = int(scores.get(killer_id, 0)) + 1
	kill_reported.emit(killer_id, victim_id)
	if killer_id == multiplayer.get_unique_id():
		for p: Node in get_tree().get_nodes_in_group("player"):
			if p.is_multiplayer_authority():
				p.round_reset(true)
				return


@rpc("authority", "call_remote", "reliable")
func _spawn_remote(id: int) -> void:
	_spawn_player(id)


@rpc("authority", "call_remote", "reliable")
func _despawn_remote(id: int) -> void:
	_despawn_player(id)
