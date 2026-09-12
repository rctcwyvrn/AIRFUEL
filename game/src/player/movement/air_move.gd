extends Object

## Definition: one AIRBORNE-state tick — gravity, free air control plus the
## fueled strafe layer, ramp-grace bookkeeping, and the buffered-jump ladder
## (wall coyote > ground coyote > double jump). Spec: air_move.gd.md.

const AirAccelerate := preload("air_accelerate.gd")
const CoyoteWalljump := preload("coyote_walljump.gd")
const DecayExcessSpeed := preload("decay_excess_speed.gd")
const SpendFuel := preload("spend_fuel.gd")


static func air_move(
	sim: MoveSim, cfg: MovementConfig, wish: Vector3, jump: bool, facing: Vector3, delta: float
) -> void:
	sim.velocity.y -= cfg.gravity * delta

	if wish != Vector3.ZERO:
		AirAccelerate.air_accelerate(sim, wish, cfg.air_control_accel, cfg.base_run_speed, delta)
		if (
			sim.velocity.dot(wish) < cfg.air_strafe_speed_cap
			and SpendFuel.spend_fuel(sim, cfg.air_strafe_cost_per_sec * delta)
		):
			AirAccelerate.air_accelerate(
				sim, wish, cfg.air_strafe_accel, cfg.air_strafe_speed_cap, delta
			)

	if sim.ramp_grace_timer > 0.0:
		sim.ramp_grace_timer -= delta
	else:
		DecayExcessSpeed.decay_excess_speed(sim, cfg, cfg.ramp_decay_rate, delta)

	if not sim.move_locked and jump:
		sim.jump_buffer_timer = 0.0
		if sim.wall_coyote_timer > 0.0:
			CoyoteWalljump.coyote_walljump(sim, cfg, facing)
		elif sim.ground_coyote_timer > 0.0:
			sim.ground_coyote_timer = 0.0
			sim.velocity.y = cfg.jump_velocity
		elif sim.double_jump_timer == 0.0 and SpendFuel.spend_fuel(sim, cfg.double_jump_cost):
			sim.velocity.y = maxf(sim.velocity.y, cfg.double_jump_strength)
			sim.double_jump_timer = cfg.double_jump_cooldown
