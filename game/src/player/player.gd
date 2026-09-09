class_name AirfuelPlayer
extends CharacterBody3D

## Roadmap Steps 1 + 2: movement, plus dual railgun arms vs stationary targets.
## Wallrun (flat + curved via radial ray probes), dismount fuel/speed grants,
## ramp persistence across gaps, dashes, fueled strafes, terminal velocity;
## per-arm rail charge with freeze/trajectory-lock, hitscan, canister
## ejection. Plus prototype LAN netplay (client-authoritative, see Net).

enum MoveState { GROUNDED, AIRBORNE, WALLRUN }

signal shot_fired(side: String, result: String)
signal damaged(amount: int, from_id: int)
signal died
signal respawned

const CANISTER := preload("res://src/weapons/canister.tscn")

@export var ghost_controlled := false
@export var config: MovementConfig
@export var combat: CombatConfig
@export var mouse_sensitivity := 0.0022

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var arm_left: RailArm = $ArmLeft
@onready var arm_right: RailArm = $ArmRight
@onready var vm_left: MeshInstance3D = $Head/Camera3D/ViewmodelL
@onready var vm_right: MeshInstance3D = $Head/Camera3D/ViewmodelR
@onready var puppet_arm_l: MeshInstance3D = $PuppetArmL
@onready var puppet_arm_r: MeshInstance3D = $PuppetArmR


var state := MoveState.AIRBORNE
var fuel := 0.0

var wall_normal := Vector3.ZERO
var wall_speed := 0.0
var wallrun_time := 0.0
var last_wall_normal := Vector3.ZERO
var wall_rearm_timer := 0.0

var ramp_grace_timer := 0.0
var dash_cooldown_timer := 0.0
var double_jump_timer := 0.0
var wall_coyote_timer := 0.0
var coyote_wall_normal := Vector3.ZERO
var coyote_wall_speed := 0.0
var ground_coyote_timer := 0.0
var jump_buffer_timer := 0.0

var base_fov := 100.0
var spawn_transform: Transform3D

var move_locked := false
var pending_arms: Array[RailArm] = []
var last_shot_time := -1000.0

var hp := 2
var _net_target_pos := Vector3.ZERO

# Per-tick command state: filled from Input for humans, written directly by
# a controller (TAS ghost, future bots) when ghost_controlled.
var cmd_move := Vector2.ZERO
var cmd_vert := 0.0
var cmd_jump := false
var cmd_dash := false
var cmd_fire_l := false
var cmd_fire_r := false
var cmd_swap := false
var cmd_respawn := false

var recording := false
var _tape_lines: PackedStringArray = []

var run_time := 0.0
var run_finished := false
var countdown := 0.0

const LOADOUTS: Array = [["rail", "rail"], ["rail", "sword"], ["sword", "sword"]]
const RAIL_VM_COLOR := Color(0.45, 0.47, 0.5)
const SWORD_VM_COLOR := Color(0.82, 0.84, 0.88)
var loadout_index := 0
var arm_types: Array = ["rail", "rail"]
var sword_cd: Array = [0.0, 0.0]
var sword_active := 0.0
var sword_side := "L"
var _net_prog := Vector2.ZERO
var _rail_vm_mesh: BoxMesh
var _sword_vm_mesh: BoxMesh
var _trail_node: MeshInstance3D
var _trail_mesh: ImmediateMesh
var _trail_pts: Array[Vector3] = []
var _trail_times: Array[float] = []


