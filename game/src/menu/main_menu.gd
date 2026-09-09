extends Control

## Entry menu: solo, host LAN, join LAN, or join a dedicated lobby server.
## Networking itself lives in the Net autoload — this scene only collects
## the choice (and remembers the last username/server in user://).

const ARENA := "res://maps/graybox_corridor.tscn"
const PARKOUR := "res://maps/parkour_track.tscn"
const SETTINGS := "user://settings.cfg"

const STATUS_COLOR := Color(0.55, 0.58, 0.63)
const ERROR_COLOR := Color(1.0, 0.3, 0.25)

@onready var ip_edit: LineEdit = $VBox/JoinRow/IpEdit
@onready var name_edit: LineEdit = $VBox/ServerRow/NameEdit
@onready var server_ip_edit: LineEdit = $VBox/ServerRow/ServerIpEdit
@onready var error_label: Label = $VBox/ErrorLabel


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	Net.net_error.connect(_show_error)
	if Net.last_error != "":
		# A failure that landed while another scene was current (server
		# dropped mid-lobby/mid-match) surfaces here on return.
		_show_error(Net.last_error)
	$VBox/SoloButton.pressed.connect(
			func() -> void: get_tree().change_scene_to_file(ARENA))
	$VBox/ParkourButton.pressed.connect(
			func() -> void: get_tree().change_scene_to_file(PARKOUR))
	$VBox/HostButton.pressed.connect(func() -> void: Net.host())
	$VBox/JoinRow/JoinButton.pressed.connect(_join)
	ip_edit.text_submitted.connect(func(_text: String) -> void: _join())
	$VBox/ServerRow/JoinServerButton.pressed.connect(_join_server)
	server_ip_edit.text_submitted.connect(func(_text: String) -> void: _join_server())
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) == OK:
		name_edit.text = cf.get_value("lobby", "name", "")
		server_ip_edit.text = cf.get_value("lobby", "ip", "")


func _join() -> void:
	var ip := ip_edit.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	_show_status("connecting to %s..." % ip)
	Net.join(ip)


func _join_server() -> void:
	var username := name_edit.text.strip_edges()
	if username.is_empty():
		username = "player"
	var ip := server_ip_edit.text.strip_edges()
	if ip.is_empty():
		ip = Net.DEFAULT_SERVER
	var cf := ConfigFile.new()
	cf.set_value("lobby", "name", username)
	cf.set_value("lobby", "ip", ip)
	cf.save(SETTINGS)
	_show_status("connecting to %s..." % ip)
	Net.join_lobby(ip, username)


func _show_status(message: String) -> void:
	error_label.add_theme_color_override("font_color", STATUS_COLOR)
	error_label.text = message
	error_label.visible = true


func _show_error(message: String) -> void:
	Net.last_error = ""  # consumed; don't re-show on the next menu visit
	error_label.add_theme_color_override("font_color", ERROR_COLOR)
	error_label.text = message
	error_label.visible = true
