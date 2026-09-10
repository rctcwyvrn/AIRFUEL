class_name BotController
extends Node

## Practice-opponent driver (DESIGN.md Appendix A: a bot as an always-
## available PRACTICE tool — never the Step 3 validity test). Pilots a real
## AirfuelPlayer (its parent, spawned with bot_controlled = true) through the
## actual movement/combat physics by writing its cmd_* inputs each tick,
## exactly like the TAS ghost: fuel, cooldowns, and gravity are all real.
##
## Two layers (the §19.3 intent-level shape): a slow brain (~brain_hz) picks
## an intent and rolls dice; the per-tick actuator steers, aims, and dodges.
## The player's aim crush stays cut (Appendix A) — but the bot's own tracking
## degrades as its charge builds (turn_rate_free → turn_rate_charged), a
## bot-only handicap that keeps charge → tell → dodge winnable against it.
## Fairness: the bot only reads what a human perceives — opponent position
## (through walls only as "last seen"), charge progress (globally warned,
## §15.2), and its own state. Never the opponent's cmds or fuel.

enum Intent { ENGAGE, REFUEL }
enum DodgeResponse { DASH, STRAFE, NONE }

## Menu → PracticeSpawner handoff: loadout index for the next practice duel.
## -1 = no practice duel pending (the spawner then does nothing).
static var pending_loadout := -1

@export var bot: BotConfig

var body: AirfuelPlayer
var opponent: AirfuelPlayer

var intent := Intent.ENGAGE
var clock := 0.0
var think_timer := 0.0
var want_stagger := false
var want_jump := false

# Aiming: ring buffer of opponent positions — the bot tracks a slightly
# stale target (aim_lag), plus slow-wandering noise re-rolled per think.
var aim_samples: Array[Vector3] = []
var noise_yaw := 0.0
var noise_pitch := 0.0

var strafe_dir := 1.0
var strafe_timer := 0.0

# One dodge event per enemy arm, created when that arm's charge starts:
# {react_at, dash_at, response, reacted, dashed}. Empty dict = no event.
var dodge_events: Array[Dictionary] = [{}, {}]
var prev_charge: Array[float] = [0.0, 0.0]

var refuel_wall_point := Vector3.ZERO
var refuel_wall_normal := Vector3.ZERO
var refuel_target := Vector3.ZERO
var has_refuel_target := false


func _ready() -> void:
	process_physics_priority = -1  # write cmds BEFORE the body's physics tick
	body = get_parent() as AirfuelPlayer
	body.respawned.connect(_on_respawned)


func _physics_process(delta: float) -> void:
	if body == null:
		return
	_clear_cmds()
	if body.countdown > 0.0:
		return
	clock += delta
	if opponent == null or not is_instance_valid(opponent):
		_find_opponent()
		if opponent == null:
			return
	_sample_opponent()
	_detect_charges()
	think_timer -= delta
	if think_timer <= 0.0:
		think_timer = 1.0 / bot.brain_hz
		_think()
	var dist := body.global_position.distance_to(opponent.global_position)
	if intent == Intent.REFUEL:
		_refuel_move(delta)
		_run_dodges()
		return
	_aim_at_opponent(delta)
	_engage_move(dist, delta)
	_run_dodges()
	_combat(dist)


## Slow layer: intent switching and the per-think dice (stagger, hop, noise).
func _think() -> void:
	want_stagger = randf() < bot.stagger_chance
	if randf() < bot.jump_chance:
		want_jump = true
	noise_yaw = deg_to_rad(randfn(0.0, bot.aim_noise_deg))
	noise_pitch = deg_to_rad(randfn(0.0, bot.aim_noise_deg))
	if intent == Intent.ENGAGE and body.fuel < bot.refuel_enter:
		intent = Intent.REFUEL
		has_refuel_target = false
	elif intent == Intent.REFUEL and body.fuel >= bot.refuel_exit:
		intent = Intent.ENGAGE
	if intent == Intent.REFUEL and body.state != AirfuelPlayer.MoveState.WALLRUN:
		_pick_refuel_wall()


