class_name TasGhostController
extends Node

## TAS ghost driver: pilots a real AirfuelPlayer (parent, ghost_controlled)
## through the ACTUAL movement physics by writing its cmd_* inputs each tick
## — jumps cost fuel, dashes obey cooldowns, gravity is real. It chases the
## generator's waypoint line with rate-limited (human-plausible) steering,
## so its speed is whatever the movement system actually yields.

@export var waypoints: PackedVector3Array
@export var tape_path := ""  # a .tas recording; when set, replays it verbatim
@export var turn_rate := 9.0
@export var arrive_dist := 16.0

var body: AirfuelPlayer
var idx := 0
var stall := 0.0
var tape: Array = []
var tick := 0
var tape_loadout := 0


func _ready() -> void:
	process_physics_priority = -1  # write cmds BEFORE the body's physics tick
	body = get_parent() as AirfuelPlayer
	if tape_path != "":
		_load_tape()
	_apply_tape_loadout.call_deferred()
	_link_player.call_deferred()


func _apply_tape_loadout() -> void:
	if not tape.is_empty():
		body.set_loadout(tape_loadout)


func _load_tape() -> void:
	var f := FileAccess.open(tape_path, FileAccess.READ)
	if f == null:
		push_warning("Airfuel ghost: tape not found: %s — using autopilot" % tape_path)
		return
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with("#"):
			for token in line.split(" "):
				if token.begins_with("loadout="):
					tape_loadout = token.trim_prefix("loadout=").to_int()
			continue
		if line.is_empty():
			continue
		var c := line.split(" ")
		if c.size() >= 6:
			tape.append(
				[
					c[0].to_float(),
					c[1].to_float(),
					c[2].to_float(),
					c[3].to_float(),
					c[4].to_float(),
					c[5].to_int()
				]
			)
	print("Airfuel ghost: tape loaded, %d ticks" % tape.size())


func _link_player() -> void:
	for p: Node in get_tree().get_nodes_in_group("player"):
		if p != body and not p.ghost_controlled:
			p.respawned.connect(_restart)
			return


func _restart() -> void:
	idx = 0
	tick = 0
	stall = 0.0
	body._respawn()
	# the tape assumes the loadout it was recorded with — every loop too
	if not tape.is_empty():
		body.set_loadout(tape_loadout)


func _physics_process(delta: float) -> void:
	if body == null or body.countdown > 0.0:
		return
	if not tape.is_empty():
		# fixed-input TAS replay: absolute look + recorded commands per tick
		if tick >= tape.size():
			_restart()
			return
		var r: Array = tape[tick]
		tick += 1
		body.rotation.y = r[0]
		body.head.rotation.x = r[1]
		body.cmd_move = Vector2(r[2], r[3])
		body.cmd_down_dash = r[4] != 0.0
		var fl: int = r[5]
		body.cmd_jump = bool(fl & 1)
		body.cmd_dash = bool(fl & 2)
		body.cmd_fire_l = bool(fl & 4)
		body.cmd_fire_r = bool(fl & 8)
		body.cmd_swap = bool(fl & 16)
		return
	if waypoints.is_empty():
		return
	var target := waypoints[idx]
	var to := target - body.global_position
	var flat_dist := Vector2(to.x, to.z).length()
	var fwd := -body.global_transform.basis.z
	var passed := flat_dist < 28.0 and Vector2(to.x, to.z).dot(Vector2(fwd.x, fwd.z)) < 0.0
	if flat_dist < arrive_dist or passed:
		idx += 1
		stall = 0.0
		if idx >= waypoints.size():
			_restart()
		return
	# orbit/stuck recovery: snap back onto the line rather than looping the
	# whole track — pragmatic TAS splice, rare enough to read as a blink
	stall += delta
	if stall > 8.0:
		body.global_position = waypoints[maxi(idx - 1, 0)]
		body.sim.velocity = Vector3.ZERO
		body.velocity = Vector3.ZERO
		body.sim.fuel = body.config.fuel_max
		stall = 0.0
		return

	# steer like a player: rate-limited yaw, near-level aim (dashes are
	# camera-aimed — pitching hard at high waypoints balloons the flight)
	var desired_yaw := atan2(-to.x, -to.z)
	body.rotation.y = lerp_angle(body.rotation.y, desired_yaw, minf(1.0, turn_rate * delta))
	body.head.rotation.x = clampf(atan2(to.y, flat_dist) * 0.4, -0.55, 0.55)

	body.cmd_move = Vector2(0, -1)  # hold W
	body.cmd_down_dash = false
	body.cmd_jump = false
	body.cmd_dash = false

	var hspeed := body.horizontal_speed()
	if body.is_on_floor():
		if to.y > 2.0 or hspeed < 15.0:
			body.cmd_jump = true
	elif to.y > 3.0 and body.velocity.y < 4.0:
		body.cmd_jump = true  # climb: double jump whenever rise is fading
	# dashes are the fuel hogs: spend only with a deep tank so climbs
	# always have double-jump budget left
	if (
		hspeed < 26.0
		and to.y > -3.0
		and body.sim.fuel > 80.0
		and body.sim.dash_cooldown_timer == 0.0
	):
		body.cmd_dash = true
