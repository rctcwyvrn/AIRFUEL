extends Node

## Autoload "Net" — LAN listen-server multiplayer (prototype tier).
## Client-authoritative movement, no prediction/rewind: correct for ~1ms LAN,
## NOT the shipping §20.2 architecture. Offline play (no CLI args) is untouched.
##
##   host:  godot4 --path game -- --server
##   join:  godot4 --path game -- --client <ip>

const ARENA := "res://maps/graybox_corridor.tscn"
const PORT := 27555
const MAX_PEERS := 8
const PLAYER_SCENE := preload("res://src/player/player.tscn")


var active := false
var is_host := false
var players: Dictionary = {}  # peer id -> AirfuelPlayer


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--server" in args:
		host()
	else:
		var i := args.find("--client")
		if i != -1:
			var ip := "127.0.0.1"
			if i + 1 < args.size() and not args[i + 1].begins_with("--"):
				ip = args[i + 1]
			join(ip)


func host() -> void:
	if active:
		return
	await _load_arena()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PEERS)
	if err != OK:
		push_error("Airfuel net: failed to host on udp/%d (err %d)" % [PORT, err])
		return
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = true
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("Airfuel net: hosting on udp/%d" % PORT)
	_spawn_player(1)


func join(ip: String) -> void:
	if active:
		return
	await _load_arena()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		push_error("Airfuel net: failed to start client for %s (err %d)" % [ip, err])
		return
	multiplayer.multiplayer_peer = peer
	active = true
	multiplayer.connected_to_server.connect(
			func() -> void: print("Airfuel net: joined %s as peer %d" % [ip, multiplayer.get_unique_id()]))
	multiplayer.connection_failed.connect(
			func() -> void: push_error("Airfuel net: connection to %s failed" % ip))
	multiplayer.server_disconnected.connect(
			func() -> void:
				push_error("Airfuel net: server disconnected")
				get_tree().quit())
	print("Airfuel net: connecting to %s:%d..." % [ip, PORT])


## Switch to the arena (from menu or startup), then strip its offline Player
## so per-peer spawns are the only players. Peer creation happens AFTER this,
## so no spawn rpc can arrive while the menu is still the current scene.
func _load_arena() -> void:
	await get_tree().process_frame
	if get_tree().current_scene == null \
			or get_tree().current_scene.scene_file_path != ARENA:
		get_tree().change_scene_to_file(ARENA)
		while get_tree().current_scene == null \
				or get_tree().current_scene.scene_file_path != ARENA:
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


func _spawn_player(id: int) -> void:
	if players.has(id):
		return
	var p := PLAYER_SCENE.instantiate() as CharacterBody3D
	p.name = str(id)
	p.set_multiplayer_authority(id)
	p.transform = _spawn_transform_for_index(players.size())
	get_tree().current_scene.add_child(p)
	players[id] = p
	print("Airfuel net: spawned player %d at %s (mine: %s, cam: %s)" % [
			id, p.global_position, p.is_multiplayer_authority(),
			(p.get_node("Head/Camera3D") as Camera3D).current])


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


## Sent by a dying player's authority to the killer's peer: reset the
## killer's own player too (kills reset the round, both duelists respawn).
@rpc("any_peer", "call_remote", "reliable")
func kill_scored() -> void:
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
