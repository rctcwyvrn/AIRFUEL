extends Node

## Headless trajectory-fingerprint harness: replays the checked-in parkour
## TAS tape through the real movement sim and hashes the ghost's full state
## every tick. Two runs on the same machine/build must print the same
## SHA-256 — the regression gate for "a movement refactor changed nothing"
## (DESIGN.md §20.2 used this method ad hoc; this makes it a tool).
## Run: godot4 --headless --path game res://tools/fingerprint.tscn
## Baseline: game/tas/parkour.fingerprint (same-machine comparisons only —
## float codegen may differ across machines/builds).

const TRACK := "res://maps/parkour_track.tscn"
const STARTUP_GRACE_TICKS := 600  # tape must start feeding within 5 s

var _ghost: CharacterBody3D
var _tas: TasGhostController
var _ctx := HashingContext.new()
var _captured := 0
var _idle_ticks := 0


func _ready() -> void:
	# Capture AFTER every body's physics tick (TasController writes cmds at
	# -1, bodies simulate at 0).
	process_physics_priority = 100
	var track: Node = (load(TRACK) as PackedScene).instantiate()
	add_child(track)
	_ghost = track.get_node("GhostRunner") as CharacterBody3D
	_tas = track.get_node("GhostRunner/TasController") as TasGhostController
	_ctx.start(HashingContext.HASH_SHA256)


func _physics_process(_delta: float) -> void:
	if _tas.tape.is_empty() or _tas.tick == _captured:
		# Tape not loaded yet, or holding on the spawn countdown.
		_idle_ticks += 1
		if _idle_ticks > STARTUP_GRACE_TICKS:
			push_error("fingerprint: tape never started (missing/empty tape?)")
			get_tree().quit(1)
		return
	_idle_ticks = 0
	_captured = _tas.tick
	_ctx.update(PlayerState.capture(_ghost).to_byte_array())
	if _captured >= _tas.tape.size():
		print("fingerprint sha256=%s ticks=%d" % [_ctx.finish().hex_encode(), _captured])
		get_tree().quit()
