class_name MatchHost
extends Node

## Authoritative match simulation driver (DESIGN.md §20.2, stage N1). Runs on
## whichever process owns the truth: a per-match dedicated child server
## (child_mode, first-to-N, reports and exits) or a LAN listen-server host
## (endless, dynamic peers, the host's own body is LOCAL and needs nothing
## from this node). Each remote client's body is DRIVEN: this node pops that
## client's queued cmds and writes them onto the body every tick (physics
## priority -1, before bodies simulate), then sends state snapshots back
## (reading post-tick state at the START of the next tick, so a snapshot for
## ack tick T is exactly the post-T state prediction replays need).

const CMD_QUEUE_MAX := 4
const SNAPSHOT_INTERVAL := 2  # ticks; 120 Hz sim -> 60 Hz snapshots

var win_kills := 0  # 0 = endless (LAN); >0 = first-to-N (lobby duel)
var child_mode := false  # per-match child process: forfeit on disconnect, quit after
var kills: Dictionary = {}  # peer id -> kills

var _cmd_queues: Dictionary = {}  # peer id -> Array[PackedFloat32Array]
var _last_cmds: Dictionary = {}  # peer id -> last applied cmd (loss coasting)
var _acks: Dictionary = {}  # peer id -> last applied cmd tick
var _tick_count := 0
var _ending := false


func _ready() -> void:
	process_physics_priority = -1  # write cmds BEFORE the bodies' physics tick


func _physics_process(_delta: float) -> void:
	_tick_count += 1
	if _tick_count % SNAPSHOT_INTERVAL == 0:
		_send_snapshots()
	for id: int in Net.players:
		var body := Net.players[id] as AirfuelPlayer
		if body == null or body.role != AirfuelPlayer.NetRole.DRIVEN:
			continue
		var c := _pop_cmd(id)
		if not c.is_empty():
			_acks[id] = int(c[0])
			PlayerState.apply_cmd(body, c)


## Called by Net when a client cmd rpc lands. Rejects stale/rewound ticks
## (unreliable_ordered already drops most); caps backlog by dropping oldest
## cmds but carrying their one-shot flags forward so a queued jump/fire press
## survives the drop.
func queue_cmd(id: int, c: PackedFloat32Array) -> void:
	if c.size() < PlayerState.CMD_SIZE:
		return
	if not _cmd_queues.has(id):
		_cmd_queues[id] = []
		print("Airfuel match: cmds flowing from peer %d" % id)
	var q: Array = _cmd_queues[id]
	if not q.is_empty() and c[0] <= (q.back() as PackedFloat32Array)[0]:
		return
	q.append(c)
	while q.size() > CMD_QUEUE_MAX:
		var dropped: PackedFloat32Array = q.pop_front()
		q[0][4] = float(int(q[0][4]) | int(dropped[4]))


func _pop_cmd(id: int) -> PackedFloat32Array:
	var q: Array = _cmd_queues.get(id, [])
	if q.is_empty():
		# Packet gap: coast on the held directional input, strip one-shot
		# flags (all of flags is one-shots), keep the last view angles.
		var last: PackedFloat32Array = _last_cmds.get(id, PackedFloat32Array())
		if last.is_empty():
			return last
		var coast := last.duplicate()
		coast[4] = 0.0
		return coast
	var c: PackedFloat32Array = q.pop_front()
	_last_cmds[id] = c
	return c


func _send_snapshots() -> void:
	for id: int in Net.players:
		var body := Net.players[id] as AirfuelPlayer
		if body == null or body.role != AirfuelPlayer.NetRole.DRIVEN:
			continue  # only remote clients get snapshots; a LOCAL host body has no client
		var others: Array = []
		for oid: int in Net.players:
			if oid != id:
				others.append((Net.players[oid] as AirfuelPlayer).render_state(oid))
		Net.send_snapshot(id, int(_acks.get(id, 0)), body.capture_state(), others)


## Server-side damage entry point (called by the victim body's apply_damage).
## Broadcasts the damage event; a death scores, resets both duelists (design
## 9: kills reset the round), and can end a first-to-N match.
func on_damage(victim: AirfuelPlayer, attacker_id: int) -> void:
	var victim_id := victim.get_multiplayer_authority()
	Net.broadcast_damage(victim_id, attacker_id, victim.hp)
	if victim.hp > 0:
		return
	kills[attacker_id] = int(kills.get(attacker_id, 0)) + 1
	print("Airfuel match: %d killed %d (%s)" % [attacker_id, victim_id, kills])
	victim._respawn()
	var killer := Net.players.get(attacker_id) as AirfuelPlayer
	if killer != null:
		killer._respawn()
	Net.broadcast_kill(attacker_id, victim_id, kills)
	if win_kills > 0 and int(kills[attacker_id]) >= win_kills:
		end_match(attacker_id, false)


## Server-side shot relay (rail beam fx + authoritative hit result).
func on_shot(
	shooter: AirfuelPlayer, side: String, muzzle: Vector3, end_p: Vector3, result: String
) -> void:
	Net.broadcast_shot(shooter.get_multiplayer_authority(), side, muzzle, end_p, result)


## Child server: a client dropping mid-match forfeits to the survivor.
func on_client_gone(id: int) -> void:
	if not child_mode or _ending:
		return
	for oid: int in Net.players:
		if oid != id:
			end_match(oid, true)
			return


func end_match(winner_id: int, forfeit: bool) -> void:
	if _ending:
		return
	_ending = true
	set_physics_process(false)
	for id: int in Net.players:
		# Freeze bodies too: a pending charge resolving after the clients
		# leave would fire events into their closed channels.
		(Net.players[id] as AirfuelPlayer).set_physics_process(false)
	Net.finish_match(winner_id, forfeit, kills)