func _clear_cmds() -> void:
	body.cmd_move = Vector2.ZERO
	body.cmd_down_dash = false
	body.cmd_jump = false
	body.cmd_dash = false
	body.cmd_fire_l = false
	body.cmd_fire_r = false
	body.cmd_swap = false
	body.cmd_respawn = false


func _find_opponent() -> void:
	opponent = null
	for p: Node in get_tree().get_nodes_in_group("player"):
		var ap := p as AirfuelPlayer
		if ap != null and ap != body and not ap.ghost_controlled and not ap.bot_controlled:
			opponent = ap
			return


func _on_respawned() -> void:
	dodge_events = [{}, {}]
	prev_charge = [0.0, 0.0]
	aim_samples.clear()
	intent = Intent.ENGAGE
	has_refuel_target = false
	want_jump = false
	strafe_timer = 0.0


func _sample_opponent() -> void:
	var lag_ticks := maxi(1, int(bot.aim_lag * Engine.physics_ticks_per_second))
	aim_samples.append(opponent.camera.global_position)
	while aim_samples.size() > lag_ticks:
		aim_samples.pop_front()


## New enemy rail charge → a dodge event (react → roll → execute). Each arm
## is an INDEPENDENT event (Lily's call): the bot often spends its dash on
## the first shot of a staggered dual-rail and eats the second — the feint
## layer works against it organically. Reacting needs no line of sight:
## every charge is loudly warned (§15.2 warn-on-every-charge).
func _detect_charges() -> void:
	for i in 2:
		var prog := 0.0
		if opponent.arm_types[i] == "rail":
			prog = opponent.display_arm_progress(i)
		if prog > 0.0 and prev_charge[i] <= 0.0:
			_start_dodge(i, prog)
		elif prog <= 0.0 and prev_charge[i] > 0.0:
			dodge_events[i] = {}
		prev_charge[i] = prog


func _start_dodge(index: int, prog: float) -> void:
	var remaining := (1.0 - prog) * opponent.combat.charge_time
	var react := clampf(
		randfn(bot.reaction_mean, bot.reaction_dev), bot.reaction_min, bot.reaction_max
	)
	var total := bot.dodge_weight_dash + bot.dodge_weight_strafe + bot.dodge_weight_none
	var roll := randf() * total
	var response := DodgeResponse.NONE
	if roll < bot.dodge_weight_dash:
		response = DodgeResponse.DASH
	elif roll < bot.dodge_weight_dash + bot.dodge_weight_strafe:
		response = DodgeResponse.STRAFE
	# The dash lands in the shot's terminal window: dodging earlier just
	# lets the shooter re-track (aim stays free while charging, §7.2).
	var lead := bot.dodge_lead + randf_range(-bot.dodge_lead_jitter, bot.dodge_lead_jitter)
	dodge_events[index] = {
		react_at = clock + react,
		dash_at = clock + maxf(react, remaining - lead),
		response = response,
		reacted = false,
		dashed = false,
	}


func _run_dodges() -> void:
	for i in 2:
		var e := dodge_events[i]
		if e.is_empty():
			continue
		if not e.reacted and clock >= e.react_at:
			e.reacted = true
			if e.response != DodgeResponse.NONE:
				strafe_dir = -strafe_dir  # the juke half of any response
				strafe_timer = randf_range(bot.strafe_hold_min, bot.strafe_hold_max)
		if e.response == DodgeResponse.DASH and e.reacted and not e.dashed and clock >= e.dash_at:
			e.dashed = true
			_try_dash()


func _try_dash() -> void:
	# Mechanical scarcity degrades a rolled dash to the strafe juke — distinct
	# from the deliberate no-dodge roll, and the second reason staggered
	# dual-rail lands (the first dodge's cooldown is often still running).
	if body.move_locked or body.dash_cooldown_timer > 0.0 or body.fuel < body.config.air_dash_cost:
		return
	var side := strafe_dir
	if _dash_blocked(side):
		side = -side
		if _dash_blocked(side):
			return
	body.cmd_move = Vector2(side, 0.0)
	body.cmd_dash = true


