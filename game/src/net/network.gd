extends Node

## Autoload "Net" — server-authoritative multiplayer (§20.2 stage N1).
## One netcode path everywhere: an authoritative process simulates every body
## from per-tick input cmds (MatchHost + DRIVEN/LOCAL bodies), clients
## predict their own body and render REPLICA puppets from snapshots.
##
## Topologies:
## - LAN listen server (host simulates, host's own body is a zero-latency
##   LOCAL; endless scoring):
##     host:  godot4 --path game -- --server
##     join:  godot4 --path game -- --client <ip>
## - Dedicated lobby (matchmaker ONLY — never simulates): spawns one child
##   match-server process per duel and hands both clients its port; clients
##   hop to it, duel first-to-N, then rejoin the lobby and report the result
##   (W–L records are name-keyed so they survive the hop):
##     serve: godot4 --headless --path game -- --dedicated
##     join:  godot4 --path game -- --lobby <ip> --name <username>
##     child: (spawned internally) -- --match-server --port N --token T
##            --win-kills K
##
## Offline play (no CLI args, no menu action) is untouched.
## Dev/test flags: --autoduel (auto challenge/accept + autofire),
## --fake-lag <ms> (client-side artificial round-trip latency).

signal kill_reported(killer_id: int, victim_id: int)
signal roster_updated(roster: Array)
signal challenge_received(from_id: int, from_name: String)
signal challenge_ended(reason: String)
signal net_error(message: String)

enum Mode { OFFLINE, LAN, LOBBY, DEDICATED, MATCH_CLIENT, MATCH_SERVER }

const ARENA := "res://maps/graybox_corridor.tscn"
const LOBBY_SCENE := "res://src/lobby/lobby.tscn"
const MENU_SCENE := "res://src/menu/main_menu.tscn"
const DEFAULT_SERVER := "play.airfuel-game.com"  # blank JOIN SERVER field / bare --lobby
# NOTE: must stay a DNS-only (grey-cloud) record — Cloudflare's proxy can't
# carry the game's UDP. The bare domain is Proxied and serves the homepage.
const PORT := 27555
const MAX_PEERS := 8  # LAN listen-server cap; the lobby cap is config
const PLAYER_SCENE := preload("res://src/player/player.tscn")
const SERVER_CONFIG := preload("res://src/net/default_server.tres")

var mode := Mode.OFFLINE
var active := false
var is_host := false
var headless := false
var players: Dictionary = {}  # peer id -> AirfuelPlayer (all roles)
var scores: Dictionary = {}  # peer id -> kills, server-fed via _ev_kill
var match_host: MatchHost = null  # non-null exactly on the simulating process

# Lobby client state
var my_name := ""
var last_error := ""  # cached for the menu (a failure may land mid-scene-change)
var lobby_address := ""  # where to rejoin after a match
var match_names: Dictionary = {}  # peer id -> username (both duelists)
var last_roster: Array = []  # cache so the lobby scene can render on entry
var last_match_result: Dictionary = {}  # {won, forfeit, text} for the lobby banner

var autoduel := false  # test aid: auto challenge/accept + autofire in match
var fake_lag_ms := 0  # test aid: artificial round-trip latency on cmds + snapshots
# Test aid (--spawn-gap <m>, lobby forwards it to children): spawn side 1
# this many meters from side 0 at the clear -z end instead of across the
# corridor, giving headless autofire duels line of sight. 0 = normal ends.
var match_spawn_gap := 0
# Test aid (--rewind-ms <ms>, lobby forwards it to children): overrides
# ServerConfig.rewind_max_ms (-1 = no override). 0 disables rewind — the
# A/B lever for proving lag compensation does something.
var rewind_ms_override := -1

# Dedicated lobby state (matchmaker process only)
var cfg: ServerConfig = SERVER_CONFIG
var roster: Dictionary = {}  # peer id -> {name, wins, losses, match_id}
var records: Dictionary = {}  # username -> {wins, losses}; survives reconnects
var matches: Dictionary = {}  # match id -> {a_name, b_name, port, pid, deadline}
var next_match_id := 1
var pending_challenges: Dictionary = {}  # challenger id -> {target, time_left}
var _match_port_cursor := 0  # rotating allocation; see _alloc_match_port

# Child match-server state
var match_token := 0
var _hello_names: Dictionary = {}  # peer id -> username, pre-match handshake
var _match_started := false

