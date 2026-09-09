class_name KillZone
extends Area3D

## Instant-reset volume: sits where a floorless section's floor would be
## (a few meters down). Falling through triggers the respawn + countdown
## immediately instead of a long drop to the global kill_y.


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body is AirfuelPlayer and body.is_multiplayer_authority():
		body._respawn()
