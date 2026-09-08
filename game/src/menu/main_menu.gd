extends Control

## Entry menu: solo, host LAN, or join LAN. Networking itself lives in the
## Net autoload — this scene only collects the choice.

const ARENA := "res://maps/graybox_corridor.tscn"
const PARKOUR := "res://maps/parkour_track.tscn"

@onready var ip_edit: LineEdit = $VBox/JoinRow/IpEdit


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	$VBox/SoloButton.pressed.connect(
			func() -> void: get_tree().change_scene_to_file(ARENA))
	$VBox/ParkourButton.pressed.connect(
			func() -> void: get_tree().change_scene_to_file(PARKOUR))
	$VBox/HostButton.pressed.connect(func() -> void: Net.host())
	$VBox/JoinRow/JoinButton.pressed.connect(_join)
	ip_edit.text_submitted.connect(func(_text: String) -> void: _join())


func _join() -> void:
	var ip := ip_edit.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	Net.join(ip)
