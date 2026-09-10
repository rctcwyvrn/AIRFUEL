class_name PlayerMovement
extends Object

## The player's movement layer (DESIGN.md §4, §5), split out of player.gd:
## ground/air/wallrun moves, dashes, dismounts, wall probes, glide, and the
## coyote assists. Same pattern as PlayerState: stateless static functions
## over the player body (typed CharacterBody3D — never AirfuelPlayer, so no
## class-resolution cycle). ALL state stays on the player; every function
## here runs inside _simulate() and must stay deterministic (prediction
## replays and TAS ghosts re-run it — the trajectory fingerprint must not
## move).


static func ground_move(p: CharacterBody3D, wish: Vector3, delta: float) -> void:
	if p.move_locked:
		# Charging on the ground roots you (DESIGN.md 7.2)
		p.velocity.x = 0.0
		p.velocity.z = 0.0
		p.velocity.y -= p.config.gravity * delta
		return
	var h := Vector3(p.velocity.x, 0.0, p.velocity.z)
	if wish == Vector3.ZERO:
		h = h.move_toward(Vector3.ZERO, p.config.ground_friction * delta)
	else:
		# Excess speed above base run bleeds off on the ground; the air (ramp
		# grace) and walls are where speed lives.
		var speed := maxf(
			p.config.base_run_speed,
			move_toward(h.length(), p.config.base_run_speed, p.config.ground_friction * delta)
		)
		h = h.move_toward(wish * speed, p.config.ground_accel * delta)
	p.velocity.x = h.x
	p.velocity.z = h.z
	p.velocity.y -= p.config.gravity * delta

	if p.jump_buffer_timer > 0.0:
		p.jump_buffer_timer = 0.0
		p.velocity.y = p.config.jump_velocity


static func air_move(p: CharacterBody3D, wish: Vector3, delta: float) -> void:
	p.velocity.y -= p.config.gravity * delta

	if wish != Vector3.ZERO:
		air_accelerate(p, wish, p.config.air_control_accel, p.config.base_run_speed, delta)
		if (
			p.velocity.dot(wish) < p.config.air_strafe_speed_cap
			and p._spend(p.config.air_strafe_cost_per_sec * delta)
		):
			air_accelerate(p, wish, p.config.air_strafe_accel, p.config.air_strafe_speed_cap, delta)

	if p.ramp_grace_timer > 0.0:
		p.ramp_grace_timer -= delta
	else:
		decay_excess_speed(p, p.config.ramp_decay_rate, delta)

	if not p.move_locked and p.cmd_jump:
		p.jump_buffer_timer = 0.0
		if p.wall_coyote_timer > 0.0:
			coyote_walljump(p)
		elif p.ground_coyote_timer > 0.0:
			p.ground_coyote_timer = 0.0
			p.velocity.y = p.config.jump_velocity
		elif p.double_jump_timer == 0.0 and p._spend(p.config.double_jump_cost):
			p.velocity.y = maxf(p.velocity.y, p.config.double_jump_strength)
			p.double_jump_timer = p.config.double_jump_cooldown


static func wallrun_move(p: CharacterBody3D, delta: float) -> void:
	if p.is_on_floor():
		dismount(p, false)
		return

	# Re-probe every tick so the normal tracks curved surfaces (slot caps).
	var hit := probe_wall_at(p, -p.wall_normal, 1.6)
	if hit.is_empty():
		for s: float in [1.0, -1.0]:
			hit = probe_wall_at(p, (-p.wall_normal).rotated(Vector3.UP, s * 0.6), 1.6)
			if not hit.is_empty():
				break
	if hit.is_empty():
		dismount(p, false)
		return
	var bend := (hit.normal as Vector3).angle_to(p.wall_normal)
	if (
		bend > deg_to_rad(p.config.wallrun_corner_dismount_deg)
		and bend < deg_to_rad(p.config.wallrun_corner_wrap_deg)
		and p.velocity.dot(hit.normal) > 0.0
	):
		# A moderate CONVEX corner (a wedge apex — surface falls away and
		# we're moving off it): launch along the tangent with velocity
		# intact instead of folding onto the far face and eating the speed.
		# Concave corners and hairpins (>= wrap_deg) still track: wrapping
		# a switchback or an obstacle end stays legitimate technique.
		dismount(p, false)
		return
	p.wall_normal = hit.normal

	p.wallrun_time += delta
	if p.wallrun_time > p.config.wallrun_max_duration:
		dismount(p, false)
		return

	var flat := Vector3(p.velocity.x, 0.0, p.velocity.z).slide(p.wall_normal)
	p.wall_speed = flat.length()
	if p.wall_speed < p.config.min_wallrun_speed:
		dismount(p, false)
		return

	p.wall_speed = move_toward(
		p.wall_speed, p.config.wallrun_max_speed, p.config.wallrun_accel * delta
	)
	var dir := flat.normalized()
	p.velocity.x = dir.x * p.wall_speed - p.wall_normal.x * p.config.wall_stick_speed
	p.velocity.z = dir.z * p.wall_speed - p.wall_normal.z * p.config.wall_stick_speed
	p.velocity.y = move_toward(p.velocity.y, 0.0, 20.0 * delta) - p.config.wallrun_gravity * delta

	if not p.move_locked and p.cmd_jump:
		p.jump_buffer_timer = 0.0
		dismount(p, true)


