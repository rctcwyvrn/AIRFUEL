extends Object

## Definition: airborne wall acquisition — 12 radial probes, the rearm-cone
## and approach-velocity rejects, nearest hit wins. Takes the wall-probe
## capability as a Callable `(dir, dist_scale) -> Dictionary` plus the body
## origin for the distance test. Spec: try_attach_wall.gd.md.


static func try_attach_wall(
	sim: MoveSim, cfg: MovementConfig, origin: Vector3, probe: Callable
) -> void:
	var flat := Vector3(sim.velocity.x, 0.0, sim.velocity.z)
	if flat.length() < cfg.min_wallrun_speed:
		return

	var best := {}
	var best_dist := INF
	for i in 12:
		var ang := TAU * float(i) / 12.0
		var hit: Dictionary = probe.call(Vector3(cos(ang), 0.0, sin(ang)), 1.0)
		if hit.is_empty():
			continue
		if (
			sim.wall_rearm_timer > 0.0
			and (hit.normal as Vector3).angle_to(sim.last_wall_normal) < deg_to_rad(25.0)
		):
			continue
		if sim.velocity.dot(hit.normal) > 2.0:
			continue
		var d: float = origin.distance_to(hit.position)
		if d < best_dist:
			best_dist = d
			best = hit

	if best.is_empty():
		return
	sim.wall_normal = best.normal
	sim.wallrun_time = 0.0
	sim.wall_speed = flat.slide(sim.wall_normal).length()
	sim.wall_coyote_timer = 0.0
	sim.state = MoveSim.MoveState.WALLRUN