func _ready() -> void:
	fuel = config.fuel_max
	hp = combat.hp_max
	spawn_transform = global_transform
	_net_target_pos = global_position
	arm_left.charge_complete.connect(func() -> void: pending_arms.append(arm_left))
	arm_right.charge_complete.connect(func() -> void: pending_arms.append(arm_right))
	vm_left.set_meta("rest_pos", vm_left.position)
	vm_right.set_meta("rest_pos", vm_right.position)
	vm_left.set_meta("rest_rot", vm_left.rotation)
	vm_right.set_meta("rest_rot", vm_right.rotation)
	_rail_vm_mesh = BoxMesh.new()
	_rail_vm_mesh.size = Vector3(0.12, 0.12, 0.5)
	_sword_vm_mesh = BoxMesh.new()
	_sword_vm_mesh.size = Vector3(0.05, 0.2, 1.05)
	_apply_loadout_visuals()
	_trail_mesh = ImmediateMesh.new()
	_trail_node = MeshInstance3D.new()
	_trail_node.mesh = _trail_mesh
	_trail_node.top_level = true
	var tmat := StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tmat.vertex_color_use_as_albedo = true
	_trail_node.material_override = tmat
	add_child(_trail_node)
	base_fov = camera.fov
	if ghost_controlled:
		# TAS/bot body: real physics, no human input, translucent orange.
		# Layer 0: nothing collides INTO the ghost; mask 1 = world ONLY.
		# The mask must exclude the player layer (4): a replay that can bump
		# a nearby player desyncs nondeterministically (shipped once as
		# "sometimes the ghost gets stuck").
		collision_layer = 0
		collision_mask = 1
		camera.current = false
		set_process_unhandled_input(false)
		vm_left.visible = false
		vm_right.visible = false
		var bm := $BodyMesh as MeshInstance3D
		bm.visible = true
		var gmat := (bm.material_override as StandardMaterial3D).duplicate()
		gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gmat.albedo_color = Color(1.0, 0.55, 0.1, 0.4)
		gmat.emission = Color(1.0, 0.55, 0.1, 1.0)
		bm.material_override = gmat
	elif is_multiplayer_authority():
		# Explicit claim: auto-current fails when a remote puppet's camera
		# entered the viewport first (client-side join order)
		camera.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		# Remote puppet: rendered + state-synced, never simulated here
		camera.current = false
		set_physics_process(false)
		vm_left.visible = false
		vm_right.visible = false
		$BodyMesh.visible = true
		# Shoulder weapon blocks: the remote player's loadout + charge tell.
		# Materials duplicated so multiple puppets tint independently.
		for arm: MeshInstance3D in [puppet_arm_l, puppet_arm_r]:
			arm.material_override = arm.material_override.duplicate()
			arm.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x, -PI / 2 + 0.05, PI / 2 - 0.05)
	elif event.is_action_pressed("ui_cancel"):
		var captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED)


func _physics_process(delta: float) -> void:
	_gather_input()
	if countdown > 0.0:
		# 3-2-1 after any reset: frozen in place (look around freely); the
		# run clock, tape recording, and ghost playback all wait for GO
		countdown -= delta
		velocity = Vector3.ZERO
		if Net.active:
			_send_my_state()
		return
	if not run_finished:
		run_time += delta
	dash_cooldown_timer = maxf(0.0, dash_cooldown_timer - delta)
	double_jump_timer = maxf(0.0, double_jump_timer - delta)
	wall_rearm_timer = maxf(0.0, wall_rearm_timer - delta)
	wall_coyote_timer = maxf(0.0, wall_coyote_timer - delta)
	ground_coyote_timer = maxf(0.0, ground_coyote_timer - delta)
	jump_buffer_timer = maxf(0.0, jump_buffer_timer - delta)
	sword_cd[0] = maxf(0.0, sword_cd[0] - delta)
	sword_cd[1] = maxf(0.0, sword_cd[1] - delta)
	if sword_active > 0.0:
		sword_active -= delta
		_sword_hit_check()
	if cmd_jump:
		jump_buffer_timer = config.jump_buffer_time

	move_locked = arm_left.is_locking() or arm_right.is_locking()
	_handle_arms()

	var wish := Vector3.ZERO if move_locked else _wish_dir()

	match state:
		MoveState.GROUNDED:
			_ground_move(wish, delta)
		MoveState.AIRBORNE:
			_air_move(wish, delta)
		MoveState.WALLRUN:
			_wallrun_move(delta)

	_handle_dashes()

	var speed := velocity.length()
	if speed > config.terminal_velocity:
		# Soft ceiling: overspeed (sword lunge) decays fast instead of clamping
		velocity *= move_toward(speed, config.terminal_velocity,
				config.overspeed_decay * delta) / speed
	if move_locked:
		# Charging bleeds you down to a slower, more readable trajectory
		velocity = velocity.limit_length(combat.charge_speed_cap)
	velocity.y = maxf(velocity.y, -config.terminal_fall_speed)

	var pre_slide_velocity := velocity
	move_and_slide()
	if state != MoveState.WALLRUN:
		_apply_glide(pre_slide_velocity)
	_update_state()
	_camera_feel(delta)
	_update_viewmodels(delta)

	var manual_respawn := cmd_respawn and not Net.active
	if manual_respawn or global_position.y < config.kill_y:
		_respawn()

	if recording:
		var flags := (int(cmd_jump) | int(cmd_dash) << 1 | int(cmd_fire_l) << 2
				| int(cmd_fire_r) << 3 | int(cmd_swap) << 4 | int(cmd_respawn) << 5)
		_tape_lines.append("%.5f %.5f %.3f %.3f %.1f %d" % [
				rotation.y, head.rotation.x, cmd_move.x, cmd_move.y, cmd_vert, flags])

	if Net.active:
		_send_my_state()


