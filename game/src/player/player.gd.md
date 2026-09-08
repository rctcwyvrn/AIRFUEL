# player.gd

## Function

The Steps 1+2 player: kinematic movement controller (DESIGN.md §4, §5) plus
the dual railgun arm system (§7, §8.1) — charge freeze/trajectory-lock, aim
crush, staggered dual-rail firing, hitscan damage, canister ejection. No
networking — that's Step 4.

## Interface

- `class_name AirfuelPlayer extends CharacterBody3D`; the scene root of
  `player.tscn`, always in group `"player"`.
- Exports: `config: MovementConfig`, `combat: CombatConfig` (both required,
  never null at runtime), `mouse_sensitivity: float`.
- Signal `shot_fired(side: String, result: String)` — side "L"/"R", result
  "miss"/"body"/"head"/"kill". The HUD connects for hitmarkers.
- Read by the HUD (poll, no signals yet): `fuel`, `ramp_grace_timer`, `config`,
  `horizontal_speed() -> float`, `state_name() -> String`.
- Expected children: `Head` (Node3D, pitch) → `Head/Camera3D` (roll + FOV
  feel); `ArmLeft`/`ArmRight` (`RailArm` nodes). Yaw goes on the body itself.
- HUD-facing reads: `move_locked`, `arm_progress_left/right()`.
- Consumes input actions: `move_forward/back/left/right`, `strafe_down`
  (Q — up was removed; double jump covers it), `jump`, `dash` (Shift),
  `fire_left` (LMB), `fire_right` (RMB), `respawn`, `ui_cancel`.
- `MoveState { GROUNDED, AIRBORNE, WALLRUN }` in `state`.

## Implementation

Per-physics-tick order in `_physics_process` (order is load-bearing):
timers → `move_locked` recompute + `_handle_arms` (charge starts, pending
fires) → per-state move (`_ground_move` / `_air_move` / `_wallrun_move`) →
`_handle_dashes` → terminal-velocity clamps → `move_and_slide()` →
`_update_state` (floor check, wall attach) → `_camera_feel` (speed FOV;
wallrun banks the camera `wallrun_camera_roll_deg` at
`wallrun_camera_roll_speed` and adds `wallrun_fov_bonus`) → respawn check.

**Charge freeze (§7.2)**: `move_locked` is true while either arm
`is_locking()`. Grounded → horizontal velocity zeroed (rooted). Airborne →
ballistic: gravity/ramp decay continue, all steering (wish, Q/E, double jump,
dashes) gated off. Wallrunning → the run *continues* (Lily's call: the wall
is your trajectory) but the dismount jump is ignored; running off the wall
end drops into the airborne lock. While locked, total speed is clamped to `combat.charge_speed_cap`
(charging at high speed instantly bleeds you to 40 — the freeze makes you
slower and more readable, not just steerless). **Aim crush**: mouse
sensitivity ×
`_aim_crush_mult()` = `lerp(1, aim_crush_floor, progress^exponent)` over the
max progress of both arms.

**Firing (§7.1, §8.1)**: `_handle_arms` starts charges on trigger press;
completed charges queue in `pending_arms` (FIFO = press order) and fire no
closer than `min_shot_gap` apart. `_fire_rail` raycasts from the camera
center (`range_max`, mask = player mask OR layer 2 so it hits
movement-transparent targets), reads `hit_zone` meta off the collider for body/head
damage against `TargetDummy`, then spawns the beam from the firing arm's
viewmodel muzzle (`vm.global_transform * (0,0,-0.35)`), kicks that viewmodel
back, spawns a `canister.tscn` rigid body with inherited velocity +
randomized tumble, and emits `shot_fired`.

**Graybox visuals**: `_spawn_beam` builds a thin emissive BoxMesh
(0.05×0.05×length) at the midpoint, oriented with `look_at` (up-vector
fallback for near-vertical shots), alpha+emission tweened to 0 over 0.2s
then freed. `_update_viewmodels` (every tick, after `_camera_feel`) sets
each viewmodel material's `emission_energy_multiplier` to
`arm.progress() * 3.0` — the arm block glows as its charge builds — and
lerps the viewmodel back to its `rest_pos` meta after the fire kick.

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
  Vertical strafe (`_vertical_input`) is Q-down only, fueled, capped at
  `air_strafe_vertical_cap`, airborne only; upward mobility is the double
  jump.
- **Dash is Shift + held direction, camera-aimed** (Lily's scheme, revised
  2026-09-08 from yaw-plane to full camera): WASD components follow the
  camera basis including pitch — W+Shift goes wherever you look; Q adds
  world-down. Bare Shift is inert. Shift+Q with no WASD held fires the §4.4 down dash instead, with its
  own `down_dash_*` tuning and no cooldown (fuel is its limiter); every other
  direction uses `air_dash_impulse`/`air_dash_cost`/`air_dash_cooldown`.
  Double jump is fuel-gated plus a short cooldown (interpretation of §4.5:
  fuel is the constraint, cooldown just prevents hover-spam).
- **Feel assists (Celeste-inspired, all in the Assists config group)**:
  `_apply_glide` runs after `move_and_slide` (except during wallrun) — on a
  glancing hit against a wall-ish surface it restores horizontal speed
  (`glide_speed_retention`, default 90%) along the slide direction, so
  obstacles deflect instead of stopping; impacts steeper than
  `glide_max_impact_angle_deg` from the surface still stop you. **Wall
  coyote**: falling off a wall arms `wall_coyote_timer` — jump within it
  and `_coyote_walljump` applies the full dismount boost (fuel was already
  granted at falloff, so no double-grant). **Ground coyote**: walking off
  an edge (not jumping — gated on `velocity.y <= 1`) leaves the free jump
  available briefly. **Jump buffer**: any jump press is buffered
  `jump_buffer_time`; landing consumes it. Air jump priority: wall coyote →
  ground coyote → fueled double jump.
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
- No charge cancel exists anywhere; a charge always ends in a shot. Dual
  shots are never closer than `combat.min_shot_gap` (verified: same-tick
  charges fire 0.352s apart with the default 0.35 gap).
- `move_locked` must derive only from arm `is_locking()` — freeze from first
  trigger press to last pending shot, never during COOLDOWN.
- Beam meshes always free themselves (tween callback) — a leaked beam per
  shot would accumulate fast.
- Coyote walljump must never grant fuel (falloff already did); jumping
  dismounts must clear `wall_coyote_timer` so boosts can't stack.
- Glide only redirects horizontal speed — it must never add speed
  (`target` is capped by pre-impact speed × retention).
