class_name TargetDummy
extends Node3D

## Stationary practice target for roadmap Step 2. Uniform HP (DESIGN.md 9):
## 2 hp, so rail body shots (1 dmg) take two and headshots (2 dmg) kill.
## Dies visibly, then self-respawns so range practice never stalls.

@export var max_hp := 2
@export var respawn_delay := 2.0

@onready var body: StaticBody3D = $Body
@onready var head: StaticBody3D = $Head

var hp := 0


func _ready() -> void:
	hp = max_hp


## Returns true if this hit killed the target.
func take_hit(damage: int) -> bool:
	if hp <= 0:
		return false
	hp -= damage
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE, 0.15).from(Vector3.ONE * 1.2)
	if hp <= 0:
		_die()
		return true
	return false


func _die() -> void:
	visible = false
	body.collision_layer = 0
	head.collision_layer = 0
	get_tree().create_timer(respawn_delay).timeout.connect(_respawn)


func _respawn() -> void:
	hp = max_hp
	visible = true
	body.collision_layer = 2
	head.collision_layer = 2
