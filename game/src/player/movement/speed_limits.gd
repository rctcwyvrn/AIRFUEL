extends Object

## Definition: the end-of-tick velocity clamps — soft overspeed decay above
## terminal velocity, the charge-freeze speed cap, and the hard terminal-fall
## floor. Spec: speed_limits.gd.md.


static func apply_speed_limits(
	sim: MoveSim, cfg: MovementConfig, charge_speed_cap: float, delta: float
) -> void:
	var speed := sim.velocity.length()
	if speed > cfg.terminal_velocity:
		# Soft ceiling: overspeed (sword lunge) decays fast instead of clamping
		sim.velocity *= (
			move_toward(speed, cfg.terminal_velocity, cfg.overspeed_decay * delta) / speed
		)
	if sim.move_locked:
		# Charging bleeds you down to a slower, more readable trajectory
		sim.velocity = sim.velocity.limit_length(charge_speed_cap)
	sim.velocity.y = maxf(sim.velocity.y, -cfg.terminal_fall_speed)