## LAN broadcasts to every peer; a lobby match targets only the opponent, so
## concurrent 1v1s never see each other's traffic.
func _send_my_state() -> void:
	if Net.match_opponent != 0:
		_send_state.rpc_id(Net.match_opponent, global_position, velocity,
				rotation.y, head.rotation.x,
				arm_progress_left(), arm_progress_right(), loadout_index)
	else:
		_send_state.rpc(global_position, velocity, rotation.y, head.rotation.x,
				arm_progress_left(), arm_progress_right(), loadout_index)


func _process(delta: float) -> void:
	_update_trail_line()
	if is_multiplayer_authority():
		return
	global_position = global_position.lerp(_net_target_pos, 1.0 - exp(-20.0 * delta))
	# Rail arms glow with charge (the audible-tell stand-in); swords idle warm
	for i in 2:
		var mat := (puppet_arm_l if i == 0 else puppet_arm_r).material_override as StandardMaterial3D
		mat.emission_energy_multiplier = (_net_prog[i] * 3.0) if arm_types[i] == "rail" else 0.4


func _ground_move(wish: Vector3, delta: float) -> void:
	if move_locked:
		# Charging on the ground roots you (DESIGN.md 7.2)
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= config.gravity * delta
		return
	var h := Vector3(velocity.x, 0.0, velocity.z)
	if wish == Vector3.ZERO:
		h = h.move_toward(Vector3.ZERO, config.ground_friction * delta)
	else:
		# Excess speed above base run bleeds off on the ground; the air (ramp
		# grace) and walls are where speed lives.
		var speed := maxf(config.base_run_speed,
				move_toward(h.length(), config.base_run_speed, config.ground_friction * delta))
		h = h.move_toward(wish * speed, config.ground_accel * delta)
	velocity.x = h.x
	velocity.z = h.z
	velocity.y -= config.gravity * delta

	if jump_buffer_timer > 0.0:
		jump_buffer_timer = 0.0
		velocity.y = config.jump_velocity


func _air_move(wish: Vector3, delta: float) -> void:
	velocity.y -= config.gravity * delta

	if wish != Vector3.ZERO:
		_air_accelerate(wish, config.air_control_accel, config.base_run_speed, delta)
		if velocity.dot(wish) < config.air_strafe_speed_cap \
				and _spend(config.air_strafe_cost_per_sec * delta):
			_air_accelerate(wish, config.air_strafe_accel, config.air_strafe_speed_cap, delta)

	# Q vertical strafe: fueled downward thrust only
	var vert := 0.0 if move_locked else cmd_vert
	if vert != 0.0:
		var vdir := Vector3.UP * vert
		if velocity.dot(vdir) < config.air_strafe_vertical_cap \
				and _spend(config.air_strafe_cost_per_sec * delta):
			_air_accelerate(vdir, config.air_strafe_accel, config.air_strafe_vertical_cap, delta)

	if ramp_grace_timer > 0.0:
		ramp_grace_timer -= delta
	else:
		_decay_excess_speed(config.ramp_decay_rate, delta)

	if not move_locked and cmd_jump:
		jump_buffer_timer = 0.0
		if wall_coyote_timer > 0.0:
			_coyote_walljump()
		elif ground_coyote_timer > 0.0:
			ground_coyote_timer = 0.0
			velocity.y = config.jump_velocity
		elif double_jump_timer == 0.0 and _spend(config.double_jump_cost):
			velocity.y = maxf(velocity.y, config.double_jump_strength)
			double_jump_timer = config.double_jump_cooldown


func _wallrun_move(delta: float) -> void:
	if is_on_floor():
		_dismount(false)
		return

	# Re-probe every tick so the normal tracks curved surfaces (cylinders).
	var hit := _probe_wall_at(-wall_normal, 1.6)
	if hit.is_empty():
		for s: float in [1.0, -1.0]:
			hit = _probe_wall_at((-wall_normal).rotated(Vector3.UP, s * 0.6), 1.6)
			if not hit.is_empty():
				break
	if hit.is_empty():
		_dismount(false)
		return
	wall_normal = hit.normal

	wallrun_time += delta
	if wallrun_time > config.wallrun_max_duration:
		_dismount(false)
		return

	var flat := Vector3(velocity.x, 0.0, velocity.z).slide(wall_normal)
	wall_speed = flat.length()
	if wall_speed < config.min_wallrun_speed:
		_dismount(false)
		return

	wall_speed = move_toward(wall_speed, config.wallrun_max_speed, config.wallrun_accel * delta)
	var dir := flat.normalized()
	velocity.x = dir.x * wall_speed - wall_normal.x * config.wall_stick_speed
	velocity.z = dir.z * wall_speed - wall_normal.z * config.wall_stick_speed
	velocity.y = move_toward(velocity.y, 0.0, 20.0 * delta) - config.wallrun_gravity * delta

	if not move_locked and cmd_jump:
		jump_buffer_timer = 0.0
		_dismount(true)


