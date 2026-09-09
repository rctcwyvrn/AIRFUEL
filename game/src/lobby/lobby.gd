extends Control

## Lobby screen for dedicated-server play: roster with W–L tallies, click an
## idle player to challenge, accept/decline incoming challenges, leave back
## to the menu. Pure view — all state lives in the Net autoload; this scene
## only renders Net's roster cache/signals and sends the three lobby rpcs.

var challenger_id := 0

@onready var roster_box: VBoxContainer = $VBox/RosterBox
@onready var result_label: Label = $VBox/ResultLabel
@onready var challenge_box: HBoxContainer = $VBox/ChallengeBox
@onready var challenge_label: Label = $VBox/ChallengeBox/ChallengeLabel
@onready var status_label: Label = $VBox/StatusLabel


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	Net.roster_updated.connect(_rebuild)
	Net.challenge_received.connect(_on_challenge_received)
	Net.challenge_ended.connect(_on_challenge_ended)
	$VBox/ChallengeBox/AcceptButton.pressed.connect(func() -> void: _reply(true))
	$VBox/ChallengeBox/DeclineButton.pressed.connect(func() -> void: _reply(false))
	$VBox/LeaveButton.pressed.connect(Net.leave_lobby)
	if not Net.last_match_result.is_empty():
		result_label.text = (
			"%s%s"
			% [
				Net.last_match_result.text,
				"  (opponent left)" if Net.last_match_result.forfeit else ""
			]
		)
		result_label.visible = true
	_rebuild(Net.last_roster)


func _rebuild(roster: Array) -> void:
	for child: Node in roster_box.get_children():
		child.queue_free()
	var my_id := multiplayer.get_unique_id()
	for entry: Dictionary in roster:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var name_label := Label.new()
		name_label.text = entry.name + ("  (you)" if entry.id == my_id else "")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var record := Label.new()
		record.text = "%dW %dL" % [entry.wins, entry.losses]
		row.add_child(record)
		if entry.in_match:
			var busy := Label.new()
			busy.text = "IN MATCH"
			busy.modulate = Color(1.0, 0.55, 0.1)
			row.add_child(busy)
		elif entry.id != my_id:
			var btn := Button.new()
			btn.text = "CHALLENGE"
			btn.pressed.connect(func() -> void: _challenge(entry.id, entry.name))
			row.add_child(btn)
		roster_box.add_child(row)


func _challenge(target_id: int, target_name: String) -> void:
	Net.request_challenge.rpc_id(1, target_id)
	status_label.text = "challenging %s..." % target_name
	status_label.visible = true


func _on_challenge_received(from_id: int, from_name: String) -> void:
	challenger_id = from_id
	challenge_label.text = "%s challenges you!" % from_name
	challenge_box.visible = true


func _reply(accept: bool) -> void:
	if challenger_id != 0:
		Net.challenge_reply.rpc_id(1, challenger_id, accept)
	challenger_id = 0
	challenge_box.visible = false


## Fires on the challenger when their challenge dies (declined / timeout /
## target unavailable) and on the target when it expires ("withdrawn").
func _on_challenge_ended(reason: String) -> void:
	match reason:
		"withdrawn":
			challenger_id = 0
			challenge_box.visible = false
		"declined":
			status_label.text = "challenge declined"
		"timeout":
			status_label.text = "no answer"
		_:
			status_label.text = "player unavailable"
	status_label.visible = reason != "withdrawn"
