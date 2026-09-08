extends CanvasLayer

@onready var fuel_bar: ProgressBar = $FuelBar
@onready var fuel_label: Label = $FuelLabel
@onready var speed_label: Label = $SpeedLabel
@onready var state_label: Label = $StateLabel
@onready var charge_l: ProgressBar = $ChargeL
@onready var charge_r: ProgressBar = $ChargeR
@onready var hit_label: Label = $HitLabel
@onready var lock_label: Label = $LockLabel

var player: AirfuelPlayer
var hit_timer := 0.0


func _process(_delta: float) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player") as AirfuelPlayer
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
	state_label.text = player.state_name() + extra
	charge_l.value = player.arm_progress_left()
	charge_r.value = player.arm_progress_right()
	lock_label.visible = player.move_locked
	if hit_timer > 0.0:
		hit_timer -= _delta
		if hit_timer <= 0.0:
			hit_label.visible = false


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
