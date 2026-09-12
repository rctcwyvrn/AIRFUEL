extends Object

## Definition: leaving a wall — fuel grant scaled to along-wall speed (slow
## wall-hugging gives near-nothing), the jump-dismount launch boost, the
## coyote window on falloff, and the anti-pogo lockout of the wall just left.
## A jump dismount also gets the speed boost; falling off or timing out
## grants fuel only. Spec: dismount.gd.md.


static func dismount(sim: MoveSim, cfg: MovementConfig, jumped: bool, facing: Vector3) -> void:
	var grant := clampf(
		(sim.wall_speed - cfg.min_wallrun_speed) * cfg.dismount_fuel_per_speed,
		0.0,
		cfg.dismount_fuel_max
	)
	sim.fuel = minf(cfg.fuel_max, sim.fuel + grant)

	if jumped:
		var flat := Vector3(sim.velocity.x, 0.0, sim.velocity.z)
		var dir := flat.normalized() if flat.length() > 0.1 else facing
		var boosted := minf(
			sim.wall_speed * (1.0 + cfg.dismount_boost_factor), cfg.terminal_velocity
		)
		sim.velocity.x = dir.x * boosted + sim.wall_normal.x * cfg.dismount_push_off
		sim.velocity.z = dir.z * boosted + sim.wall_normal.z * cfg.dismount_push_off
		sim.velocity.y = maxf(sim.velocity.y, cfg.dismount_up_velocity)

	if not jumped:
		# Wall coyote (Celeste-style): the dismount jump stays available briefly
		sim.wall_coyote_timer = cfg.wall_coyote_time
		sim.coyote_wall_normal = sim.wall_normal
		sim.coyote_wall_speed = sim.wall_speed
	else:
		sim.wall_coyote_timer = 0.0

	sim.ramp_grace_timer = cfg.ramp_grace_window
	sim.last_wall_normal = sim.wall_normal
	sim.wall_rearm_timer = cfg.wall_rearm_time
	sim.wallrun_time = 0.0
	sim.wall_speed = 0.0
	sim.state = MoveSim.MoveState.AIRBORNE
