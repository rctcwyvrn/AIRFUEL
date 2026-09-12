extends Object

## Definition: one WALLRUN-state tick — re-probe the wall (curved surfaces
## track), corner-bend policy, duration/speed integration, stick force, and
## the dismount exits. Takes the wall-probe capability as a Callable
## `(dir: Vector3, dist_scale: float) -> Dictionary` — tests inject fakes.
## Spec: wallrun_move.gd.md.

const Dismount := preload("dismount.gd")


static func wallrun_move(
	sim: MoveSim,
	cfg: MovementConfig,
	on_floor: bool,
	jump: bool,
	facing: Vector3,
	probe: Callable,
	delta: float,
) -> void:
	if on_floor:
		Dismount.dismount(sim, cfg, false, facing)
		return

	# Re-probe every tick so the normal tracks curved surfaces (slot caps).
	var hit: Dictionary = probe.call(-sim.wall_normal, 1.6)
	if hit.is_empty():
		for s: float in [1.0, -1.0]:
			hit = probe.call((-sim.wall_normal).rotated(Vector3.UP, s * 0.6), 1.6)
			if not hit.is_empty():
				break
	if hit.is_empty():
		Dismount.dismount(sim, cfg, false, facing)
		return
	var bend := (hit.normal as Vector3).angle_to(sim.wall_normal)
	if (
		bend > deg_to_rad(cfg.wallrun_corner_dismount_deg)
		and bend < deg_to_rad(cfg.wallrun_corner_wrap_deg)
		and sim.velocity.dot(hit.normal) > 0.0
	):
		# A moderate CONVEX corner (a wedge apex — surface falls away and
		# we're moving off it): launch along the tangent with velocity
		# intact instead of folding onto the far face and eating the speed.
		# Concave corners and hairpins (>= wrap_deg) still track: wrapping
		# a switchback or an obstacle end stays legitimate technique.
		Dismount.dismount(sim, cfg, false, facing)
		return
	sim.wall_normal = hit.normal

	sim.wallrun_time += delta
	if sim.wallrun_time > cfg.wallrun_max_duration:
		Dismount.dismount(sim, cfg, false, facing)
		return

	var flat := Vector3(sim.velocity.x, 0.0, sim.velocity.z).slide(sim.wall_normal)
	sim.wall_speed = flat.length()
	if sim.wall_speed < cfg.min_wallrun_speed:
		Dismount.dismount(sim, cfg, false, facing)
		return

	sim.wall_speed = move_toward(sim.wall_speed, cfg.wallrun_max_speed, cfg.wallrun_accel * delta)
	var dir := flat.normalized()
	sim.velocity.x = dir.x * sim.wall_speed - sim.wall_normal.x * cfg.wall_stick_speed
	sim.velocity.z = dir.z * sim.wall_speed - sim.wall_normal.z * cfg.wall_stick_speed
	sim.velocity.y = move_toward(sim.velocity.y, 0.0, 20.0 * delta) - cfg.wallrun_gravity * delta

	if not sim.move_locked and jump:
		sim.jump_buffer_timer = 0.0
		Dismount.dismount(sim, cfg, true, facing)
