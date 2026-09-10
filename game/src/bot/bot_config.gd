class_name BotConfig
extends Resource

## Every tuning number for the practice bot (DESIGN.md Appendix A: the bot
## as an always-available practice tool). Edit default_bot.tres — not code.
## The Aim group's turn-rate pair is the bot-only "aim crush": the PLAYER
## mechanic stays cut (Appendix A), but the bot's tracking degrades as its
## own charge builds so charge → tell → dodge stays winnable against it.

@export_group("Brain")
@export var brain_hz := 8.0

@export_group("Aim")
@export var turn_rate_free := 7.0
@export var turn_rate_charged := 1.1
@export var aim_smoothing := 10.0
@export var noise_ease := 6.0
@export var aim_lag := 0.12
@export var aim_noise_deg := 2.0
@export var fire_cone_deg := 3.0
@export var stagger_chance := 0.35

@export_group("Dodge")
@export var reaction_mean := 0.25
@export var reaction_dev := 0.06
@export var reaction_min := 0.15
@export var reaction_max := 0.45
@export var dodge_weight_dash := 0.55
@export var dodge_weight_strafe := 0.3
@export var dodge_weight_none := 0.15
@export var dodge_lead := 0.2
@export var dodge_lead_jitter := 0.08
@export var dodge_probe_range := 6.0

@export_group("Movement")
@export var strafe_hold_min := 0.5
@export var strafe_hold_max := 1.4
@export var preferred_range_min := 25.0
@export var preferred_range_max := 60.0
@export var dual_sword_range_min := 6.0
@export var dual_sword_range_max := 14.0
@export var air_fuel_floor := 80.0
@export var dash_fuel_floor := 100.0
@export var wall_seek_fuel := 120.0
@export var move_dash_chance := 0.3
@export var engage_wall_ride_time := 0.6
@export var double_jump_fall_speed := 3.0

@export_group("Fuel")
@export var refuel_enter := 40.0
@export var refuel_exit := 120.0
@export var refuel_ride_time := 0.8
@export var refuel_probe_range := 60.0
@export var refuel_approach_lead := 20.0
@export var refuel_jump_dist := 4.0

@export_group("Sword")
@export var sword_max_range := 14.0
@export var sword_fuel_reserve := 30.0
@export var sword_aim_cone_deg := 8.0
@export var sword_commit_factor := 1.5
