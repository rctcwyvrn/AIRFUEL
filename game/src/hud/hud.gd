extends CanvasLayer

@onready var fuel_bar: ProgressBar = $FuelBar
@onready var fuel_label: Label = $FuelLabel
@onready var speed_label: Label = $SpeedLabel
@onready var state_label: Label = $StateLabel

var player: AirfuelPlayer


func _process(_delta: float) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player") as AirfuelPlayer
		if player == null:
			return
	fuel_bar.max_value = player.config.fuel_max
	fuel_bar.value = player.fuel
	fuel_label.text = "AIRFUEL %d" % roundi(player.fuel)
	speed_label.text = "%d m/s" % roundi(player.horizontal_speed())
	var extra := ""
	if player.ramp_grace_timer > 0.0:
		extra = "   RAMP %.1f" % player.ramp_grace_timer
	state_label.text = player.state_name() + extra
