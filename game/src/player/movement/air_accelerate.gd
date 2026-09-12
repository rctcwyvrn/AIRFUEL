extends Object

## Definition: Quake-style air acceleration — add along-wish speed only up to
## a cap, so holding a direction converges instead of ballooning. Spec:
## air_accelerate.gd.md.


static func air_accelerate(
	sim: MoveSim, wish: Vector3, accel: float, cap: float, delta: float
) -> void:
	var cur: float = sim.velocity.dot(wish)
	var add := clampf(cap - cur, 0.0, accel * delta)
	sim.velocity += wish * add
