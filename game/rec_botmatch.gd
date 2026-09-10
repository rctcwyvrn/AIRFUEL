extends Node

## Bot-vs-bot recording harness, entry scene (see recording-harness/README.md).
## NOT part of the game: record.sh copies this into game/ for the render and
## deletes it afterwards. Boots the persistent setup node, then loads the arena.


func _ready() -> void:
	var setup := Node.new()
	setup.set_script(load("res://rec_botmatch_setup.gd"))
	get_tree().root.add_child.call_deferred(setup)
	get_tree().change_scene_to_file.call_deferred("res://maps/graybox_corridor.tscn")
