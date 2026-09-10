class_name PracticeSpawner
extends Node

## Offline practice-duel plumbing (DESIGN.md Appendix A: the bot as an
## always-available practice opponent). Lives in the arena scene and does
## NOTHING unless the main menu queued a duel (BotController.pending_loadout
## >= 0) — so PLAY SOLO and every netplay path are untouched. When queued:
## spawns a bot_controlled AirfuelPlayer with a BotController child at
## bot_spawn, fixes its loadout for the session, and runs the endless
## round loop: any death (or the human's manual T reset) respawns both
## bodies into a fresh 3-2-1 countdown.

const PLAYER_SCENE := preload("res://src/player/player.tscn")
const BOT_CONFIG := preload("res://src/bot/default_bot.tres")

@export var bot_spawn := Vector3(0.0, 2.6, 430.0)
@export var bot_spawn_yaw_deg := 0.0

var human: AirfuelPlayer
var bot_body: AirfuelPlayer
var _resetting := false


func _ready() -> void:
	if Net.active or BotController.pending_loadout < 0:
		return
	var loadout := BotController.pending_loadout
	BotController.pending_loadout = -1  # consumed: a scene reload spawns nothing
	_spawn.call_deferred(loadout)


## Practice duels are duels, not target practice: the solo-mode dummies go.
func _clear_dummies() -> void:
	for t: Node in get_tree().get_nodes_in_group("target"):
		t.queue_free()


func _spawn(loadout: int) -> void:
	for p: Node in get_tree().get_nodes_in_group("player"):
		var ap := p as AirfuelPlayer
		if ap != null and not ap.ghost_controlled and not ap.bot_controlled:
			human = ap
			break
	if human == null:
		push_warning("Airfuel practice: no human player in scene, bot not spawned")
		return
	_clear_dummies()
	bot_body = PLAYER_SCENE.instantiate() as AirfuelPlayer
	bot_body.name = "BotPlayer"
	bot_body.bot_controlled = true
	bot_body.transform = Transform3D(
		Basis.from_euler(Vector3(0.0, deg_to_rad(bot_spawn_yaw_deg), 0.0)), bot_spawn
	)
	get_parent().add_child(bot_body)
	bot_body.set_loadout(loadout)
	var ctrl := BotController.new()
	ctrl.bot = BOT_CONFIG
	bot_body.add_child(ctrl)
	human.died.connect(_on_death)
	bot_body.died.connect(_on_death)
	human.respawned.connect(_on_human_respawned)


func _on_death() -> void:
	if _resetting:
		return
	_resetting = true
	_reset_round.call_deferred()  # never teleport bodies mid-physics-tick


## Both sides reset on every kill — winner included, so each round opens
## from spawn state with the standard countdown, like a netplay round reset.
func _reset_round() -> void:
	human._respawn()
	bot_body._respawn()
	_resetting = false


## The human's manual T reset (or kill_y) restarts the bot too, keeping the
## round symmetric. Guarded so the resets _reset_round itself triggers
## don't recurse.
func _on_human_respawned() -> void:
	if _resetting:
		return
	_resetting = true
	_reset_bot_only.call_deferred()


func _reset_bot_only() -> void:
	bot_body._respawn()
	_resetting = false
