class_name KiteWireframe
extends Node3D

## Draws opaque edge beams — a wireframe — along every edge of the sibling
## kite obstacles (CSGPolygon3D nodes tagged `metadata/deflector`): one beam
## per polygon edge on the bottom rim, the top rim, and each vertical
## corner. Runtime-generated so the hand-written tscn stays 24 kite nodes
## instead of ~300 beam boxes. Pure visuals: no collision, nothing gameplay.

@export var beam_thickness := 0.18
@export var beam_color := Color(1.0, 0.55, 0.1)

var _mat: StandardMaterial3D


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = beam_color
	for node: Node in get_parent().get_children():
		if node is CSGPolygon3D and node.has_meta("deflector"):
			_outline(node)


func _outline(kite: CSGPolygon3D) -> void:
	var t := kite.global_transform
	var poly := kite.polygon
	var n := poly.size()
	var bottom: Array[Vector3] = []
	var top: Array[Vector3] = []
	for v: Vector2 in poly:
		# CSGPolygon3D depth-mode extrudes the local-XY polygon along -Z
		bottom.append(t * Vector3(v.x, v.y, 0.0))
		top.append(t * Vector3(v.x, v.y, -kite.depth))
	for i in n:
		var j := (i + 1) % n
		_beam(bottom[i], bottom[j])
		_beam(top[i], top[j])
		_beam(bottom[i], top[i])


func _beam(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.01:
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(beam_thickness, beam_thickness, length + beam_thickness)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = (from + to) * 0.5
	var dir := (to - from).normalized()
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	mi.look_at(to, up)
