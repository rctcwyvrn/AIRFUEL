class_name FinishZone
extends Area3D

## Touch volume at a track's finish wall: stops the run timer (and any
## active TAS recording) for the local human player. Ghosts and remote
## puppets don't finish races.


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body is AirfuelPlayer and body.is_multiplayer_authority() \
			and not body.ghost_controlled:
		body.finish_run()
