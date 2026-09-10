class_name RailArm
extends Node

## One arm mount running the railgun charge cycle (DESIGN.md 7, 8.1).
## A charge cannot be held or cancelled: it auto-completes into PENDING and
## emits charge_complete. The player fires the actual shot (min-gap sequencing
## between the two arms lives in the player, 7.1) and calls on_fired().

signal charge_complete

enum ArmState { IDLE, CHARGING, PENDING, COOLDOWN }

@export var config: CombatConfig

var state := ArmState.IDLE
var charge := 0.0
var cooldown := 0.0


## Advances the charge cycle by one tick. Called by the owning player from
## inside its simulation step (NOT self-driven _physics_process) so the whole
## player tick is one re-runnable unit for client prediction replay.
func step(delta: float) -> void:
	match state:
		ArmState.CHARGING:
			charge += delta
			if charge >= config.charge_time:
				state = ArmState.PENDING
				charge_complete.emit()
		ArmState.COOLDOWN:
			cooldown -= delta
			if cooldown <= 0.0:
				state = ArmState.IDLE


## Hard reset (loadout swap): drops any charge/cooldown.
func reset() -> void:
	state = ArmState.IDLE
	charge = 0.0
	cooldown = 0.0


func try_charge() -> bool:
	if state != ArmState.IDLE:
		return false
	state = ArmState.CHARGING
	charge = 0.0
	return true


func on_fired() -> void:
	state = ArmState.COOLDOWN
	cooldown = config.cooldown
	charge = 0.0


func progress() -> float:
	match state:
		ArmState.CHARGING:
			return charge / config.charge_time
		ArmState.PENDING:
			return 1.0
		_:
			return 0.0


## True while this arm imposes the movement freeze: from trigger press until
## its shot has actually fired (charging OR waiting out the dual-rail gap).
func is_locking() -> bool:
	return state == ArmState.CHARGING or state == ArmState.PENDING