## Reward on dismount, scaled to along-wall speed (slow wall-hugging gives
## near-nothing). A jump dismount also gets the speed boost; falling off or
## timing out grants fuel only.
func _dismount(jumped: bool) -> void:
	var grant := clampf((wall_speed - config.min_wallrun_speed) * config.dismount_fuel_per_speed,
			0.0, config.dismount_fuel_max)
	fuel = minf(config.fuel_max, fuel + grant)

	if jumped:
		var flat := Vector3(velocity.x, 0.0, velocity.z)
		var dir := flat.normalized() if flat.length() > 0.1 else -global_transform.basis.z
		var boosted := minf(wall_speed * (1.0 + config.dismount_boost_factor),
				config.terminal_velocity)
		velocity.x = dir.x * boosted + wall_normal.x * config.dismount_push_off
		velocity.z = dir.z * boosted + wall_normal.z * config.dismount_push_off
		velocity.y = maxf(velocity.y, config.dismount_up_velocity)

	if not jumped:
		# Wall coyote (Celeste-style): the dismount jump stays available briefly
		wall_coyote_timer = config.wall_coyote_time
		coyote_wall_normal = wall_normal
		coyote_wall_speed = wall_speed
	else:
		wall_coyote_timer = 0.0

	ramp_grace_timer = config.ramp_grace_window
	last_wall_normal = wall_normal
	wall_rearm_timer = config.wall_rearm_time
	wallrun_time = 0.0
	wall_speed = 0.0
	state = MoveState.AIRBORNE


func _try_attach_wall() -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() < config.min_wallrun_speed:
		return

	var best := {}
	var best_dist := INF
	for i in 12:
		var ang := TAU * float(i) / 12.0
		var hit := _probe_wall_at(Vector3(cos(ang), 0.0, sin(ang)))
		if hit.is_empty():
			continue
		if wall_rearm_timer > 0.0 \
				and (hit.normal as Vector3).angle_to(last_wall_normal) < deg_to_rad(25.0):
			continue
		if velocity.dot(hit.normal) > 2.0:
			continue
		var d: float = global_position.distance_to(hit.position)
		if d < best_dist:
			best_dist = d
			best = hit

	if best.is_empty():
		return
	wall_normal = best.normal
	wallrun_time = 0.0
	wall_speed = flat.slide(wall_normal).length()
	wall_coyote_timer = 0.0
	state = MoveState.WALLRUN


func _probe_wall_at(dir: Vector3, dist_scale := 1.0) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(
			global_position,
			global_position + dir.normalized() * config.wall_probe_distance * dist_scale,
			collision_mask, [get_rid()])
	var hit := space.intersect_ray(params)
	if hit.is_empty() or absf(hit.normal.y) > 0.4:
		return {}
	return hit


func _handle_dashes() -> void:
	if move_locked:
		return
	if not cmd_dash:
		return
	var input := cmd_move
	var vert := cmd_vert
	if input == Vector2.ZERO and vert == 0.0:
		return  # bare Shift is inert: dash requires a held direction
	var on_wall := state == MoveState.WALLRUN
	if input == Vector2.ZERO and vert < 0.0:
		# Shift+Q alone is the down dash (DESIGN.md 4.4): own tuning, no
		# cooldown. On a wall you STAY attached and slide down it fast.
		if (on_wall or state == MoveState.AIRBORNE) and _spend(config.down_dash_cost):
			velocity.y = minf(velocity.y, -config.down_dash_speed)
		return
	if dash_cooldown_timer > 0.0 or not _spend(config.air_dash_cost):
		return
	if on_wall:
		# Dashing off the wall is a real dismount: same fuel grant and speed
		# boost as jumping off, with the dash impulse stacked on top — but
		# the wall you left is locked out for longer (anti-pogo: dashing
		# straight back in compounded boosts to absurd speeds)
		_dismount(true)
		wall_rearm_timer = config.dash_wall_rearm_time
	# Camera-aimed: W+Shift dashes wherever you're looking (pitch included);
	# E/Q contribute world-vertical on top.
	var cb := camera.global_transform.basis
	var dir := (cb.x * input.x + -cb.z * -input.y + Vector3.UP * vert).normalized()
	velocity += dir * config.air_dash_impulse
	dash_cooldown_timer = config.air_dash_cooldown


