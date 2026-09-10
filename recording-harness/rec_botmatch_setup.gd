extends Node

## Bot-vs-bot recording harness, persistent half (recording-harness/README.md).
## NOT part of the game: record.sh copies this into game/ for the render and
## deletes it afterwards.
##
## Waits for the corridor to load, replaces the human player with a POV bot,
## spawns an enemy bot, cross-wires them as opponents, and runs the endless
## round loop. The POV bot gets the camera, first-person viewmodels, and the
## HUD; its own body meshes are hidden.
##
## User args (after `--` on the godot command line):
##   --pov <0|1|2>        POV bot loadout index (default 0, rail+rail)
##   --enemy <0|1|2>      enemy bot loadout index (default 2, sword+sword)
##   --countdown <sec>    per-round reset countdown (default 1.0 — short, so
##                        the video isn't mostly frozen 3-2-1)

const PLAYER_SCENE := preload("res://src/player/player.tscn")
const BOT_CONFIG := preload("res://src/bot/default_bot.tres")
const POV_SPAWN := Vector3(0, 2.6, -430)  # the corridor's human spawn
const POV_YAW_DEG := 180.0  # face +Z, down-corridor
const ENEMY_SPAWN := Vector3(0, 2.6, 430)  # far end — matches PracticeSpawner
const ENEMY_YAW_DEG := 0.0  # face -Z, toward the POV spawn

var pov_loadout := 0
var enemy_loadout := 2
var countdown := 1.0

var done := false
var pov_bot: AirfuelPlayer
var enemy_bot: AirfuelPlayer
var _resetting := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		match args[i]:
			"--pov":
				pov_loadout = clampi(int(args[i + 1]), 0, 2)
			"--enemy":
				enemy_loadout = clampi(int(args[i + 1]), 0, 2)
			"--countdown":
				countdown = float(args[i + 1])


func _process(_delta: float) -> void:
	if done:
		return
	var scene := get_tree().current_scene
	if scene == null or not scene.scene_file_path.ends_with("graybox_corridor.tscn"):
		return
	var human: AirfuelPlayer = null
	for p: Node in get_tree().get_nodes_in_group("player"):
		if p is AirfuelPlayer and not p.bot_controlled:
			human = p
	if human == null:
		return
	done = true
	human.queue_free()
	for t: Node in get_tree().get_nodes_in_group("target"):
		t.queue_free()  # duels, not target practice — same as PracticeSpawner
	pov_bot = _spawn_bot(scene, "BotPov", POV_SPAWN, POV_YAW_DEG, pov_loadout)
	enemy_bot = _spawn_bot(scene, "BotEnemy", ENEMY_SPAWN, ENEMY_YAW_DEG, enemy_loadout)
	_ctrl(pov_bot).opponent = enemy_bot
	_ctrl(enemy_bot).opponent = pov_bot
	# POV: camera + first-person arms, own third-person body hidden.
	pov_bot.camera.make_current()
	pov_bot.vm_left.visible = true
	pov_bot.vm_right.visible = true
	pov_bot.get_node("BodyMesh").visible = false
	pov_bot.get_node("Head/HeadMesh").visible = false
	pov_bot.get_node("PuppetArmL").visible = false
	pov_bot.get_node("PuppetArmR").visible = false
	# Adopt the POV bot on the HUD (bypasses the human-only adoption).
	var hud: Node = scene.get_node("HUD")
	hud.player = pov_bot
	print(
		(
			"BOTMATCH: recording %s (POV) vs %s, countdown %.1fs"
			% [pov_bot.loadout_name(), enemy_bot.loadout_name(), countdown]
		)
	)


func _spawn_bot(
	parent: Node, bot_name: String, pos: Vector3, yaw_deg: float, loadout: int
) -> AirfuelPlayer:
	var b := PLAYER_SCENE.instantiate() as AirfuelPlayer
	b.name = bot_name
	b.bot_controlled = true
	b.transform = Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(yaw_deg), 0)), pos)
	parent.add_child(b)
	b.set_loadout(loadout)
	# Harness-local countdown override (dup — never edit the shared
	# default_tuning resource).
	b.config = b.config.duplicate()
	b.config.reset_countdown = countdown
	var c := BotController.new()
	c.bot = BOT_CONFIG
	b.add_child(c)
	b.died.connect(_on_death)
	return b


func _ctrl(b: AirfuelPlayer) -> BotController:
	for c: Node in b.get_children():
		if c is BotController:
			return c
	return null


func _on_death() -> void:
	if _resetting:
		return
	_resetting = true
	_reset_round.call_deferred()  # never teleport bodies mid-physics-tick


func _reset_round() -> void:
	pov_bot._respawn()
	enemy_bot._respawn()
	_resetting = false
	print("BOTMATCH: round reset")
