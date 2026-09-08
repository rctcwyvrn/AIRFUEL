extends Control

## Rotating-prism minimap, drawn directly on the canvas via manual 3D
## projection. Replaces a SubViewport approach that rendered blank on the
## target editor build — _draw has no viewport/world/camera pipeline to
## misbehave. Corridor positions are squashed non-uniformly (length 1:12,
## girth 1:3) so the 880 m corridor reads as a chunky prism, not a sliver.

const MAP_DIV := Vector3(3.0, 3.0, 12.0)
const HALF := Vector3(13.35, 6.7, 36.7)  # corridor half-extents after MAP_DIV
const PITCH := 0.45
const ZOOM := 2.3
const EDGES: Array = [
	[0, 1], [2, 3], [4, 5], [6, 7],
	[0, 2], [1, 3], [4, 6], [5, 7],
	[0, 4], [1, 5], [2, 6], [3, 7],
]

var yaw := 0.0
var track: Node3D  # the local player; assigned by hud.gd


func _process(delta: float) -> void:
	if not visible:
		return
	if is_instance_valid(track):
		# Compass lock: the direction you face projects up-screen
		yaw = lerp_angle(yaw, PI - track.rotation.y, 1.0 - exp(-10.0 * delta))
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var corners: Array[Vector2] = []
	for i in 8:
		corners.append(_project(Vector3(
				HALF.x * (1.0 if i & 1 else -1.0),
				HALF.y * (1.0 if i & 2 else -1.0),
				HALF.z * (1.0 if i & 4 else -1.0)), center))
	# floor face (y = -HALF.y corners: 0,1,5,4) filled grey for orientation
	draw_colored_polygon(PackedVector2Array([
			corners[0], corners[1], corners[5], corners[4]]),
			Color(0.7, 0.72, 0.75, 0.28))
	for e: Array in EDGES:
		draw_line(corners[e[0]], corners[e[1]], Color(1, 0.55, 0.1, 0.55), 1.5)
	for id: int in Net.players:
		var p := Net.players[id] as Node3D
		if not is_instance_valid(p):
			continue
		var col := Color(1, 0.55, 0.1) if p.is_multiplayer_authority() \
				else Color(1, 0.15, 0.15)
		draw_circle(_project(p.global_position / MAP_DIV, center), 5.0, col)


func _project(v: Vector3, center: Vector2) -> Vector2:
	var x := v.x * cos(yaw) + v.z * sin(yaw)
	var z := -v.x * sin(yaw) + v.z * cos(yaw)
	var y := v.y * cos(PITCH) + z * sin(PITCH)
	return center + Vector2(-x, -y) * ZOOM