var _spawn_indices: Dictionary = {}  # peer id -> spawn index
var _pending_report: Dictionary = {}  # result to deliver on lobby rejoin
var _autoduel_sent := false
var _lag_out: Array = []  # [{at, cmd}] delayed outgoing cmds
var _lag_in: Array = []  # [{at, ack, own, others}] delayed snapshots


func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"
	var args := OS.get_cmdline_user_args()
	autoduel = "--autoduel" in args
	fake_lag_ms = int(_arg_value(args, "--fake-lag", "0"))
	match_spawn_gap = int(_arg_value(args, "--spawn-gap", "0"))
	rewind_ms_override = int(_arg_value(args, "--rewind-ms", "-1"))
	if "--dedicated" in args:
		host_dedicated()
	elif "--match-server" in args:
		match_serve(
			int(_arg_value(args, "--port", "0")),
			int(_arg_value(args, "--token", "0")),
			int(_arg_value(args, "--win-kills", "5"))
		)
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


## ---- LAN listen server (server-auth: the host simulates everyone) ----


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
	_attach_match_host(0, false)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("Airfuel net: hosting on udp/%d" % PORT)
	_spawn_player(1, 0, AirfuelPlayer.NetRole.LOCAL)


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


func _on_peer_connected(id: int) -> void:
	print("Airfuel net: peer %d connected" % id)
	var index := players.size()
	for existing_id: int in players:
		_spawn_remote.rpc_id(id, existing_id, int(_spawn_indices.get(existing_id, 0)))
	_spawn_remote.rpc(id, index)
	_spawn_player(id, index, AirfuelPlayer.NetRole.DRIVEN)


func _on_peer_disconnected(id: int) -> void:
	print("Airfuel net: peer %d disconnected" % id)
	# No despawn relay on a match child: a client leaving there means the
	# match is over and the other client is leaving too (racing its channel).
	if mode != Mode.MATCH_SERVER:
		for pid: int in multiplayer.get_peers():
			if pid != id:  # live peers only
				_despawn_remote.rpc_id(pid, id)
	_despawn_player(id)
	if mode == Mode.MATCH_SERVER and match_host != null:
		match_host.on_client_gone(id)


## ---- Dedicated lobby server (matchmaker only, never simulates) ----


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
			"Airfuel lobby: matchmaker on udp/%d (%d peers max, duels first to %d on udp %d-%d)"
			% [
				PORT,
				cfg.max_peers,
				cfg.duel_win_kills,
				cfg.match_port_start,
				cfg.match_port_start + cfg.match_port_count - 1,
			]
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
	lobby_address = ip
	multiplayer.connected_to_server.connect(
		func() -> void:
			print("Airfuel lobby: joined %s as peer %d" % [ip, multiplayer.get_unique_id()])
			_register.rpc_id(1, my_name)
			if not _pending_report.is_empty():
				_report_result.rpc_id(1, _pending_report.winner, _pending_report.loser)
				_pending_report = {}
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


## ---- Per-match child server ----


## Boot mode for the child process the lobby spawns: one arena, exactly two
## token-checked clients, first-to-N, then report-via-clients and exit.
func match_serve(port: int, token: int, win_kills: int) -> void:
	if active:
		return
	if port == 0:
		push_error("Airfuel match-server: no --port given")
		get_tree().quit(1)
		return
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 2)
	if err != OK:
		push_error("Airfuel match-server: can't bind udp/%d (%s)" % [port, error_string(err)])
		get_tree().quit(1)
		return
	_clear_session_signals()
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = true
	mode = Mode.MATCH_SERVER
	match_token = token
	_attach_match_host(win_kills, true)
	multiplayer.peer_connected.connect(
		func(id: int) -> void: print("Airfuel match: peer %d connected" % id)
	)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("Airfuel match-server: udp/%d, first to %d" % [port, win_kills])
	get_tree().create_timer(cfg.match_hello_timeout).timeout.connect(
		func() -> void:
			if not _match_started:
				print("Airfuel match-server: nobody showed up, exiting")
				get_tree().quit()
	)
	get_tree().create_timer(cfg.match_max_seconds).timeout.connect(
		func() -> void:
			if match_host != null:
				match_host.end_match(0, false)  # stalemate guard: winner 0 = draw
	)