## Reward on dismount, scaled to along-wall speed (slow wall-hugging gives
## near-nothing). A jump dismount also gets the speed boost; falling off or
## timing out grants fuel only.
static func dismount(p: CharacterBody3D, jumped: bool) -> void:
	var grant := clampf(
		(p.wall_speed - p.config.min_wallrun_speed) * p.config.dismount_fuel_per_speed,
		0.0,
		p.config.dismount_fuel_max
	)
	p.fuel = minf(p.config.fuel_max, p.fuel + grant)

	if jumped:
		var flat := Vector3(p.velocity.x, 0.0, p.velocity.z)
		var dir := flat.normalized() if flat.length() > 0.1 else -p.global_transform.basis.z
		var boosted := minf(
			p.wall_speed * (1.0 + p.config.dismount_boost_factor), p.config.terminal_velocity
		)
		p.velocity.x = dir.x * boosted + p.wall_normal.x * p.config.dismount_push_off
		p.velocity.z = dir.z * boosted + p.wall_normal.z * p.config.dismount_push_off
		p.velocity.y = maxf(p.velocity.y, p.config.dismount_up_velocity)

	if not jumped:
		# Wall coyote (Celeste-style): the dismount jump stays available briefly
		p.wall_coyote_timer = p.config.wall_coyote_time
		p.coyote_wall_normal = p.wall_normal
		p.coyote_wall_speed = p.wall_speed
	else:
		p.wall_coyote_timer = 0.0

	p.ramp_grace_timer = p.config.ramp_grace_window
	p.last_wall_normal = p.wall_normal
	p.wall_rearm_timer = p.config.wall_rearm_time
	p.wallrun_time = 0.0
	p.wall_speed = 0.0
	p.state = p.MoveState.AIRBORNE


static func try_attach_wall(p: CharacterBody3D) -> void:
	var flat := Vector3(p.velocity.x, 0.0, p.velocity.z)
	if flat.length() < p.config.min_wallrun_speed:
		return

	var best := {}
	var best_dist := INF
	for i in 12:
		var ang := TAU * float(i) / 12.0
		var hit := probe_wall_at(p, Vector3(cos(ang), 0.0, sin(ang)))
		if hit.is_empty():
			continue
		if (
			p.wall_rearm_timer > 0.0
			and (hit.normal as Vector3).angle_to(p.last_wall_normal) < deg_to_rad(25.0)
		):
			continue
		if p.velocity.dot(hit.normal) > 2.0:
			continue
		var d: float = p.global_position.distance_to(hit.position)
		if d < best_dist:
			best_dist = d
			best = hit

	if best.is_empty():
		return
	p.wall_normal = best.normal
	p.wallrun_time = 0.0
	p.wall_speed = flat.slide(p.wall_normal).length()
	p.wall_coyote_timer = 0.0
	p.state = p.MoveState.WALLRUN


static func probe_wall_at(p: CharacterBody3D, dir: Vector3, dist_scale := 1.0) -> Dictionary:
	var space := p.get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(
		p.global_position,
		p.global_position + dir.normalized() * p.config.wall_probe_distance * dist_scale,
		p.collision_mask,
		[p.get_rid()]
	)
	var hit := space.intersect_ray(params)
	if hit.is_empty() or absf(hit.normal.y) > 0.4:
		return {}
	return hit


static func handle_dashes(p: CharacterBody3D) -> void:
	if p.move_locked:
		return
	var on_wall: bool = p.state == p.MoveState.WALLRUN
	if p.cmd_down_dash:
		# Q is the down dash (DESIGN.md 4.4): own tuning, no cooldown. On a
		# wall you STAY attached and slide down it fast. Independent of
		# Shift — pressing Q always means straight down.
		if (on_wall or p.state == p.MoveState.AIRBORNE) and p._spend(p.config.down_dash_cost):
			p.velocity.y = minf(p.velocity.y, -p.config.down_dash_speed)
	if not p.cmd_dash:
		return
	var input: Vector2 = p.cmd_move
	if input == Vector2.ZERO:
		return  # bare Shift is inert: a directional dash needs held WASD
	if p.dash_cooldown_timer > 0.0 or not p._spend(p.config.air_dash_cost):
		return
	if on_wall:
		# Dashing off the wall is a real dismount: same fuel grant and speed
		# boost as jumping off, with the dash impulse stacked on top — but
		# the wall you left is locked out for longer (anti-pogo: dashing
		# straight back in compounded boosts to absurd speeds)
		dismount(p, true)
		p.wall_rearm_timer = p.config.dash_wall_rearm_time
	# Camera-aimed: W+Shift dashes wherever you're looking (pitch included)
	var cb: Basis = p.camera.global_transform.basis
	var dir := (cb.x * input.x + -cb.z * -input.y).normalized()
	p.velocity += dir * p.config.air_dash_impulse
	p.dash_cooldown_timer = p.config.air_dash_cooldown


