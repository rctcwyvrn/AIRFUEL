extends Object

## Definition: the jump-dismount boost, applied during the wall-coyote window
## after the wall ended. Fuel was already granted at falloff — this only adds
## the boost. Spec: coyote_walljump.gd.md.


static func coyote_walljump(sim: MoveSim, cfg: MovementConfig, facing: Vector3) -> void:
	var flat := Vector3(sim.velocity.x, 0.0, sim.velocity.z)
	var dir := flat.normalized() if flat.length() > 0.1 else facing
	var boosted := minf(
		sim.coyote_wall_speed * (1.0 + cfg.dismount_boost_factor), cfg.terminal_velocity
	)
	sim.velocity.x = dir.x * boosted + sim.coyote_wall_normal.x * cfg.dismount_push_off
	sim.velocity.z = dir.z * boosted + sim.coyote_wall_normal.z * cfg.dismount_push_off
	sim.velocity.y = maxf(sim.velocity.y, cfg.dismount_up_velocity)
	sim.ramp_grace_timer = cfg.ramp_grace_window
	sim.wall_coyote_timer = 0.0
