class_name MovementConfig
extends Resource

## Every movement tuning number from DESIGN.md Appendix B.
## Edit default_tuning.tres (or live in the inspector while running) — not code.

@export_group("Fuel")
@export var fuel_max := 100.0

@export_group("Ground")
@export var base_run_speed := 12.0
@export var ground_accel := 60.0
@export var ground_friction := 45.0
@export var jump_velocity := 9.0

@export_group("Air")
@export var gravity := 14.0
@export var terminal_velocity := 55.0
@export var terminal_fall_speed := 40.0
@export var air_control_accel := 6.0
@export var air_strafe_accel := 25.0
@export var air_strafe_speed_cap := 18.0
@export var air_strafe_vertical_cap := 10.0
@export var air_strafe_cost_per_sec := 6.0
@export var double_jump_cost := 8.0
@export var double_jump_strength := 8.0
@export var double_jump_cooldown := 0.35

@export_group("Dash")
@export var air_dash_cost := 25.0
@export var air_dash_impulse := 18.0
@export var air_dash_cooldown := 0.8
@export var down_dash_cost := 12.0
@export var down_dash_speed := 30.0

@export_group("Wallrun")
@export var wall_probe_distance := 1.3
@export var min_wallrun_speed := 6.0
@export var wallrun_max_duration := 2.5
@export var wallrun_accel := 14.0
@export var wallrun_max_speed := 38.0
@export var wallrun_gravity := 2.0
@export var wall_stick_speed := 3.0
@export var wallrun_camera_roll_deg := 10.0

@export_group("Dismount")
@export var dismount_fuel_per_speed := 1.4
@export var dismount_fuel_max := 60.0
@export var dismount_boost_factor := 0.18
@export var dismount_up_velocity := 6.0
@export var dismount_push_off := 4.0
@export var wall_rearm_time := 0.18

@export_group("Ramp Persistence")
@export var ramp_grace_window := 1.2
@export var ramp_decay_rate := 10.0

@export_group("Misc")
@export var kill_y := -40.0