static func update_state(p: CharacterBody3D) -> void:
	if p.state == p.MoveState.WALLRUN:
		return
	if p.is_on_floor():
		p.state = p.MoveState.GROUNDED
		return
	if p.state == p.MoveState.GROUNDED and p.velocity.y <= 1.0:
		p.ground_coyote_timer = p.config.ground_coyote_time  # walked off an edge, not a jump
	p.state = p.MoveState.AIRBORNE
	try_attach_wall(p)


static func air_accelerate(
	p: CharacterBody3D, wish: Vector3, accel: float, cap: float, delta: float
) -> void:
	var cur: float = p.velocity.dot(wish)
	var add := clampf(cap - cur, 0.0, accel * delta)
	p.velocity += wish * add


static func decay_excess_speed(p: CharacterBody3D, rate: float, delta: float) -> void:
	var h := Vector3(p.velocity.x, 0.0, p.velocity.z)
	var hs := h.length()
	if hs <= p.config.base_run_speed:
		return
	var ns := move_toward(hs, p.config.base_run_speed, rate * delta)
	p.velocity.x *= ns / hs
	p.velocity.z *= ns / hs


## Momentum-preserving glide (Celeste-style): a glancing hit on a wall-ish
## surface redirects horizontal speed along the surface instead of eating it.
## Near-head-on impacts (past glide_max_impact_angle_deg from the surface)
## still stop you — commitment reads as a real collision, grazing doesn't.
static func apply_glide(p: CharacterBody3D, pre_vel: Vector3) -> void:
	if p.get_slide_collision_count() == 0:
		return
	var pre_h := Vector3(pre_vel.x, 0.0, pre_vel.z)
	var pre_speed := pre_h.length()
	if pre_speed < 0.5:
		return
	var post_h := Vector3(p.velocity.x, 0.0, p.velocity.z)
	if post_h.length() >= pre_speed * 0.98:
		return
	var normal := Vector3.ZERO
	var deflector := false
	for i in p.get_slide_collision_count():
		var col: KinematicCollision3D = p.get_slide_collision(i)
		var n := col.get_normal()
		if absf(n.y) < 0.4:
			normal = n
			var body := col.get_collider() as Node
			# Map-authored "deflector" geometry (pointed kite obstacles):
			# even a dead-center hit splits you around it instead of
			# stopping — the head-on rejection below is skipped.
			deflector = body != null and body.has_meta("deflector")
			break
	if normal == Vector3.ZERO:
		return
	var pre_dir := pre_h / pre_speed
	if (
		not deflector
		and absf(pre_dir.dot(normal)) > sin(deg_to_rad(p.config.glide_max_impact_angle_deg))
	):
		return
	var slide := pre_h.slide(normal)
	if slide.length() < 0.05:
		return
	var target: float = pre_speed * p.config.glide_speed_retention
	if target > post_h.length():
		var dir := slide.normalized()
		p.velocity.x = dir.x * target
		p.velocity.z = dir.z * target


## The jump-dismount boost, applied during the wall-coyote window after the
## wall ended. Fuel was already granted at falloff — this only adds the boost.
static func coyote_walljump(p: CharacterBody3D) -> void:
	var flat := Vector3(p.velocity.x, 0.0, p.velocity.z)
	var dir := flat.normalized() if flat.length() > 0.1 else -p.global_transform.basis.z
	var boosted := minf(
		p.coyote_wall_speed * (1.0 + p.config.dismount_boost_factor), p.config.terminal_velocity
	)
	p.velocity.x = dir.x * boosted + p.coyote_wall_normal.x * p.config.dismount_push_off
	p.velocity.z = dir.z * boosted + p.coyote_wall_normal.z * p.config.dismount_push_off
	p.velocity.y = maxf(p.velocity.y, p.config.dismount_up_velocity)
	p.ramp_grace_timer = p.config.ramp_grace_window
	p.wall_coyote_timer = 0.0


static func wish_dir(p: CharacterBody3D) -> Vector3:
	var m: Vector2 = p.cmd_move
	if m == Vector2.ZERO:
		return Vector3.ZERO
	var b: Basis = p.global_transform.basis
	return (b.x * m.x + -b.z * -m.y).normalized()
