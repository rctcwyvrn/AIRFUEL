---
name: wallrun_move
---

# wallrun_move

One WALLRUN-state tick. Re-probes the wall every tick (toward
`-wall_normal` at 1.6× probe distance, falling back to ±0.6 rad rotations)
so the normal tracks curved surfaces. Exits to `dismount(false)` on floor
contact, lost wall, the corner-launch condition, timeout past
`wallrun_max_duration`, or along-wall speed below `min_wallrun_speed`.
While running: wall speed accumulates toward `wallrun_max_speed`, velocity
is laid along the wall tangent with a stick force into the wall, vertical
velocity settles toward zero minus a gentle wallrun gravity, and a jump
press (when not charge-locked) is the jump dismount.

The probe is a capability: `probe.call(dir: Vector3, dist_scale: float) ->
Dictionary` (a raycast hit or `{}`) — the node adapter in real play
(`PlayerMovement.probe_wall_at`), a fake in tests.

```gd-sig
wallrun_move : (sim: MoveSim, cfg: MovementConfig, on_floor: bool, jump: bool, facing: Vector3, probe: Callable, delta: float) -> void
```

```requires
running a wall: sim.state == WALLRUN and sim.wall_normal != ZERO
probe is honest: probe returns {} or a hit with abs(normal.y) <= 0.4
```

```ensures
every exit dismounts: leaving WALLRUN this tick goes through dismount (fuel grant + lockout + coyote rules apply)
normal stays fresh: still WALLRUN implies sim.wall_normal == this tick's probe normal
speed accumulates bounded: still WALLRUN implies sim.wall_speed <= max(old wall speed, cfg.wallrun_max_speed)
```

```test tracks-and-accumulates
with sim = {velocity: [0.0, 0.0, -20.0], wall_normal: [1, 0, 0], wallrun_time: 0.0, state: WALLRUN}
with probe = fake_probe {normal: [1, 0, 0], position: [0.65, 0.0, 0.0]}
(sim, cfg, false, false, [0, 0, -1], probe, 0.1) => {velocity: [-3.0, -0.2, -21.4], wall_speed: 21.4, wallrun_time: 0.1, state: WALLRUN}
```

```test lost-wall-dismounts
with sim = {velocity: [0.0, 0.0, -20.0], wall_normal: [1, 0, 0], wall_speed: 20.0, fuel: 0.0, state: WALLRUN}
with probe = fake_probe {}
(sim, cfg, false, false, [0, 0, -1], probe, 0.1) => {fuel: 19.6, wall_coyote_timer: 0.15, state: AIRBORNE}
```

```test timeout-dismounts
with sim = {velocity: [0.0, 0.0, -20.0], wall_normal: [1, 0, 0], wall_speed: 20.0, wallrun_time: 2.45, fuel: 0.0, state: WALLRUN}
with probe = fake_probe {normal: [1, 0, 0], position: [0.65, 0.0, 0.0]}
(sim, cfg, false, false, [0, 0, -1], probe, 0.1) => {fuel: 19.6, state: AIRBORNE, wallrun_time: 0.0}
```

## Implementation

- **Corner launch**: if the re-probed normal jumps by an angle inside
  `[wallrun_corner_dismount_deg, wallrun_corner_wrap_deg)` (50–80°) in one
  tick AND `velocity.dot(new_normal) > 0` (convex — the surface falls
  away), dismount fires BEFORE the normal is adopted: velocity leaves
  along the old tangent intact instead of folding onto the far face.
  Concave corners and ≥ wrap_deg hairpins still track/wrap — switchbacks
  stay legitimate technique.
- Structural literals (deliberate, not config): probe scale `1.6`,
  fallback rotations `±0.6` rad, vertical settle rate `20.0`.
- The tick integrates in probe → corner → duration → speed-floor → drive
  order; each gate dismounts with the *current* `wall_speed`, which is why
  the timeout test still grants falloff fuel.
