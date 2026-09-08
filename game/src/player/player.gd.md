# player.gd

## Function

The Step 1 kinematic character controller (DESIGN.md §4, §5, §24). Implements
the entire movement economy: wallrun as the only in-play fuel refill, rewards
on dismount, ramp persistence across gaps, fuel-costed air abilities, terminal
velocity. No weapons, no networking — those are later roadmap steps.

## Interface

- `class_name AirfuelPlayer extends CharacterBody3D`; the scene root of
  `player.tscn`, always in group `"player"`.
- Exports: `config: MovementConfig` (required, never null at runtime),
  `mouse_sensitivity: float`.
- Read by the HUD (poll, no signals yet): `fuel`, `ramp_grace_timer`, `config`,
  `horizontal_speed() -> float`, `state_name() -> String`.
- Expected children: `Head` (Node3D, pitch) → `Head/Camera3D` (roll + FOV feel).
  Yaw goes on the body itself.
- Consumes input actions: `move_forward/back/left/right`, `jump`, `dash`,
  `down_dash`, `respawn`, `ui_cancel` (mouse release toggle).
- `MoveState { GROUNDED, AIRBORNE, WALLRUN }` in `state`.

## Implementation

Per-physics-tick order in `_physics_process` (order is load-bearing):
timers → per-state move (`_ground_move` / `_air_move` / `_wallrun_move`) →
`_handle_dashes` → terminal-velocity clamps → `move_and_slide()` →
`_update_state` (floor check, wall attach) → `_camera_feel` → respawn check.

- **Wall detection is ray-based, not collision-based**, so curved surfaces
  (cylinders) work. Attach: 12 radial horizontal rays from body center
  (`_try_attach_wall`), best = nearest hit with a wall-ish normal. Maintain:
  re-probe toward `-wall_normal` each tick at 1.6× distance, falling back to
  ±0.6 rad rotations so the normal tracks curvature (`_wallrun_move`).
- **Dismount** (`_dismount`): fuel grant scales with along-wall speed *above*
  `min_wallrun_speed` (slow wall-hugging ≈ nothing). Jump dismounts also get
  the speed boost + push-off + up-velocity; falling off / timing out grants
  fuel only. This is an interpretation of §4.2 — deliberate chaining pays.
- **Ramp persistence**: `_dismount` arms `ramp_grace_timer`; while it runs,
  airborne excess speed doesn't decay. After it expires, `_decay_excess_speed`
  pulls horizontal speed toward `base_run_speed`. Ground contact bleeds excess
  via `_ground_move` instead.
- **Re-attach guard**: for `wall_rearm_time` after dismount, walls whose normal
  is within 25° of `last_wall_normal` are ignored — blocks same-wall re-grab
  without slowing transfer to the *next* wall.
- **Air control**: projection-capped acceleration (`_air_accelerate` adds speed
  only up to a cap along the wish direction). Free control caps at
  `base_run_speed`; the fueled strafe tier caps at `air_strafe_speed_cap` and
  drains `air_strafe_cost_per_sec` only when it can actually add speed.
- Dash aim (`_aim_dir`) is camera-relative including pitch; empty input = camera
  forward. Double jump is fuel-gated plus a short cooldown (interpretation of
  §4.5: fuel is the constraint, cooldown just prevents hover-spam).
- Respawn on `respawn` action or falling below `config.kill_y`.

## Assertions

- `fuel` stays in `[0, config.fuel_max]`; all spends go through `_spend`,
  which is all-or-nothing (never partial-drains below the cost).
- Wallrunning itself never costs fuel; **dismount is the only in-play refill**
  (DESIGN.md §5.1 — do not add refills on kill, death, or pickup).
- `wall_normal` is always near-horizontal: probes reject `|normal.y| > 0.4`.
- `state == WALLRUN` implies not on floor; `_wallrun_move` bails to
  `_dismount(false)` on floor contact, lost wall, timeout, or speed below
  `min_wallrun_speed`.
- After the clamp step, `velocity.length() <= terminal_velocity` and
  `velocity.y >= -terminal_fall_speed` every tick.
- No gameplay literals: any new tunable must be a `MovementConfig` field.
  (Current known exceptions to fix if touched: the vertical-settle rate `20.0`
  in `_wallrun_move`, camera-feel lerp rates and FOV factor, the 12-ray count,
  probe rotation `0.6`, and the 25° rearm cone.)
- `_update_state` never overrides WALLRUN — only wallrun code exits wallrun.
