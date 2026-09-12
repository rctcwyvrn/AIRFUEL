extends Object

## Definition: horizontal overspeed decay toward base run speed at a given
## rate, direction preserved. Spec: decay_excess_speed.gd.md.


static func decay_excess_speed(
	sim: MoveSim, cfg: MovementConfig, rate: float, delta: float
) -> void:
	var h := Vector3(sim.velocity.x, 0.0, sim.velocity.z)
	var hs := h.length()
	if hs <= cfg.base_run_speed:
		return
	var ns := move_toward(hs, cfg.base_run_speed, rate * delta)
	sim.velocity.x *= ns / hs
	sim.velocity.z *= ns / hs
