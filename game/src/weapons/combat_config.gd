class_name CombatConfig
extends Resource

## Combat tuning numbers from DESIGN.md Appendix B ("Combat" block).
## Edit default_combat.tres, not code.

@export_group("Railgun")
@export var charge_time := 1.0
@export var cooldown := 1.2
@export var damage_body := 1
@export var damage_head := 2
@export var range_max := 2000.0

@export_group("Aim Crush")
@export var aim_crush_floor := 0.05
@export var aim_crush_exponent := 2.0

@export_group("Dual Rail")
@export var min_shot_gap := 0.35