func _handle_arms() -> void:
	if cmd_swap:
		_cycle_loadout()
	if cmd_fire_l:
		_trigger_arm(0)
	if cmd_fire_r:
		_trigger_arm(1)
	if pending_arms.is_empty():
		return
	# 7.1: completed charges fire in press order, never closer than min_shot_gap
	var now := Time.get_ticks_msec() / 1000.0
	if now - last_shot_time >= combat.min_shot_gap:
		_fire_rail(pending_arms.pop_front())
		last_shot_time = now


func _trigger_arm(index: int) -> void:
	if arm_types[index] == "rail":
		(arm_left if index == 0 else arm_right).try_charge()
		return
	# Sword lunge (DESIGN.md 8.2): movement ability that is also the kill.
	# Cheaper per meter and longer than a dash, per-arm cooldown, no freeze.
	if move_locked or state == MoveState.WALLRUN:
		return
	if sword_cd[index] > 0.0 or not _spend(combat.sword_lunge_cost):
		return
	sword_cd[index] = combat.sword_lunge_cooldown
	sword_active = combat.sword_active_time
	sword_side = "L" if index == 0 else "R"
	velocity = -camera.global_transform.basis.z * combat.sword_lunge_speed
	ramp_grace_timer = config.ramp_grace_window
	var vm := vm_left if index == 0 else vm_right
	vm.position += Vector3(0.0, -0.06, -0.5)
	vm.rotation.x += 0.4


## While the blade is live, anything in reach dies (one hit per lunge).
func _sword_hit_check() -> void:
	var candidates: Array[Node] = []
	candidates.append_array(get_tree().get_nodes_in_group("player"))
	candidates.append_array(get_tree().get_nodes_in_group("target"))
	for node: Node in candidates:
		if node == self or (node is AirfuelPlayer and node.ghost_controlled):
			continue
		var pos := (node as Node3D).global_position
		if node is TargetDummy:
			pos += Vector3.UP * 2.55
		if global_position.distance_to(pos) > combat.sword_hit_range:
			continue
		sword_active = 0.0
		if node is TargetDummy:
			node.take_hit(99)
			shot_fired.emit(sword_side, "kill")
		elif node is AirfuelPlayer:
			node.take_damage.rpc_id(node.get_multiplayer_authority(), 99,
					multiplayer.get_unique_id())
		return


func _cycle_loadout() -> void:
	set_loadout((loadout_index + 1) % LOADOUTS.size())


func set_loadout(index: int) -> void:
	loadout_index = index
	arm_types = LOADOUTS[loadout_index]
	arm_left.reset()
	arm_right.reset()
	pending_arms.clear()
	sword_cd = [0.0, 0.0]
	sword_active = 0.0
	_apply_loadout_visuals()


## First-person weapon identity: rail = chunky block held level, sword = a
## long thin blade rolled inward and tilted up. Pose is stored as meta so
## the recovery lerp returns to the weapon's stance, not to zero.
func _apply_loadout_visuals() -> void:
	for i in 2:
		var vm := vm_left if i == 0 else vm_right
		var mat := vm.material_override as StandardMaterial3D
		var is_sword: bool = arm_types[i] == "sword"
		mat.albedo_color = SWORD_VM_COLOR if is_sword else RAIL_VM_COLOR
		vm.mesh = _sword_vm_mesh if is_sword else _rail_vm_mesh
		var rest: Vector3 = vm.get_meta("rest_rot")
		var pose := rest
		if is_sword:
			pose = rest + Vector3(0.12, 0.0, 0.35 if i == 0 else -0.35)
		vm.rotation = pose
		vm.set_meta("pose_rot", pose)


func loadout_name() -> String:
	return "L %s | R %s" % [arm_types[0].to_upper(), arm_types[1].to_upper()]


func _fire_rail(arm: RailArm) -> void:
	var side := "L" if arm == arm_left else "R"
	var cam := camera.global_transform
	var from := cam.origin
	var to := from + -cam.basis.z * combat.range_max
	var space := get_world_3d().direct_space_state
	# mask: world geometry (player's mask) + targets (layer 2, movement-transparent)
	var params := PhysicsRayQueryParameters3D.create(from, to, collision_mask | 2, [get_rid()])
	var hit := space.intersect_ray(params)
	var end := to
	var result := "miss"
	if not hit.is_empty():
		end = hit.position
		var collider: Object = hit.collider
		if collider.has_meta("hit_zone"):
			var zone: String = collider.get_meta("hit_zone")
			var damage: int = combat.damage_head if zone == "head" else combat.damage_body
			var target := (collider as Node).get_parent()
			if target is TargetDummy:
				result = "kill" if target.take_hit(damage) else zone
		elif collider is AirfuelPlayer and not collider.ghost_controlled:
			result = "body"
			collider.take_damage.rpc_id(
					collider.get_multiplayer_authority(), combat.damage_body,
					multiplayer.get_unique_id())
	arm.on_fired()
	var side_sign := 1.0 if side == "R" else -1.0
	var vm := vm_right if side == "R" else vm_left
	vm.position += Vector3(0.0, 0.02, 0.16)
	var muzzle: Vector3 = vm.global_transform * Vector3(0, 0, -0.35)
	_spawn_beam(muzzle, end)
	_spawn_canister(side_sign, cam)
	if Net.active:
		if Net.match_opponent != 0:
			_remote_shot_fx.rpc_id(Net.match_opponent, muzzle, end)
		else:
			_remote_shot_fx.rpc(muzzle, end)
	shot_fired.emit(side, result)


