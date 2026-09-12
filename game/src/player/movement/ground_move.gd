extends Object

## Definition: one GROUNDED-state tick — friction toward rest or acceleration
## toward wish at base run speed, gravity, and the buffered jump. Spec:
## ground_move.gd.md.


static func ground_move(sim: MoveSim, cfg: MovementConfig, wish: Vector3, delta: float) -> void:
	if sim.move_locked:
		# Charging on the ground roots you (DESIGN.md 7.2)
		sim.velocity.x = 0.0
		sim.velocity.z = 0.0
		sim.velocity.y -= cfg.gravity * delta
		return
	var h := Vector3(sim.velocity.x, 0.0, sim.velocity.z)
	if wish == Vector3.ZERO:
		h = h.move_toward(Vector3.ZERO, cfg.ground_friction * delta)
	else:
		# Excess speed above base run bleeds off on the ground; the air (ramp
		# grace) and walls are where speed lives.
		var speed := maxf(
			cfg.base_run_speed,
			move_toward(h.length(), cfg.base_run_speed, cfg.ground_friction * delta)
		)
		h = h.move_toward(wish * speed, cfg.ground_accel * delta)
	sim.velocity.x = h.x
	sim.velocity.z = h.z
	sim.velocity.y -= cfg.gravity * delta

	if sim.jump_buffer_timer > 0.0:
		sim.jump_buffer_timer = 0.0
		sim.velocity.y = cfg.jump_velocity
