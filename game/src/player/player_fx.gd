class_name PlayerFx
extends Object

## Stateless one-shot combat cosmetics (DESIGN.md §17 feedback beats), split
## out of player.gd: the rail beam and the ejected canister. Pure visuals —
## nothing here may affect simulation (prediction replays skip them
## entirely, and the headless server never calls them).

const CANISTER := preload("res://src/weapons/canister.tscn")
const RAIL_SOUND := preload("res://sounds/rail.wav")
const SLASH_SOUND := preload("res://sounds/slash.wav")

## Weapon one-shots sit above the arena BGM (source RMS is ~equal, so the
## boost here + the -10 dB on the map's Bgm node keeps activations on top).
const RAIL_VOLUME_DB := 6.0
const SLASH_VOLUME_DB := 4.0
## §16 "loud, directional": big unit size so shots carry across the arena.
const SOUND_UNIT_SIZE := 20.0


## Railgun activation sound at the muzzle (DESIGN.md §16). Played by the
## shooter's own fire_rail and by Net for an opponent's shot on REPLICAs.
static func play_rail_sound(parent: Node, pos: Vector3) -> void:
	_play_sound_at(parent, RAIL_SOUND, pos, RAIL_VOLUME_DB)


## Sword lunge activation sound (DESIGN.md §16), triggered off the lunge
## rising edge in PlayerTrails so every rendered role (local + replica)
## sounds the same tell that shows the blue ribbon.
static func play_slash_sound(parent: Node, pos: Vector3) -> void:
	_play_sound_at(parent, SLASH_SOUND, pos, SLASH_VOLUME_DB)


## Fire-and-forget positional one-shot; frees itself when done.
static func _play_sound_at(parent: Node, stream: AudioStream, pos: Vector3, db: float) -> void:
	var sp := AudioStreamPlayer3D.new()
	sp.stream = stream
	sp.volume_db = db
	sp.unit_size = SOUND_UNIT_SIZE
	parent.add_child(sp)
	sp.global_position = pos
	sp.finished.connect(sp.queue_free)
	sp.play()


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


## One segment of the sword-lunge trail: fatter, bluer, and longer-lived
## than the rail beam so a lunging player reads at a glance. Segments are
## dropped along the lunge path by player.gd's _update_sword_trail and
## overlap slightly so the ribbon has no gaps.
static func spawn_sword_trail(parent: Node, from: Vector3, to: Vector3) -> void:
	var dir := to - from
	var length := dir.length()
	if length < 0.05:
		return
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.45, 0.45, length + 0.3)
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.25, 0.55, 1.0, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.5, 1.0)
	mat.emission_energy_multiplier = 6.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = (from + to) * 0.5
	var up := Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT
	mi.look_at(to, up)
	var tw := mi.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.45)
	tw.parallel().tween_property(mat, "emission_energy_multiplier", 0.0, 0.45)
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