func _spawn_beam(from: Vector3, to: Vector3) -> void:
	var dir := to - from
	var length := dir.length()
	if length < 0.05:
		return
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.05, 0.05, length)
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.85, 0.55, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.3)
	mat.emission_energy_multiplier = 4.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(mi)
	mi.global_position = (from + to) * 0.5
	var up := Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT
	mi.look_at(to, up)
	var tw := mi.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.2)
	tw.parallel().tween_property(mat, "emission_energy_multiplier", 0.0, 0.2)
	tw.tween_callback(mi.queue_free)


## One long thin orange line tracing the recent flight path: world-space
## line strip over a rolling position history (2 m samples, ~4 s / 150 pt
## cap), alpha fading toward the tail. Replaces the old particle puffs.
func _update_trail_line() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _trail_pts.is_empty() \
			or _trail_pts[-1].distance_to(global_position) > 2.0:
		_trail_pts.append(global_position + Vector3.UP * 0.4)
		_trail_times.append(now)
	while not _trail_times.is_empty() \
			and (now - _trail_times[0] > 4.0 or _trail_pts.size() > 150):
		_trail_pts.pop_front()
		_trail_times.pop_front()
	_trail_node.global_transform = Transform3D.IDENTITY
	_trail_mesh.clear_surfaces()
	if _trail_pts.size() < 2:
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var n := _trail_pts.size()
	for i in n:
		var a := float(i) / float(n - 1)
		_trail_mesh.surface_set_color(Color(1.0, 0.55, 0.1, a * 0.8))
		_trail_mesh.surface_add_vertex(_trail_pts[i])
	_trail_mesh.surface_end()


func _update_viewmodels(delta: float) -> void:
	for i in 2:
		var vm := vm_left if i == 0 else vm_right
		var mat := vm.material_override as StandardMaterial3D
		if arm_types[i] == "rail":
			var arm := arm_left if i == 0 else arm_right
			mat.emission_energy_multiplier = arm.progress() * 3.0
		else:
			# only the lunging blade flares; the other idles warm
			var flaring: bool = sword_active > 0.0 and sword_side == ("L" if i == 0 else "R")
			mat.emission_energy_multiplier = 2.5 if flaring else 0.3
		vm.position = vm.position.lerp(vm.get_meta("rest_pos"), 1.0 - exp(-12.0 * delta))
		vm.rotation = vm.rotation.lerp(vm.get_meta("pose_rot"), 1.0 - exp(-10.0 * delta))


func _spawn_canister(side_sign: float, cam: Transform3D) -> void:
	var c := CANISTER.instantiate() as RigidBody3D
	get_parent().add_child(c)
	c.global_position = cam.origin + cam.basis.x * 0.35 * side_sign - cam.basis.y * 0.1
	c.linear_velocity = velocity + cam.basis.x * side_sign * 2.5 + cam.basis.y * 2.0 + cam.basis.z * 1.5
	c.angular_velocity = Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12))


func _update_state() -> void:
	if state == MoveState.WALLRUN:
		return
	if is_on_floor():
		state = MoveState.GROUNDED
		return
	if state == MoveState.GROUNDED and velocity.y <= 1.0:
		ground_coyote_timer = config.ground_coyote_time  # walked off an edge, not a jump
	state = MoveState.AIRBORNE
	_try_attach_wall()


func _air_accelerate(wish: Vector3, accel: float, cap: float, delta: float) -> void:
	var cur := velocity.dot(wish)
	var add := clampf(cap - cur, 0.0, accel * delta)
	velocity += wish * add


func _decay_excess_speed(rate: float, delta: float) -> void:
	var h := Vector3(velocity.x, 0.0, velocity.z)
	var hs := h.length()
	if hs <= config.base_run_speed:
		return
	var ns := move_toward(hs, config.base_run_speed, rate * delta)
	velocity.x *= ns / hs
	velocity.z *= ns / hs


