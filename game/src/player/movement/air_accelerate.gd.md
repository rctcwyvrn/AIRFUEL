---
name: air_accelerate
---

# air_accelerate

Quake-style projection-capped air acceleration: adds speed along the wish
direction only up to `cap` of along-wish speed, so holding a direction
converges to the cap instead of ballooning, and speed the player already
carries in that direction is respected. Perpendicular velocity is never
touched — this is how air *control* stays separate from air *speed*.

```gd-sig
air_accelerate : (sim: MoveSim, wish: Vector3, accel: float, cap: float, delta: float) -> void
```

```requires
wish is unit: wish is normalized
```

```ensures
along-wish speed capped: velocity.dot(wish) <= max(cap, old velocity.dot(wish))
add is bounded: the velocity change is wish * clamp(cap - old_dot, 0, accel * delta)
only velocity changes: no other sim field is written
```

```test from-rest
with sim = {velocity: [0.0, 0.0, 0.0]}
(sim, [1, 0, 0], 25.0, 18.0, 0.1) => {velocity: [2.5, 0.0, 0.0]}
```

```test clamps-at-cap
with sim = {velocity: [17.0, 0.0, 0.0]}
(sim, [1, 0, 0], 25.0, 18.0, 0.1) => {velocity: [18.0, 0.0, 0.0]}
```

```test past-cap-adds-nothing
with sim = {velocity: [20.0, 0.0, 0.0]}
(sim, [1, 0, 0], 25.0, 18.0, 0.1) => {velocity: [20.0, 0.0, 0.0]}
```

## Implementation

`cur` uses the full 3D dot product, so a wish with a vertical component
(never produced today — `wish_dir` is planar) would count vertical speed
toward the cap. Callers pass the cap: free air control caps at
`base_run_speed`, the fueled strafe tier at `air_strafe_speed_cap`
(see air_move).
