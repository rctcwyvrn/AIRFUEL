class_name AirfuelPlayer
extends CharacterBody3D

## Roadmap Step 1: movement alone.
## Wallrun (flat + curved via radial ray probes), dismount fuel/speed grants,
## ramp persistence across gaps, air dash, down dash, double jump / fueled
## air strafe, terminal velocity. No weapons, no network.

enum MoveState { GROUNDED, AIRBORNE, WALLRUN }

@export var config: MovementConfig
@export var mouse_sensitivity := 0.0022

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D

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

var base_fov := 100.0
var spawn_transform: Transform3D


func _ready() -> void:
	fuel = config.fuel_max
	spawn_transform = global_transform
	base_fov = camera.fov
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x, -PI / 2 + 0.05, PI / 2 - 0.05)
	elif event.is_action_pressed("ui_cancel"):
		var captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED)


func _physics_process(delta: float) -> void:
	dash_cooldown_timer = maxf(0.0, dash_cooldown_timer - delta)
	double_jump_timer = maxf(0.0, double_jump_timer - delta)
	wall_rearm_timer = maxf(0.0, wall_rearm_timer - delta)

	var wish := _wish_dir()

	match state:
		MoveState.GROUNDED:
			_ground_move(wish, delta)
		MoveState.AIRBORNE:
			_air_move(wish, delta)
		MoveState.WALLRUN:
			_wallrun_move(delta)

	_handle_dashes()

	velocity = velocity.limit_length(config.terminal_velocity)
	velocity.y = maxf(velocity.y, -config.terminal_fall_speed)

	move_and_slide()
	_update_state()
	_camera_feel(delta)

	if Input.is_action_just_pressed("respawn") or global_position.y < config.kill_y:
		_respawn()


func _ground_move(wish: Vector3, delta: float) -> void:
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

	if Input.is_action_just_pressed("jump"):
		velocity.y = config.jump_velocity


func _air_move(wish: Vector3, delta: float) -> void:
	velocity.y -= config.gravity * delta

	if wish != Vector3.ZERO:
		_air_accelerate(wish, config.air_control_accel, config.base_run_speed, delta)
		if velocity.dot(wish) < config.air_strafe_speed_cap \
				and _spend(config.air_strafe_cost_per_sec * delta):
			_air_accelerate(wish, config.air_strafe_accel, config.air_strafe_speed_cap, delta)

	if ramp_grace_timer > 0.0:
		ramp_grace_timer -= delta
	else:
		_decay_excess_speed(config.ramp_decay_rate, delta)

	if Input.is_action_just_pressed("jump") and double_jump_timer == 0.0 \
			and _spend(config.double_jump_cost):
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

	if Input.is_action_just_pressed("jump"):
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
		var boosted := wall_speed * (1.0 + config.dismount_boost_factor)
		velocity.x = dir.x * boosted + wall_normal.x * config.dismount_push_off
		velocity.z = dir.z * boosted + wall_normal.z * config.dismount_push_off
		velocity.y = maxf(velocity.y, config.dismount_up_velocity)

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
	if state == MoveState.WALLRUN:
		return
	if Input.is_action_just_pressed("dash") and dash_cooldown_timer == 0.0 \
			and _spend(config.air_dash_cost):
		velocity += _aim_dir() * config.air_dash_impulse
		dash_cooldown_timer = config.air_dash_cooldown
	if Input.is_action_just_pressed("down_dash") and state == MoveState.AIRBORNE \
			and _spend(config.down_dash_cost):
		velocity.y = minf(velocity.y, -config.down_dash_speed)


func _update_state() -> void:
	if state == MoveState.WALLRUN:
		return
	if is_on_floor():
		state = MoveState.GROUNDED
		return
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


func _spend(amount: float) -> bool:
	if fuel < amount:
		return false
	fuel -= amount
	return true


func _wish_dir() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input == Vector2.ZERO:
		return Vector3.ZERO
	var b := global_transform.basis
	return (b.x * input.x + -b.z * -input.y).normalized()


## Omnidirectional, camera-relative (pitch included) — no input dashes forward.
func _aim_dir() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cb := camera.global_transform.basis
	if input == Vector2.ZERO:
		return -cb.z
	return (cb.x * input.x + -cb.z * -input.y).normalized()


func _camera_feel(delta: float) -> void:
	var target_roll := 0.0
	if state == MoveState.WALLRUN:
		var side := signf((-wall_normal).dot(global_transform.basis.x))
		target_roll = side * deg_to_rad(config.wallrun_camera_roll_deg)
	camera.rotation.z = lerpf(camera.rotation.z, target_roll, 1.0 - exp(-10.0 * delta))

	var hs := Vector3(velocity.x, 0.0, velocity.z).length()
	var target_fov := base_fov + clampf(hs - config.base_run_speed, 0.0, 25.0) * 0.6
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-6.0 * delta))


func _respawn() -> void:
	global_transform = spawn_transform
	velocity = Vector3.ZERO
	fuel = config.fuel_max
	state = MoveState.AIRBORNE
	ramp_grace_timer = 0.0
	wallrun_time = 0.0
	wall_speed = 0.0
	head.rotation.x = 0.0


func horizontal_speed() -> float:
	return Vector3(velocity.x, 0.0, velocity.z).length()


func state_name() -> String:
	match state:
		MoveState.GROUNDED:
			return "GROUNDED"
		MoveState.WALLRUN:
			return "WALLRUN"
		_:
			return "AIRBORNE"
