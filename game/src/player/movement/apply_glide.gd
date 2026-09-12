extends Object

## Definition: momentum-preserving glide (Celeste-style) — a glancing hit on
## a wall-ish surface redirects horizontal speed along the surface instead of
## eating it. Near-head-on impacts (past glide_max_impact_angle_deg from the
## surface) still stop you — commitment reads as a real collision, grazing
## doesn't. Takes the tick's slide collisions as plain data rows
## `{normal: Vector3, deflector: bool}`. Spec: apply_glide.gd.md.


static func apply_glide(
	sim: MoveSim, cfg: MovementConfig, pre_vel: Vector3, collisions: Array[Dictionary]
) -> void:
	if collisions.is_empty():
		return
	var pre_h := Vector3(pre_vel.x, 0.0, pre_vel.z)
	var pre_speed := pre_h.length()
	if pre_speed < 0.5:
		return
	var post_h := Vector3(sim.velocity.x, 0.0, sim.velocity.z)
	if post_h.length() >= pre_speed * 0.98:
		return
	var normal := Vector3.ZERO
	var deflector := false
	for col: Dictionary in collisions:
		var n: Vector3 = col.normal
		if absf(n.y) < 0.4:
			normal = n
			# Map-authored "deflector" geometry (pointed kite obstacles):
			# even a dead-center hit splits you around it instead of
			# stopping — the head-on rejection below is skipped.
			deflector = col.deflector
			break
	if normal == Vector3.ZERO:
		return
	var pre_dir := pre_h / pre_speed
	if (
		not deflector
		and absf(pre_dir.dot(normal)) > sin(deg_to_rad(cfg.glide_max_impact_angle_deg))
	):
		return
	var slide := pre_h.slide(normal)
	if slide.length() < 0.05:
		return
	var target: float = pre_speed * cfg.glide_speed_retention
	if target > post_h.length():
		var dir := slide.normalized()
		sim.velocity.x = dir.x * target
		sim.velocity.z = dir.z * target