func _attach_match_host(win_kills: int, child: bool) -> void:
	match_host = MatchHost.new()
	match_host.name = "MatchHost"
	match_host.win_kills = win_kills
	match_host.child_mode = child
	add_child(match_host)


## Client -> match server, first thing after connecting: prove the lobby sent
## you (token) and say who you are. Two valid hellos start the match.
@rpc("any_peer", "call_remote", "reliable")
func _hello(token: int, username: String) -> void:
	if mode != Mode.MATCH_SERVER:
		return
	var id := multiplayer.get_remote_sender_id()
	if _match_started:
		# Stray connection (e.g. a new match mistakenly pointed at this
		# port): kick so the client fails fast instead of hanging.
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(id)
		return
	if token != match_token:
		print("Airfuel match-server: bad token from peer %d, kicking" % id)
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(id)
		return
	_hello_names[id] = username
	if _hello_names.size() == 2:
		_begin_child_match()


func _begin_child_match() -> void:
	_match_started = true
	var ids: Array = _hello_names.keys()
	ids.sort()  # deterministic side assignment: lower peer id gets side 0 (-z)
	var names: Array = ids.map(func(i: int) -> String: return _hello_names[i])
	match_names = {}
	for i in ids.size():
		match_names[ids[i]] = names[i]
	for id: int in ids:
		_begin_match.rpc_id(id, ids, names, match_spawn_gap)
	await _load_arena()
	for i in ids.size():
		_spawn_player(ids[i], i, AirfuelPlayer.NetRole.DRIVEN)
	for id: int in ids:
		(players[id] as AirfuelPlayer)._respawn()  # 3-2-1 countdown, then GO
	print("Airfuel match-server: %s vs %s" % [names[0], names[1]])


## Server -> both clients: the pair (ordered by spawn side) and their names.
@rpc("authority", "call_remote", "reliable")
func _begin_match(ids: Array, names: Array, spawn_gap: int = 0) -> void:
	match_spawn_gap = spawn_gap
	match_names = {}
	for i in ids.size():
		match_names[int(ids[i])] = str(names[i])
	scores = {}
	for id: int in match_names:
		scores[id] = 0
	await _load_arena()
	var my_id := multiplayer.get_unique_id()
	for i in ids.size():
		var id := int(ids[i])
		var role := (
			AirfuelPlayer.NetRole.PREDICTED if id == my_id else AirfuelPlayer.NetRole.REPLICA
		)
		_spawn_player(id, i, role)


## ---- Cmd / snapshot plumbing ----


## Called by the local PREDICTED body every tick.
func send_cmd(c: PackedFloat32Array) -> void:
	if fake_lag_ms > 0:
		_lag_out.append({at = Time.get_ticks_msec() + fake_lag_ms / 2.0, cmd = c})
		return
	_client_cmd.rpc_id(1, c)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _client_cmd(c: PackedFloat32Array) -> void:
	if match_host != null:
		match_host.queue_cmd(multiplayer.get_remote_sender_id(), c)


## Effective rewind window: the test override beats config.
func rewind_ms() -> float:
	return float(rewind_ms_override) if rewind_ms_override >= 0 else cfg.rewind_max_ms


## Called by MatchHost for each remote client.
func send_snapshot(
	id: int, server_tick: int, ack: int, own: PackedFloat32Array, others: Array
) -> void:
	_snapshot.rpc_id(id, server_tick, ack, own, others)


@rpc("authority", "call_remote", "unreliable_ordered")
func _snapshot(server_tick: int, ack: int, own: PackedFloat32Array, others: Array) -> void:
	if fake_lag_ms > 0:
		(
			_lag_in
			. append(
				{
					at = Time.get_ticks_msec() + fake_lag_ms / 2.0,
					tick = server_tick,
					ack = ack,
					own = own,
					others = others,
				}
			)
		)
		return
	_apply_snapshot(server_tick, ack, own, others)


func _apply_snapshot(server_tick: int, ack: int, own: PackedFloat32Array, others: Array) -> void:
	var me := players.get(multiplayer.get_unique_id()) as AirfuelPlayer
	if me != null:
		me.seen_server_tick = server_tick  # echoed in cmds; the rewind target
		me.on_server_snapshot(ack, own)
	for pair: Array in others:
		var rep := players.get(int(pair[0])) as AirfuelPlayer
		if rep != null and rep.role == AirfuelPlayer.NetRole.REPLICA:
			rep.apply_replica(pair[1])


