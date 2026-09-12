---
name: decay_excess_speed
---

# decay_excess_speed

Pulls horizontal speed down toward `base_run_speed` at `rate`, preserving
direction exactly; at or below base speed it does nothing. This is the
"speed is borrowed, not owned" rule (DESIGN.md §4): excess speed survives
only inside the ramp-grace window or on a wall — everywhere else it decays
through this function.

```gd-sig
decay_excess_speed : (sim: MoveSim, cfg: MovementConfig, rate: float, delta: float) -> void
```

```requires
non-negative rate: rate >= 0.0
```

```ensures
never below base: new horizontal speed >= min(old horizontal speed, cfg.base_run_speed)
direction preserved: velocity.x and velocity.z scale by the same factor; velocity.y untouched
only velocity changes: no other sim field is written
```

```test decays-toward-base
with sim = {velocity: [24.0, -3.0, 0.0]}
(sim, cfg, 10.0, 0.1) => {velocity: [23.0, -3.0, 0.0]}
```

```test at-base-no-op
with sim = {velocity: [12.0, 5.0, 0.0]}
(sim, cfg, 10.0, 0.1) => {velocity: [12.0, 5.0, 0.0]}
```

## Implementation

Scales `velocity.x/z` by `new_speed / old_speed` rather than reconstructing
from a normalized direction — one division, no normalization drift. `rate`
is a parameter (not read from cfg) because ground and air callers used to
pass different rates; today the only caller is air_move with
`cfg.ramp_decay_rate` (ground decay happens inside ground_move's
move_toward instead).