func _dash_blocked(side: float) -> bool:
	var dir := body.global_transform.basis.x * side
	var space := body.get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(
		body.global_position,
		body.global_position + dir * bot.dodge_probe_range,
		1,
		[body.get_rid()]
	)
	return not space.intersect_ray(params).is_empty()


func _dodge_dash_pending() -> bool:
	for e: Dictionary in dodge_events:
		if not e.is_empty() and e.response == DodgeResponse.DASH and not e.dashed:
			return true
	return false


## Rate-limited tracking toward a lagged target sample. The rate degrades
## with the bot's own charge — the bot-only aim crush — so a terminal-window
## dash outruns its tracking exactly when a shot is about to land.
func _aim_at_opponent(delta: float) -> void:
	if aim_samples.is_empty():
		return
	var to := aim_samples[0] - body.camera.global_position
	var flat := Vector2(to.x, to.z).length()
	# Noise scales with the target's speed: a stationary target dies, a
	# dashing one survives — the dodge incentive, from the bot's side.
	var noise_scale := clampf(
		opponent.horizontal_speed() / opponent.config.base_run_speed, 0.0, 1.0
	)
	var desired_yaw := atan2(-to.x, -to.z) + noise_yaw * noise_scale
	var desired_pitch := clampf(
		atan2(to.y, flat) + noise_pitch * noise_scale, -PI / 2 + 0.1, PI / 2 - 0.1
	)
	var rate := lerpf(bot.turn_rate_free, bot.turn_rate_charged, _own_charge())
	var step := rate * delta
	body.rotation.y += clampf(angle_difference(body.rotation.y, desired_yaw), -step, step)
	body.head.rotation.x += clampf(desired_pitch - body.head.rotation.x, -step, step)


func _own_charge() -> float:
	var c := 0.0
	if body.arm_types[0] == "rail":
		c = maxf(c, body.arm_left.progress())
	if body.arm_types[1] == "rail":
		c = maxf(c, body.arm_right.progress())
	return c


func _aim_error() -> float:
	if aim_samples.is_empty():
		return PI
	var fwd := -body.camera.global_transform.basis.z
	return fwd.angle_to((aim_samples[0] - body.camera.global_position).normalized())


func _has_los() -> bool:
	var space := body.get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(
		body.camera.global_position,
		opponent.camera.global_position,
		1,
		[body.get_rid(), opponent.get_rid()]
	)
	return space.intersect_ray(params).is_empty()


## Orbit inside the kit's preferred range band: held strafes (flipped on a
## timer or by a dodge juke, never per-tick jitter), advance/retreat on the
## band edges, occasional hops. Dual sword wants a much closer band — its
## gap-closer lunge does the traveling.
func _engage_move(dist: float, delta: float) -> void:
	var rmin := bot.preferred_range_min
	var rmax := bot.preferred_range_max
	if _dual_sword():
		rmin = bot.dual_sword_range_min
		rmax = bot.dual_sword_range_max
	strafe_timer -= delta
	if strafe_timer <= 0.0:
		strafe_timer = randf_range(bot.strafe_hold_min, bot.strafe_hold_max)
		strafe_dir = 1.0 if randf() < 0.5 else -1.0
	var fwd := 0.0
	if dist > rmax:
		fwd = -1.0
	elif dist < rmin:
		fwd = 1.0
	body.cmd_move = Vector2(strafe_dir, fwd)
	if want_jump and body.is_on_floor():
		want_jump = false
		body.cmd_jump = true


func _dual_sword() -> bool:
	return body.arm_types[0] == "sword" and body.arm_types[1] == "sword"


## Arm decisions. A tick that dashes never also commits an arm, and no rail
## charge starts while a dodge dash is still owed — charging would freeze
## the bot straight through its own dodge window.
func _combat(dist: float) -> void:
	if body.cmd_dash or not _has_los():
		return
	var err := _aim_error()
	var aimed := err < deg_to_rad(bot.fire_cone_deg)
	var sword_aimed := err < deg_to_rad(bot.sword_aim_cone_deg)
	for i in 2:
		if body.arm_types[i] == "rail":
			_try_rail(i, aimed)
		else:
			_try_sword(i, dist, sword_aimed, _dual_sword() and i == 0)


