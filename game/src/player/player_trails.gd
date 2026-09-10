class_name PlayerTrails
extends Node

## Render-side trail cosmetics for one AirfuelPlayer, split out of player.gd
## (1200-line cap): the orange flight-path line and the blue sword-lunge
## ribbon (DESIGN.md 8.2 readability). Pure visuals — nothing here may touch
## simulation. Created by player.gd in _ready as a child node; fully inert on
## the headless server.

var _player: CharacterBody3D
var _trail_node: MeshInstance3D
var _trail_mesh: ImmediateMesh
var _trail_pts: Array[Vector3] = []
var _trail_times: Array[float] = []
var _sword_last := Vector3.ZERO
var _sword_live := false


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_trail_mesh = ImmediateMesh.new()
	_trail_node = MeshInstance3D.new()
	_trail_node.mesh = _trail_mesh
	_trail_node.top_level = true
	var tmat := StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tmat.vertex_color_use_as_albedo = true
	_trail_node.material_override = tmat
	add_child(_trail_node)


func _process(_delta: float) -> void:
	_update_trail_line()
	_update_sword_trail()


## Respawn hook: the flight path must not connect across a teleport.
func clear() -> void:
	_trail_pts.clear()
	_trail_times.clear()


## One long thin orange line tracing the recent flight path: world-space
## line strip over a rolling position history (2 m samples, ~4 s / 150 pt
## cap), alpha fading toward the tail. Replaces the old particle puffs.
func _update_trail_line() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var pos: Vector3 = _player.global_position
	if _trail_pts.is_empty() or _trail_pts[-1].distance_to(pos) > 2.0:
		_trail_pts.append(pos + Vector3.UP * 0.4)
		_trail_times.append(now)
	while not _trail_times.is_empty() and (now - _trail_times[0] > 4.0 or _trail_pts.size() > 150):
		_trail_pts.pop_front()
		_trail_times.pop_front()
	_trail_node.global_transform = Transform3D.IDENTITY
	_trail_mesh.clear_surfaces()
	if _trail_pts.size() < 2:
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var n := _trail_pts.size()
	for i in n:
		var a := float(i) / float(n - 1)
		_trail_mesh.surface_set_color(Color(1.0, 0.55, 0.1, a * 0.8))
		_trail_mesh.surface_add_vertex(_trail_pts[i])
	_trail_mesh.surface_end()


## Sword lunge tell: a strong blue ribbon of emissive segments dropped along
## the lunge path while the blade is live. Works for every role that renders
## — replicas receive sword_active via render rows (player.gd render_state).
func _update_sword_trail() -> void:
	if _player.sword_active <= 0.0:
		_sword_live = false
		return
	var pos: Vector3 = _player.global_position + Vector3.UP * 0.7
	if not _sword_live:
		# Lunge just started: anchor here, first segment next frame. The
		# activation sound rides the same rising edge so local players and
		# replicas alike are audible (§16).
		_sword_live = true
		_sword_last = pos
		PlayerFx.play_slash_sound(_player.get_parent(), pos)
		return
	if pos.distance_to(_sword_last) < 0.4:
		return
	PlayerFx.spawn_sword_trail(_player.get_parent(), _sword_last, pos)
	_sword_last = pos
