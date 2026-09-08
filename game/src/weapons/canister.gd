extends RigidBody3D

## Spent railgun canister (DESIGN.md 8.1 bolt action, 17 feedback beat).

@export var lifetime := 4.0


func _ready() -> void:
	get_tree().create_timer(lifetime).timeout.connect(queue_free)
