class_name PlayerFx
extends Object

## Stateless one-shot combat cosmetics (DESIGN.md §17 feedback beats), split
## out of player.gd: the rail beam and the ejected canister. Pure visuals —
## nothing here may affect simulation (prediction replays skip them
## entirely, and the headless server never calls them).

const CANISTER := preload("res://src/weapons/canister.tscn")


## Fading emissive beam from muzzle to impact, parented next to the shooter
## (world space). Also used by Net for an opponent's shot on REPLICA bodies.
static func spawn_beam(parent: Node, from: Vector3, to: Vector3) -> void:
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
	parent.add_child(mi)
	mi.global_position = (from + to) * 0.5
	var up := Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT
	mi.look_at(to, up)
	var tw := mi.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.2)
	tw.parallel().tween_property(mat, "emission_energy_multiplier", 0.0, 0.2)
	tw.tween_callback(mi.queue_free)


## Spent canister ejected sideways from the firing arm (8.1 bolt action).
static func spawn_canister(shooter: CharacterBody3D, side_sign: float, cam: Transform3D) -> void:
	var c := CANISTER.instantiate() as RigidBody3D
	shooter.get_parent().add_child(c)
	c.global_position = cam.origin + cam.basis.x * 0.35 * side_sign - cam.basis.y * 0.1
	c.linear_velocity = (
		shooter.velocity + cam.basis.x * side_sign * 2.5 + cam.basis.y * 2.0 + cam.basis.z * 1.5
	)
	c.angular_velocity = Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12))