## ---- Server -> client event fan-out ----
## Broadcast helpers run on the simulating process: rpc to every remote
## client, plus a direct local call when the host is also a player (LAN).


func _client_peer_ids() -> Array:
	# Filtered to live connections: DRIVEN bodies can outlive their client for
	# a beat (e.g. a pending charge resolving right after match end), and
	# events aimed at a dropped peer just spam ENet send errors.
	var live := multiplayer.get_peers()
	var ids: Array = []
	for id: int in players:
		if (players[id] as AirfuelPlayer).role == AirfuelPlayer.NetRole.DRIVEN and id in live:
			ids.append(id)
	return ids


func _host_plays() -> bool:
	return mode == Mode.LAN and is_host


func broadcast_shot(
	shooter_id: int, side: String, muzzle: Vector3, end_p: Vector3, result: String
) -> void:
	for id: int in _client_peer_ids():
		_ev_shot.rpc_id(id, shooter_id, side, muzzle, end_p, result)
	if _host_plays():
		_handle_shot(shooter_id, side, muzzle, end_p, result)


@rpc("authority", "call_remote", "reliable")
func _ev_shot(
	shooter_id: int, side: String, muzzle: Vector3, end_p: Vector3, result: String
) -> void:
	_handle_shot(shooter_id, side, muzzle, end_p, result)


func _handle_shot(
	shooter_id: int, side: String, muzzle: Vector3, end_p: Vector3, result: String
) -> void:
	var body := players.get(shooter_id) as AirfuelPlayer
	if body == null:
		return
	if shooter_id == multiplayer.get_unique_id():
		body.shot_fired.emit(side, result)  # authoritative hitmarker; beam was predicted
	elif body.role == AirfuelPlayer.NetRole.REPLICA:
		# Opponent fx: their predicted client already played its own.
		PlayerFx.spawn_beam(body.get_parent(), muzzle, end_p)
		PlayerFx.play_rail_sound(body.get_parent(), muzzle)


func broadcast_damage(victim_id: int, attacker_id: int, hp_left: int) -> void:
	for id: int in _client_peer_ids():
		_ev_damage.rpc_id(id, victim_id, attacker_id, hp_left)
	if _host_plays():
		_handle_damage(victim_id, attacker_id, hp_left)


@rpc("authority", "call_remote", "reliable")
func _ev_damage(victim_id: int, attacker_id: int, hp_left: int) -> void:
	_handle_damage(victim_id, attacker_id, hp_left)


func _handle_damage(victim_id: int, attacker_id: int, hp_left: int) -> void:
	if victim_id != multiplayer.get_unique_id():
		return
	var me := players.get(victim_id) as AirfuelPlayer
	if me != null:
		me.on_net_damage(attacker_id, hp_left)


func broadcast_kill(killer_id: int, victim_id: int, kills: Dictionary) -> void:
	scores = kills.duplicate()
	for id: int in _client_peer_ids():
		_ev_kill.rpc_id(id, killer_id, victim_id, kills)
	if _host_plays():
		kill_reported.emit(killer_id, victim_id)


@rpc("authority", "call_remote", "reliable")
func _ev_kill(killer_id: int, victim_id: int, kills: Dictionary) -> void:
	scores = kills
	kill_reported.emit(killer_id, victim_id)


## Child server, match decided: tell both clients, then exit. winner_id 0 is
## the stalemate-guard draw.
func finish_match(winner_id: int, forfeit: bool, kills: Dictionary) -> void:
	if mode != Mode.MATCH_SERVER:
		return  # LAN is endless; nothing to finish
	for id: int in _client_peer_ids():
		_ev_match_over.rpc_id(id, winner_id, forfeit, kills)
	print(
		(
			"Airfuel match-server: over, winner %s%s"
			% [match_names.get(winner_id, "DRAW"), " (forfeit)" if forfeit else ""]
		)
	)
	get_tree().create_timer(2.0).timeout.connect(func() -> void: get_tree().quit())