## Momentum-preserving glide (Celeste-style): a glancing hit on a wall-ish
## surface redirects horizontal speed along the surface instead of eating it.
## Near-head-on impacts (past glide_max_impact_angle_deg from the surface)
## still stop you — commitment reads as a real collision, grazing doesn't.
func _apply_glide(pre_vel: Vector3) -> void:
	if get_slide_collision_count() == 0:
		return
	var pre_h := Vector3(pre_vel.x, 0.0, pre_vel.z)
	var pre_speed := pre_h.length()
	if pre_speed < 0.5:
		return
	var post_h := Vector3(velocity.x, 0.0, velocity.z)
	if post_h.length() >= pre_speed * 0.98:
		return
	var normal := Vector3.ZERO
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if absf(n.y) < 0.4:
			normal = n
			break
	if normal == Vector3.ZERO:
		return
	var pre_dir := pre_h / pre_speed
	if absf(pre_dir.dot(normal)) > sin(deg_to_rad(config.glide_max_impact_angle_deg)):
		return
	var slide := pre_h.slide(normal)
	if slide.length() < 0.05:
		return
	var target := pre_speed * config.glide_speed_retention
	if target > post_h.length():
		var dir := slide.normalized()
		velocity.x = dir.x * target
		velocity.z = dir.z * target


## The jump-dismount boost, applied during the wall-coyote window after the
## wall ended. Fuel was already granted at falloff — this only adds the boost.
func _coyote_walljump() -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var dir := flat.normalized() if flat.length() > 0.1 else -global_transform.basis.z
	var boosted := minf(coyote_wall_speed * (1.0 + config.dismount_boost_factor),
			config.terminal_velocity)
	velocity.x = dir.x * boosted + coyote_wall_normal.x * config.dismount_push_off
	velocity.z = dir.z * boosted + coyote_wall_normal.z * config.dismount_push_off
	velocity.y = maxf(velocity.y, config.dismount_up_velocity)
	ramp_grace_timer = config.ramp_grace_window
	wall_coyote_timer = 0.0


func _spend(amount: float) -> bool:
	if fuel < amount:
		return false
	fuel -= amount
	return true


func _gather_input() -> void:
	if ghost_controlled:
		return  # controller wrote the cmds (process_physics_priority < 0)
	cmd_move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	cmd_vert = -1.0 if Input.is_action_pressed("strafe_down") else 0.0
	cmd_jump = Input.is_action_just_pressed("jump")
	cmd_dash = Input.is_action_just_pressed("dash")
	cmd_fire_l = Input.is_action_just_pressed("fire_left")
	cmd_fire_r = Input.is_action_just_pressed("fire_right")
	cmd_swap = Input.is_action_just_pressed("swap_loadout")
	cmd_respawn = Input.is_action_just_pressed("respawn")
	if Input.is_action_just_pressed("record"):
		_toggle_recording()


func _wish_dir() -> Vector3:
	if cmd_move == Vector2.ZERO:
		return Vector3.ZERO
	var b := global_transform.basis
	return (b.x * cmd_move.x + -b.z * -cmd_move.y).normalized()





func _camera_feel(delta: float) -> void:
	var target_roll := 0.0
	if state == MoveState.WALLRUN:
		var side := signf((-wall_normal).dot(global_transform.basis.x))
		target_roll = side * deg_to_rad(config.wallrun_camera_roll_deg)
	camera.rotation.z = lerpf(camera.rotation.z, target_roll,
			1.0 - exp(-config.wallrun_camera_roll_speed * delta))

	var hs := Vector3(velocity.x, 0.0, velocity.z).length()
	var target_fov := base_fov + clampf(hs - config.base_run_speed, 0.0, 25.0) * 0.6
	if state == MoveState.WALLRUN:
		target_fov += config.wallrun_fov_bonus
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-6.0 * delta))


## LAN-trust damage: the shooter reports the hit, the victim's authority
## applies it. 2 HP, every rail hit = 1 -> two shots to kill; a kill resets
## BOTH duelists to spawn (design 9: no regen, no partial states).
@rpc("any_peer", "call_remote", "reliable")
func take_damage(amount: int, from_id: int) -> void:
	if not is_multiplayer_authority():
		return
	hp -= amount
	damaged.emit(amount, from_id)
	if hp <= 0:
		died.emit()
		if Net.match_opponent != 0:
			# Lobby match: the server keeps score (first-to-N) and relays
			Net.report_match_kill.rpc_id(1, from_id)
		else:
			Net.report_kill.rpc(from_id, multiplayer.get_unique_id())
		_respawn()


## Round reset: both duelists return to spawn after a kill. Called locally
## (victim) and via Net.kill_scored (killer, with the KILL hitmarker).
func round_reset(scored_kill: bool) -> void:
	if scored_kill:
		shot_fired.emit("", "kill")
	_respawn()


