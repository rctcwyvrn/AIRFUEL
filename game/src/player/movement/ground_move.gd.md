---
name: ground_move
---

# ground_move

One GROUNDED-state tick. While charge-frozen, horizontal velocity is zeroed
outright (charging on the ground roots you, DESIGN.md §7.2) and only gravity
integrates. Otherwise: with no wish, friction pulls horizontal speed toward
rest; with a wish, speed above base run bleeds off at friction rate (the
ground is not where speed lives — walls and ramp grace are) and the
horizontal velocity turns toward `wish * speed` at ground acceleration.
Gravity always applies, and a buffered jump fires at the end, consuming the
buffer and setting vertical velocity to exactly `jump_velocity`.

```gd-sig
ground_move : (sim: MoveSim, cfg: MovementConfig, wish: Vector3, delta: float) -> void
```

```requires
wish is planar unit or zero: wish == ZERO or (wish.y == 0.0 and wish is normalized)
```

```ensures
gravity always integrates: sim.velocity.y decreases by cfg.gravity * delta unless the buffered jump fired
buffered jump is exact: if it fired, sim.velocity.y == cfg.jump_velocity and sim.jump_buffer_timer == 0.0
locked means rooted: sim.move_locked implies sim.velocity.x == 0.0 and sim.velocity.z == 0.0
only velocity and the jump buffer change: no other sim field is written
```

```test locked-roots
with sim = {velocity: [5.0, 3.0, 5.0], move_locked: true}
(sim, cfg, [0, 0, -1], 0.1) => {velocity: [0.0, 1.6, 0.0]}
```

```test friction-at-rest-wish
with sim = {velocity: [10.0, 0.0, 0.0]}
(sim, cfg, [0, 0, 0], 0.1) => {velocity: [5.5, -1.4, 0.0]}
```

```test buffered-jump-fires
with sim = {velocity: [0.0, 0.0, 0.0], jump_buffer_timer: 0.05}
(sim, cfg, [0, 0, 0], 0.1) => {velocity: [0.0, 9.0, 0.0], jump_buffer_timer: 0.0}
```

## Implementation

The with-wish branch computes `speed = maxf(base_run_speed,
move_toward(current, base_run_speed, friction * delta))` *first*, then turns
toward `wish * speed` at `ground_accel` — so overspeed decays at friction
rate while the direction change happens at accel rate, independently. The
buffered jump deliberately runs after gravity so the jump tick leaves
exactly `jump_velocity`, not `jump_velocity - gravity * delta`.