@rpc("authority", "call_remote", "reliable")
func _ev_match_over(winner_id: int, forfeit: bool, kills: Dictionary) -> void:
	var my_id := multiplayer.get_unique_id()
	var opp := 0
	for id: int in match_names:
		if id != my_id:
			opp = id
	var won := winner_id == my_id
	var text: String
	if winner_id == 0:
		text = "DRAW vs %s" % match_names.get(opp, "?")
	else:
		text = (
			"%s %d — %d vs %s"
			% [
				"WON" if won else "LOST",
				int(kills.get(my_id, 0)),
				int(kills.get(opp, 0)),
				match_names.get(opp, "?"),
			]
		)
	last_match_result = {won = won, forfeit = forfeit, text = text}
	if winner_id != 0:
		_pending_report = {
			winner = match_names.get(winner_id, "?"),
			loser = match_names.get(opp if won else my_id, "?"),
		}
	_return_to_lobby()


## Tear down the match connection and rejoin the lobby we came from.
func _return_to_lobby() -> void:
	for p: Node in players.values():
		if is_instance_valid(p):
			p.queue_free()
	players.clear()
	_spawn_indices.clear()
	scores.clear()
	match_names.clear()
	_lag_out.clear()
	_lag_in.clear()
	_autoduel_sent = false  # --autoduel soaks: re-challenge every lobby visit
	_clear_session_signals()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	active = false
	mode = Mode.OFFLINE
	if lobby_address != "":
		join_lobby(lobby_address, my_name)
	else:
		_teardown_to_menu()


## ---- Lobby protocol (matchmaker = peer 1; all reliable) ----

@rpc("any_peer", "call_remote", "reliable")
func _register(username: String) -> void:
	if mode != Mode.DEDICATED:
		return
	var id := multiplayer.get_remote_sender_id()
	var uname := _unique_name(username)
	var rec: Dictionary = records.get(uname, {wins = 0, losses = 0})
	records[uname] = rec
	roster[id] = {name = uname, wins = rec.wins, losses = rec.losses, match_id = 0}
	print("Airfuel lobby: peer %d registered as '%s'" % [id, uname])
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
	# Per-registrant rpc_id filtered to live, NOT-in-match peers: duelists
	# drop their lobby connection the moment _match_launch lands, so sending
	# them roster updates races their closed channel (ENet send errors).
	# They get a fresh roster when they return and re-register anyway.
	var live := multiplayer.get_peers()
	for id: int in roster:
		if id in live and roster[id].match_id == 0:
			_roster_sync.rpc_id(id, arr)


@rpc("authority", "call_remote", "reliable")
func _roster_sync(arr: Array) -> void:
	last_roster = arr
	roster_updated.emit(arr)
	# Headless test aid: the highest-id idle peer challenges the lowest, once.
	if autoduel and not _autoduel_sent and mode == Mode.LOBBY:
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
		_challenge_result.rpc_id(from, false, "unavailable")
		return
	pending_challenges[from] = {target = target_id, time_left = cfg.challenge_timeout}
	_challenge_offer.rpc_id(target_id, from, roster[from].name)


func _is_challenge_target(id: int) -> bool:
	return pending_challenges.values().any(func(c: Dictionary) -> bool: return c.target == id)


@rpc("authority", "call_remote", "reliable")
func _challenge_offer(from_id: int, from_name: String) -> void:
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
		_challenge_result.rpc_id(challenger_id, false, "declined")


@rpc("authority", "call_remote", "reliable")
func _challenge_result(_accepted: bool, reason: String) -> void:
	challenge_ended.emit(reason)


@rpc("authority", "call_remote", "reliable")
func _challenge_withdrawn() -> void:
	challenge_ended.emit("withdrawn")


## Housekeeping ticks: fake-lag queues (clients), challenge timeouts and
## match expiry (matchmaker).
func _process(delta: float) -> void:
	if fake_lag_ms > 0:
		var now := Time.get_ticks_msec()
		while not _lag_out.is_empty() and _lag_out[0].at <= now:
			var o: Dictionary = _lag_out.pop_front()
			if mode == Mode.MATCH_CLIENT or (mode == Mode.LAN and not is_host):
				_client_cmd.rpc_id(1, o.cmd)
		while not _lag_in.is_empty() and _lag_in[0].at <= now:
			var s: Dictionary = _lag_in.pop_front()
			_apply_snapshot(s.tick, s.ack, s.own, s.others)
	if mode != Mode.DEDICATED:
		return
	for from: int in pending_challenges.keys():
		pending_challenges[from].time_left -= delta
		if pending_challenges[from].time_left <= 0.0:
			var target: int = pending_challenges[from].target
			pending_challenges.erase(from)
			_challenge_result.rpc_id(from, false, "timeout")
			_challenge_withdrawn.rpc_id(target)
	for mid: int in matches.keys():
		matches[mid].deadline -= delta
		if matches[mid].deadline <= 0.0:
			print("Airfuel lobby: match %d expired unreported, freeing port" % mid)
			_close_match(mid, "")


