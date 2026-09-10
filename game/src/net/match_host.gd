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
var _pos_history: Dictionary = {}  # peer id -> {server tick: Vector3} (rewind, §20.2 N2)
var _tick_count := 0
var _ending := false


func _ready() -> void:
	process_physics_priority = -1  # write cmds BEFORE the bodies' physics tick


func _physics_process(_delta: float) -> void:
	# Runs before the bodies' tick, so the state visible here is the post-tick
	# state of server tick `_tick_count`: record it in the rewind history and
	# stamp outgoing snapshots with that same tick — the tick a client later
	# echoes back as seen_server_tick indexes this history exactly.
	_record_history()
	if _tick_count % SNAPSHOT_INTERVAL == 0:
		_send_snapshots()
	_tick_count += 1
	for id: int in Net.players:
		var body := Net.players[id] as AirfuelPlayer
		if body == null or body.role != AirfuelPlayer.NetRole.DRIVEN:
			continue
		var c := _pop_cmd(id)
		if not c.is_empty():
			_acks[id] = int(c[0])
			PlayerState.apply_cmd(body, c)


func _record_history() -> void:
	var oldest := _tick_count - _rewind_window_ticks()
	for id: int in Net.players:
		var body := Net.players[id] as AirfuelPlayer
		if body == null or not body.sim_active():
			continue
		if not _pos_history.has(id):
			_pos_history[id] = {}
		var h: Dictionary = _pos_history[id]
		h[_tick_count] = body.global_position
		for t: int in h.keys():
			if t < oldest:
				h.erase(t)


func _rewind_window_ticks() -> int:
	return int(ceilf(Net.rewind_ms() / 1000.0 * float(Engine.physics_ticks_per_second)))


## The server tick a shooter's hits are evaluated at: what their client had
## rendered when the trigger was pulled, clamped to the rewind window. A
## LOCAL body (LAN host) sees the present — no rewind.
func _rewind_tick_for(shooter: AirfuelPlayer) -> int:
	if shooter.role == AirfuelPlayer.NetRole.LOCAL or shooter.seen_server_tick == 0:
		return _tick_count
	return clampi(shooter.seen_server_tick, _tick_count - _rewind_window_ticks(), _tick_count)


## A body's position at the shooter's rewind tick (falls back to its current
## position when history is missing). Used by the sword's reach check.
func rewound_position(victim: AirfuelPlayer, shooter: AirfuelPlayer) -> Vector3:
	var h: Dictionary = _pos_history.get(victim.get_multiplayer_authority(), {})
	return h.get(_rewind_tick_for(shooter), victim.global_position)


## Lag-compensated rail hit (§20.2 N2). The static world is raycast for
## occlusion at its live state (walls don't move); player victims are tested
## analytically as capsules at their REWOUND positions — no physics-server
## mutation, so no move-bodies-mid-tick sync hazards. Returns
## {end: Vector3, victim: AirfuelPlayer or null}.
func eval_rail_hit(
	shooter: AirfuelPlayer, from: Vector3, dir: Vector3, max_range: float
) -> Dictionary:
	var d_end := max_range
	var space := shooter.get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(from, from + dir * max_range, 1)
	var wall := space.intersect_ray(params)
	if not wall.is_empty():
		d_end = from.distance_to(wall.position)
	var rewind_tick := _rewind_tick_for(shooter)
	var victim: AirfuelPlayer = null
	for id: int in Net.players:
		var body := Net.players[id] as AirfuelPlayer
		if body == null or body == shooter or not body.sim_active() or body.ghost_controlled:
			continue
		var h: Dictionary = _pos_history.get(id, {})
		var pos: Vector3 = h.get(rewind_tick, body.global_position)
		var shape := body.get_node("CollisionShape3D") as CollisionShape3D
		var capsule := shape.shape as CapsuleShape3D
		var half_seg := capsule.height / 2.0 - capsule.radius
		var d := _ray_capsule_hit(
			from, dir, pos + Vector3.DOWN * half_seg, pos + Vector3.UP * half_seg, capsule.radius
		)
		if d >= 0.0 and d < d_end:
			d_end = d
			victim = body
	if victim != null and rewind_tick != _tick_count:
		print(
			(
				"Airfuel match: rewound hit, %d ticks (%.0f ms)"
				% [
					_tick_count - rewind_tick,
					(_tick_count - rewind_tick) * 1000.0 / Engine.physics_ticks_per_second,
				]
			)
		)
	return {end = from + dir * d_end, victim = victim}


## Analytic ray-vs-capsule (segment a-b, radius r): distance along the ray to
## the entry point, or -1.0 on miss. Cylinder quadratic plus sphere caps.
func _ray_capsule_hit(ro: Vector3, rd: Vector3, a: Vector3, b: Vector3, r: float) -> float:
	var ba := b - a
	var oa := ro - a
	var baba := ba.dot(ba)
	var bard := ba.dot(rd)
	var baoa := ba.dot(oa)
	var rdoa := rd.dot(oa)
	var oaoa := oa.dot(oa)
	var qa := baba - bard * bard
	var qb := baba * rdoa - baoa * bard
	var qc := baba * oaoa - baoa * baoa - r * r * baba
	if absf(qa) > 1e-6:
		var h := qb * qb - qa * qc
		if h >= 0.0:
			var t := (-qb - sqrt(h)) / qa
			var y := baoa + t * bard
			if t >= 0.0 and y > 0.0 and y < baba:
				return t  # cylindrical body hit
	# End caps (also covers rays parallel to the axis)
	var best := -1.0
	for cap: Vector3 in [a, b]:
		var oc := ro - cap
		var cb := rd.dot(oc)
		var cc := oc.dot(oc) - r * r
		var ch := cb * cb - cc
		if ch >= 0.0:
			var t2 := -cb - sqrt(ch)
			if t2 >= 0.0 and (best < 0.0 or t2 < best):
				best = t2
	return best


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
				# [id, row] pairs: the id must ride as a real int — float32
				# arrays corrupt 10-digit peer ids (see render_state).
				others.append([oid, (Net.players[oid] as AirfuelPlayer).render_state()])
		Net.send_snapshot(id, _tick_count, int(_acks.get(id, 0)), body.capture_state(), others)


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