@rpc("authority", "call_remote", "unreliable")
func _remote_shot_fx(from: Vector3, to: Vector3) -> void:
	_spawn_beam(from, to)


@rpc("authority", "call_remote", "unreliable_ordered")
func _send_state(pos: Vector3, vel: Vector3, yaw: float, pitch: float,
		prog_l: float, prog_r: float, l_idx: int) -> void:
	_net_target_pos = pos
	velocity = vel
	rotation.y = yaw
	head.rotation.x = pitch
	_net_prog = Vector2(prog_l, prog_r)
	if l_idx != loadout_index:
		loadout_index = l_idx
		arm_types = LOADOUTS[l_idx]
		for i in 2:
			var mat := (puppet_arm_l if i == 0 else puppet_arm_r).material_override as StandardMaterial3D
			mat.albedo_color = SWORD_VM_COLOR if arm_types[i] == "sword" else RAIL_VM_COLOR


## F5: record this run's inputs, one line per physics tick, for TAS ghost
## playback. Starting a recording respawns you first so the tape begins from
## the exact spawn state; stopping writes user://tas/ and prints the path.
func _toggle_recording() -> void:
	if not recording:
		_respawn()
		_tape_lines.clear()
		_tape_lines.append("# airfuel-tas v1 map=%s tick_hz=%d loadout=%d" % [
				get_tree().current_scene.scene_file_path,
				Engine.physics_ticks_per_second, loadout_index])
		recording = true
		return
	recording = false
	DirAccess.make_dir_recursive_absolute("user://tas")
	var fname := "user://tas/run_%s.tas" % Time.get_datetime_string_from_system().replace(":", "-")
	var f := FileAccess.open(fname, FileAccess.WRITE)
	if f == null:
		push_error("Airfuel: could not write %s" % fname)
		return
	f.store_string("\n".join(_tape_lines))
	f.close()
	print("Airfuel: TAS tape saved: %s (%d ticks) — real path: %s" % [
			fname, _tape_lines.size() - 1,
			ProjectSettings.globalize_path(fname)])


## Crossing a FinishZone: freeze the run clock; a live recording stops and
## saves here too, so a finished run yields a complete tape of itself.
func finish_run() -> void:
	if run_finished:
		return
	run_finished = true
	if recording:
		_toggle_recording()


func _respawn() -> void:
	global_transform = spawn_transform
	velocity = Vector3.ZERO
	fuel = config.fuel_max
	hp = combat.hp_max
	run_time = 0.0
	run_finished = false
	countdown = config.reset_countdown
	_trail_pts.clear()
	_trail_times.clear()
	# Deterministic reset: recordings and replays must start from identical
	# state, so no timer or arm state survives a respawn
	dash_cooldown_timer = 0.0
	double_jump_timer = 0.0
	wall_coyote_timer = 0.0
	ground_coyote_timer = 0.0
	jump_buffer_timer = 0.0
	wall_rearm_timer = 0.0
	ramp_grace_timer = 0.0
	sword_cd = [0.0, 0.0]
	sword_active = 0.0
	arm_left.reset()
	arm_right.reset()
	pending_arms.clear()
	if recording:
		# any reset (T, fall, F5) restarts the tape: a recording is always
		# one clean spawn-to-finish attempt, never a spliced teleport
		_tape_lines.clear()
		_tape_lines.append("# airfuel-tas v1 map=%s tick_hz=%d loadout=%d" % [
				get_tree().current_scene.scene_file_path,
				Engine.physics_ticks_per_second, loadout_index])
	respawned.emit()
	state = MoveState.AIRBORNE
	ramp_grace_timer = 0.0
	wallrun_time = 0.0
	wall_speed = 0.0
	head.rotation.x = 0.0


func horizontal_speed() -> float:
	return Vector3(velocity.x, 0.0, velocity.z).length()


func arm_progress_left() -> float:
	if arm_types[0] == "sword":
		return 1.0 - clampf(sword_cd[0] / combat.sword_lunge_cooldown, 0.0, 1.0)
	return arm_left.progress()


func arm_progress_right() -> float:
	if arm_types[1] == "sword":
		return 1.0 - clampf(sword_cd[1] / combat.sword_lunge_cooldown, 0.0, 1.0)
	return arm_right.progress()


## Synced arm progress of a remote puppet (from _send_state) — the HUD's
## charge-warning source. Meaningless on locally simulated bodies.
func remote_arm_progress(index: int) -> float:
	return _net_prog.x if index == 0 else _net_prog.y


func state_name() -> String:
	match state:
		MoveState.GROUNDED:
			return "GROUNDED"
		MoveState.WALLRUN:
			return "WALLRUN"
		_:
			return "AIRBORNE"