func _try_rail(index: int, aimed: bool) -> void:
	if not aimed or _dodge_dash_pending():
		return
	var arm := body.arm_left if index == 0 else body.arm_right
	if arm.state != RailArm.ArmState.IDLE:
		return
	var other := body.arm_right if index == 0 else body.arm_left
	var other_locking: bool = body.arm_types[1 - index] == "rail" and other.is_locking()
	if other_locking and not want_stagger:
		return  # staggered second charge only on the brain's dice
	_press_fire(index)


## Conservative sword (Lily's gates): the kill lunge needs the hard range
## gate AND a punish window — the opponent charge-frozen, or already inside
## committed reach. Dual sword's arm 0 may additionally lunge as a pure
## gap-closer beyond its band (that loadout's design identity, §8.3); a
## rail+sword bot never lunges as traversal.
func _try_sword(index: int, dist: float, aimed: bool, gap_arm: bool) -> void:
	if not aimed or body.move_locked or body.state == AirfuelPlayer.MoveState.WALLRUN:
		return
	if body.sword_cd[index] > 0.0:
		return
	if body.fuel < body.combat.sword_lunge_cost + bot.sword_fuel_reserve:
		return
	var committed := dist <= body.combat.sword_hit_range * bot.sword_commit_factor
	if dist <= bot.sword_max_range and (opponent.move_locked or committed):
		_press_fire(index)
		return
	if gap_arm and dist > bot.dual_sword_range_max:
		_press_fire(index)


func _press_fire(index: int) -> void:
	if index == 0:
		body.cmd_fire_l = true
	else:
		body.cmd_fire_r = true


## Fuel maintenance: dismount is the only in-play refill (§5.1), so a dry
## bot runs a wall on purpose — angle in, jump to attach, ride briefly,
## jump off for the speed-scaled grant. This is the gap the TAS ghost
## deliberately left open ("Step 3 bot territory", ghost.gd.md).
func _pick_refuel_wall() -> void:
	has_refuel_target = false
	var space := body.get_world_3d().direct_space_state
	var best := {}
	var best_d := INF
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var params := PhysicsRayQueryParameters3D.create(
			body.global_position,
			body.global_position + dir * bot.refuel_probe_range,
			1,
			[body.get_rid()]
		)
		var hit := space.intersect_ray(params)
		if hit.is_empty() or absf(hit.normal.y) > 0.4:
			continue
		var d: float = body.global_position.distance_to(hit.position)
		if d < best_d:
			best_d = d
			best = hit
	if best.is_empty():
		intent = Intent.ENGAGE  # nothing to run on here
		return
	refuel_wall_point = best.position
	refuel_wall_normal = best.normal
	var tangent: Vector3 = refuel_wall_normal.cross(Vector3.UP)
	if tangent.dot(-body.global_transform.basis.z) < 0.0:
		tangent = -tangent  # run the wall the way we're already facing
	refuel_target = refuel_wall_point + tangent * bot.refuel_approach_lead
	has_refuel_target = true


func _refuel_move(delta: float) -> void:
	if body.state == AirfuelPlayer.MoveState.WALLRUN:
		body.cmd_move = Vector2(0.0, -1.0)
		if body.wallrun_time >= bot.refuel_ride_time:
			body.cmd_jump = true  # jump dismount: fuel grant + speed boost
		return
	if not has_refuel_target:
		return
	var to := refuel_target - body.global_position
	var step := bot.turn_rate_free * delta
	body.rotation.y += clampf(angle_difference(body.rotation.y, atan2(-to.x, -to.z)), -step, step)
	body.head.rotation.x += clampf(-body.head.rotation.x, -step, step)  # level out
	body.cmd_move = Vector2(0.0, -1.0)
	var wall_dist := absf((body.global_position - refuel_wall_point).dot(refuel_wall_normal))
	if (
		body.is_on_floor()
		and wall_dist < bot.refuel_jump_dist
		and body.horizontal_speed() > body.config.min_wallrun_speed
	):
		body.cmd_jump = true  # attach needs to be airborne
