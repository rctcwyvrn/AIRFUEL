class_name PlayerState
extends Object

## Rollback-state codec for AirfuelPlayer (§20.2 N1): everything a tick's
## outcome depends on, packed as a fixed-layout PackedFloat32Array. Captured
## post-tick on the server (snapshots), captured/restored on predicting
## clients (reconciliation). View angles are deliberately absent — they are
## client-authoritative and travel with cmds, never with state.
##
## Layout: [0-2] pos, [3-5] vel, [6] fuel, [7] move state, [8-10] wall
## normal, [11] wall speed, [12] wallrun time, [13-15] last wall normal,
## [16] wall rearm, [17] ramp grace, [18] dash cd, [19] double jump,
## [20] wall coyote, [21-23] coyote wall normal, [24] coyote wall speed,
## [25] ground coyote, [26] jump buffer, [27] countdown, [28] hp,
## [29] shot gap, [30-31] sword cds, [32] sword active, [33] sword side,
## [34] loadout, [35-37] arm L (state, charge, cooldown), [38-40] arm R,
## [41] pending-fire queue code.

const SIZE := 42
const PENDING_CODES: Array = [[], ["L"], ["R"], ["L", "R"], ["R", "L"]]

# Cmd wire format: [tick, move.x, move.y, down_dash, flags, yaw, pitch,
# seen_server_tick] — flags bit order matches the TAS tape
# (jump|dash|fireL|fireR|swap|respawn). seen_server_tick is the newest
# server tick the client had rendered when it issued this cmd — the
# server-side rewind (§20.2 N2) evaluates this player's shots against
# victims' positions at that tick.
const CMD_SIZE := 8


static func encode_cmd(p: CharacterBody3D) -> PackedFloat32Array:
	var flags := (
		int(p.cmd_jump)
		| int(p.cmd_dash) << 1
		| int(p.cmd_fire_l) << 2
		| int(p.cmd_fire_r) << 3
		| int(p.cmd_swap) << 4
		| int(p.cmd_respawn) << 5
	)
	var c := PackedFloat32Array()
	c.resize(CMD_SIZE)
	c[0] = float(p.net_tick)
	c[1] = p.cmd_move.x
	c[2] = p.cmd_move.y
	c[3] = 1.0 if p.cmd_down_dash else 0.0
	c[4] = float(flags)
	c[5] = p.rotation.y
	c[6] = p.head.rotation.x
	c[7] = float(p.seen_server_tick)
	return c


## Writes a net cmd onto a body (DRIVEN on the server, or a history entry
## during a reconciliation replay). View angles are applied directly: they
## are client-authoritative and travel with the cmd, never with state.
static func apply_cmd(p: CharacterBody3D, c: PackedFloat32Array) -> void:
	p.cmd_move = Vector2(c[1], c[2])
	p.cmd_down_dash = c[3] != 0.0
	var flags := int(c[4])
	p.cmd_jump = bool(flags & 1)
	p.cmd_dash = bool(flags & 2)
	p.cmd_fire_l = bool(flags & 4)
	p.cmd_fire_r = bool(flags & 8)
	p.cmd_swap = bool(flags & 16)
	p.cmd_respawn = bool(flags & 32)
	p.rotation.y = c[5]
	p.head.rotation.x = c[6]
	p.seen_server_tick = int(c[7])


static func capture(p: CharacterBody3D) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(SIZE)
	var pos: Vector3 = p.global_position
	var sim: MoveSim = p.sim
	s[0] = pos.x
	s[1] = pos.y
	s[2] = pos.z
	s[3] = sim.velocity.x
	s[4] = sim.velocity.y
	s[5] = sim.velocity.z
	s[6] = sim.fuel
	s[7] = float(sim.state)
	s[8] = sim.wall_normal.x
	s[9] = sim.wall_normal.y
	s[10] = sim.wall_normal.z
	s[11] = sim.wall_speed
	s[12] = sim.wallrun_time
	s[13] = sim.last_wall_normal.x
	s[14] = sim.last_wall_normal.y
	s[15] = sim.last_wall_normal.z
	s[16] = sim.wall_rearm_timer
	s[17] = sim.ramp_grace_timer
	s[18] = sim.dash_cooldown_timer
	s[19] = sim.double_jump_timer
	s[20] = sim.wall_coyote_timer
	s[21] = sim.coyote_wall_normal.x
	s[22] = sim.coyote_wall_normal.y
	s[23] = sim.coyote_wall_normal.z
	s[24] = sim.coyote_wall_speed
	s[25] = sim.ground_coyote_timer
	s[26] = sim.jump_buffer_timer
	s[27] = p.countdown
	s[28] = float(p.hp)
	s[29] = p.shot_gap_timer
	s[30] = p.sword_cd[0]
	s[31] = p.sword_cd[1]
	s[32] = p.sword_active
	s[33] = 0.0 if p.sword_side == "L" else 1.0
	s[34] = float(p.loadout_index)
	s[35] = float(p.arm_left.state)
	s[36] = p.arm_left.charge
	s[37] = p.arm_left.cooldown
	s[38] = float(p.arm_right.state)
	s[39] = p.arm_right.charge
	s[40] = p.arm_right.cooldown
	s[41] = float(_encode_pending(p))
	return s