## ---- Match lifecycle (matchmaker side) ----


func _start_match(a: int, b: int) -> void:
	var port := _alloc_match_port()
	if port == 0:
		_challenge_result.rpc_id(a, false, "unavailable")
		_challenge_withdrawn.rpc_id(b)
		return
	var token := randi()
	var args: PackedStringArray = ["--headless"]
	if OS.has_feature("editor"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	(
		args
		. append_array(
			[
				"--",
				"--match-server",
				"--port",
				str(port),
				"--token",
				str(token),
				"--win-kills",
				str(cfg.duel_win_kills),
			]
		)
	)
	if match_spawn_gap > 0:
		args.append_array(["--spawn-gap", str(match_spawn_gap)])
	if rewind_ms_override >= 0:
		args.append_array(["--rewind-ms", str(rewind_ms_override)])
	var pid := OS.create_process(OS.get_executable_path(), args)
	if pid == -1:
		_fail("Couldn't spawn a match server process.")
		_challenge_result.rpc_id(a, false, "unavailable")
		_challenge_withdrawn.rpc_id(b)
		return
	var mid := next_match_id
	next_match_id += 1
	matches[mid] = {
		a_name = roster[a].name,
		b_name = roster[b].name,
		port = port,
		pid = pid,
		deadline = cfg.match_result_timeout,
	}
	roster[a].match_id = mid
	roster[b].match_id = mid
	_match_launch.rpc_id(a, port, token, roster[b].name)
	_match_launch.rpc_id(b, port, token, roster[a].name)
	print(
		(
			"Airfuel lobby: match %d — %s vs %s on udp/%d (pid %d)"
			% [mid, roster[a].name, roster[b].name, port, pid]
		)
	)
	_broadcast_roster()


## Rotating, not first-free: a just-finished child lingers ~2 s to flush its
## final events, so its port must not be re-handed out immediately (bind
## failure). Rotation only revisits a port after the whole range cycled.
func _alloc_match_port() -> int:
	for i in cfg.match_port_count:
		var port: int = cfg.match_port_start + (_match_port_cursor + i) % cfg.match_port_count
		var taken := false
		for m: Dictionary in matches.values():
			if int(m.port) == port:
				taken = true
				break
		if not taken:
			_match_port_cursor = (_match_port_cursor + i + 1) % cfg.match_port_count
			return port
	return 0


## Lobby -> both duelists: hop to your private match server.
@rpc("authority", "call_remote", "reliable")
func _match_launch(port: int, token: int, opponent_name: String) -> void:
	print("Airfuel: match ready vs %s on udp/%d, connecting..." % [opponent_name, port])
	_clear_session_signals()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(lobby_address, port)
	if err != OK:
		_fail("Couldn't start the match client (%s)." % error_string(err))
		_return_to_lobby()
		return
	multiplayer.multiplayer_peer = peer
	mode = Mode.MATCH_CLIENT
	multiplayer.connected_to_server.connect(func() -> void: _hello.rpc_id(1, token, my_name))
	multiplayer.connection_failed.connect(
		func() -> void:
			_fail("Couldn't reach the match server on udp/%d." % port)
			_return_to_lobby.call_deferred()
	)
	multiplayer.server_disconnected.connect(
		func() -> void:
			# Normal after _ev_match_over (the child exits); anything earlier
			# is a crash — either way the lobby is the place to land.
			if mode == Mode.MATCH_CLIENT:
				_return_to_lobby.call_deferred()
	)


## Winner/loser by name, reported by returning duelists (both report; the
## first one closes the match, the duplicate finds nothing and is ignored).
@rpc("any_peer", "call_remote", "reliable")
func _report_result(winner_name: String, loser_name: String) -> void:
	if mode != Mode.DEDICATED:
		return
	for mid: int in matches:
		var m: Dictionary = matches[mid]
		var pair: Array = [m.a_name, m.b_name]
		if winner_name in pair and loser_name in pair and winner_name != loser_name:
			_close_match(mid, winner_name)
			return


## Close a match record: settle name-keyed W–L (empty winner = abandoned, no
## records change), refresh any present roster entries, free the port.
func _close_match(mid: int, winner_name: String) -> void:
	var m: Dictionary = matches[mid]
	matches.erase(mid)
	if winner_name != "":
		for entry_name: String in [m.a_name, m.b_name]:
			var rec: Dictionary = records.get(entry_name, {wins = 0, losses = 0})
			if entry_name == winner_name:
				rec.wins += 1
			else:
				rec.losses += 1
			records[entry_name] = rec
	for id: int in roster:
		if roster[id].match_id == mid:
			roster[id].match_id = 0
		var rec2: Dictionary = records.get(roster[id].name, {})
		if not rec2.is_empty():
			roster[id].wins = rec2.wins
			roster[id].losses = rec2.losses
	if winner_name != "":
		print("Airfuel lobby: match %d closed, %s wins" % [mid, winner_name])
	_broadcast_roster()


func _on_lobby_peer_disconnected(id: int) -> void:
	print("Airfuel lobby: peer %d disconnected" % id)
	roster.erase(id)
	pending_challenges.erase(id)
	for from: int in pending_challenges.keys():
		if pending_challenges[from].target == id:
			pending_challenges.erase(from)
			_challenge_result.rpc_id(from, false, "unavailable")
	# A matched player disconnecting is EXPECTED — they hopped to their match
	# server; the match record carries their name until the result comes back.
	_broadcast_roster()


## ---- Shared plumbing ----


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
		multiplayer.peer_disconnected,
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
	_spawn_indices.clear()
	scores.clear()
	match_names.clear()
	last_roster = []
	last_match_result = {}
	_pending_report = {}
	_autoduel_sent = false
	_lag_out.clear()
	_lag_in.clear()
	if match_host != null:
		match_host.queue_free()
		match_host = null
	active = false
	is_host = false
	mode = Mode.OFFLINE
	_clear_session_signals()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var cur := get_tree().current_scene
	if cur == null or cur.scene_file_path != MENU_SCENE:
		get_tree().change_scene_to_file(MENU_SCENE)


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
	# PvP arena: no practice dummies in netplay sessions
	for dummy: Node in get_tree().get_nodes_in_group("target"):
		dummy.free()


@rpc("authority", "call_remote", "reliable")
func _spawn_remote(id: int, index: int) -> void:
	var role := (
		AirfuelPlayer.NetRole.PREDICTED
		if id == multiplayer.get_unique_id()
		else AirfuelPlayer.NetRole.REPLICA
	)
	_spawn_player(id, index, role)


@rpc("authority", "call_remote", "reliable")
func _despawn_remote(id: int) -> void:
	_despawn_player(id)


func _spawn_player(id: int, index: int, role: AirfuelPlayer.NetRole) -> void:
	if players.has(id):
		return
	var p := PLAYER_SCENE.instantiate() as AirfuelPlayer
	p.name = str(id)
	p.set_multiplayer_authority(id)
	p.role = role
	p.transform = _spawn_transform_for_index(index)
	get_tree().current_scene.add_child(p)
	players[id] = p
	_spawn_indices[id] = index
	print("Airfuel net: spawned player %d at %s (role %d)" % [id, p.global_position, role])


## Spawns alternate ends (even index: -z facing +z, odd: +z facing -z) and
## spread laterally for 3+ players. Index = spawn order on the server, which
## drives every peer's spawns, so it is identical everywhere.
func _spawn_transform_for_index(index: int) -> Transform3D:
	if match_spawn_gap > 0 and index == 1:
		# Test spawn: face -z back toward side 0 from just up the corridor
		return Transform3D(Basis(), Vector3(0.0, 2.6, -430.0 + float(match_spawn_gap)))
	var x := float(index >> 1) * 8.0  # lateral spread per pair (deliberate int halving)
	if index % 2 == 0:
		return Transform3D(Basis(Vector3.UP, PI), Vector3(x, 2.6, -430.0))
	return Transform3D(Basis(), Vector3(x, 2.6, 430.0))


func _despawn_player(id: int) -> void:
	if players.has(id):
		players[id].queue_free()
		players.erase(id)
		_spawn_indices.erase(id)
