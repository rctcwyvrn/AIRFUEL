extends CanvasLayer

@onready var fuel_bar: ProgressBar = $FuelBar
@onready var fuel_label: Label = $FuelLabel
@onready var speed_label: Label = $SpeedLabel
@onready var state_label: Label = $StateLabel
@onready var charge_l: ProgressBar = $ChargeL
@onready var charge_r: ProgressBar = $ChargeR
@onready var hit_label: Label = $HitLabel
@onready var lock_label: Label = $LockLabel
@onready var controls_hint: Control = $ControlsHint

const KEY_DIM := Color(0.5, 0.5, 0.55, 0.25)
const KEY_LIT := Color(1.0, 0.75, 0.3, 0.9)
const KEY_LAYOUT: Array = [
	["move_forward", "W", 34, 0, 30],
	["move_left", "A", 0, 34, 30],
	["move_back", "S", 34, 34, 30],
	["move_right", "D", 68, 34, 30],
	["strafe_down", "Q", 110, 34, 30],
	["dash", "SHIFT", 0, 68, 64],
	["jump", "SPACE", 68, 68, 72],
	["fire_left", "LMB", 0, 102, 47],
	["fire_right", "RMB", 51, 102, 47],
	["respawn", "T", 110, 102, 30],
]

var player: AirfuelPlayer
var hit_timer := 0.0
var key_rects: Dictionary = {}


func _ready() -> void:
	for k: Array in KEY_LAYOUT:
		if k[0] == "respawn" and Net.active:
			continue  # manual reset is solo-only
		var cr := ColorRect.new()
		cr.position = Vector2(k[2], k[3])
		cr.size = Vector2(k[4], 30)
		cr.color = KEY_DIM
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lb := Label.new()
		lb.text = k[1]
		lb.set_anchors_preset(Control.PRESET_FULL_RECT)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lb.add_theme_font_size_override("font_size", 12)
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cr.add_child(lb)
		controls_hint.add_child(cr)
		key_rects[k[0]] = cr


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = null
		for p: Node in get_tree().get_nodes_in_group("player"):
			if p.is_multiplayer_authority():
				player = p as AirfuelPlayer
				break
		if player == null:
			return
		player.shot_fired.connect(_on_shot_fired)
	fuel_bar.max_value = player.config.fuel_max
	fuel_bar.value = player.fuel
	fuel_label.text = "AIRFUEL %d" % roundi(player.fuel)
	speed_label.text = "%d m/s" % roundi(player.horizontal_speed())
	var extra := ""
	if player.ramp_grace_timer > 0.0:
		extra = "   RAMP %.1f" % player.ramp_grace_timer
	state_label.text = "HP %d   %s%s" % [player.hp, player.state_name(), extra]
	charge_l.value = player.arm_progress_left()
	charge_r.value = player.arm_progress_right()
	lock_label.visible = player.move_locked
	if hit_timer > 0.0:
		hit_timer -= _delta
		if hit_timer <= 0.0:
			hit_label.visible = false
	for action: String in key_rects:
		key_rects[action].color = KEY_LIT if Input.is_action_pressed(action) else KEY_DIM


func _on_shot_fired(_side: String, result: String) -> void:
	match result:
		"kill":
			hit_label.text = "KILL"
			hit_label.modulate = Color(1.0, 0.25, 0.2)
		"head":
			hit_label.text = "HEADSHOT"
			hit_label.modulate = Color(1.0, 0.6, 0.15)
		"body":
			hit_label.text = "HIT"
			hit_label.modulate = Color(1, 1, 1)
		_:
			hit_label.text = ""
	hit_label.visible = hit_label.text != ""
	hit_timer = 0.45