static func restore(p: CharacterBody3D, s: PackedFloat32Array) -> void:
	var sim: MoveSim = p.sim
	p.global_position = Vector3(s[0], s[1], s[2])
	sim.velocity = Vector3(s[3], s[4], s[5])
	p.velocity = sim.velocity  # keep the body mirror in step
	sim.fuel = s[6]
	sim.state = int(s[7]) as MoveSim.MoveState
	sim.wall_normal = Vector3(s[8], s[9], s[10])
	sim.wall_speed = s[11]
	sim.wallrun_time = s[12]
	sim.last_wall_normal = Vector3(s[13], s[14], s[15])
	sim.wall_rearm_timer = s[16]
	sim.ramp_grace_timer = s[17]
	sim.dash_cooldown_timer = s[18]
	sim.double_jump_timer = s[19]
	sim.wall_coyote_timer = s[20]
	sim.coyote_wall_normal = Vector3(s[21], s[22], s[23])
	sim.coyote_wall_speed = s[24]
	sim.ground_coyote_timer = s[25]
	sim.jump_buffer_timer = s[26]
	p.countdown = s[27]
	p.hp = int(s[28])
	p.shot_gap_timer = s[29]
	if int(s[34]) != p.loadout_index:
		p.set_loadout(int(s[34]))
	p.sword_cd = [s[30], s[31]]
	p.sword_active = s[32]
	p.sword_side = "L" if s[33] < 0.5 else "R"
	p.arm_left.state = int(s[35])
	p.arm_left.charge = s[36]
	p.arm_left.cooldown = s[37]
	p.arm_right.state = int(s[38])
	p.arm_right.charge = s[39]
	p.arm_right.cooldown = s[40]
	_restore_pending(p, int(s[41]))
	sim.move_locked = p.arm_left.is_locking() or p.arm_right.is_locking()


## Fields that must match for a client prediction to stand. Position/velocity
## get a small epsilon (cross-machine float drift); discrete fields exact.
static func agree(a: PackedFloat32Array, b: PackedFloat32Array) -> bool:
	if a.size() != SIZE or b.size() != SIZE:
		return false
	var pos_ok := Vector3(a[0], a[1], a[2]).distance_to(Vector3(b[0], b[1], b[2])) <= 0.02
	var vel_ok := Vector3(a[3], a[4], a[5]).distance_to(Vector3(b[3], b[4], b[5])) <= 0.1
	var fuel_ok := absf(a[6] - b[6]) <= 0.5
	var countdown_ok := absf(a[27] - b[27]) <= 0.1
	var discrete_ok := true
	for i: int in [7, 28, 34, 35, 38, 41]:  # move state, hp, loadout, arm states, pending
		if int(a[i]) != int(b[i]):
			discrete_ok = false
	return pos_ok and vel_ok and fuel_ok and countdown_ok and discrete_ok


static func _encode_pending(p: CharacterBody3D) -> int:
	var sides: Array = []
	for arm: Node in p.pending_arms:
		sides.append("L" if arm == p.arm_left else "R")
	return maxi(0, PENDING_CODES.find(sides))


static func _restore_pending(p: CharacterBody3D, code: int) -> void:
	p.pending_arms.clear()
	for side: String in PENDING_CODES[clampi(code, 0, PENDING_CODES.size() - 1)]:
		p.pending_arms.append(p.arm_left if side == "L" else p.arm_right)
