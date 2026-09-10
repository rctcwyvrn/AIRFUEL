# player_movement.gd

## Function

The player's movement layer (DESIGN.md §4, §5), split out of player.gd
2026-09-10: ground/air/wallrun moves, dashes, dismount rewards, wall
probes, the Celeste-style assists (glide, coyote, jump buffer), and the
wish-direction helper. Everything here runs inside the player's
`_simulate()` tick and is part of the deterministic, prediction-replayed
simulation.

## Interface

- `class_name PlayerMovement extends Object` — stateless static functions
  over the player body, the `PlayerState` pattern: params typed
  `CharacterBody3D` (never `AirfuelPlayer` — avoids a class-resolution
  cycle), ALL state lives on the player.
- Called from `player.gd`'s `_simulate()`: `ground_move(p, wish, delta)`,
  `air_move(p, wish, delta)`, `wallrun_move(p, delta)`,
  `handle_dashes(p)`, `apply_glide(p, pre_slide_velocity)`,
  `update_state(p)`, `wish_dir(p) -> Vector3`.
- Internal but public statics (callable, no other callers today):
  `dismount(p, jumped)`, `try_attach_wall(p)`,
  `probe_wall_at(p, dir, dist_scale) -> Dictionary`,
  `air_accelerate(p, wish, accel, cap, delta)`,
  `decay_excess_speed(p, rate, delta)`, `coyote_walljump(p)`.
- Reads/writes only public player state (`velocity`, `fuel` via
  `p._spend`, `state`, wall/coyote/timer fields, `cmd_*`) and
  `p.config`; enum values via `p.MoveState.*` (dynamic lookup — same
  cycle-avoidance).

## Implementation

- **Wall detection is ray-based, not collision-based**, so curved surfaces
  work. Attach: 12 radial horizontal rays from body center
  (`try_attach_wall`), best = nearest hit with a wall-ish normal
  (probes reject `|normal.y| > 0.4`). Maintain: re-probe toward
  `-wall_normal` each tick at 1.6× distance, falling back to ±0.6 rad
  rotations so the normal tracks curvature (`wallrun_move`).
- **Corner launch**: if the re-probed normal jumps by an angle inside
  `[wallrun_corner_dismount_deg, wallrun_corner_wrap_deg)` (50-80°) in
  one tick AND `velocity.dot(new_normal) > 0` (convex — the surface falls
  away), `dismount(false)` fires BEFORE the normal is adopted: velocity
  leaves along the old tangent intact instead of folding onto the far
  face. Concave corners and ≥80° hairpins still track/wrap.
- **Dismount** (`dismount`): fuel grant scales with along-wall speed
  *above* `min_wallrun_speed` (slow wall-hugging ≈ nothing). Jump
  dismounts also get the speed boost + push-off + up-velocity; falling
  off / timing out grants fuel only and arms the wall-coyote window.
- **Ramp persistence**: `dismount` arms `ramp_grace_timer`; while it
  runs, airborne excess speed doesn't decay; after, `decay_excess_speed`
  pulls horizontal speed toward `base_run_speed`. Ground contact bleeds
  excess via `ground_move` instead.
- **Re-attach guard**: for `wall_rearm_time` after dismount, walls whose
  normal is within 25° of `last_wall_normal` are ignored.
- **Air control**: projection-capped acceleration (`air_accelerate` adds
  speed only up to a cap along the wish direction). Free control caps at
  `base_run_speed`; the fueled strafe tier caps at
  `air_strafe_speed_cap` and drains `air_strafe_cost_per_sec` only when
  it can actually add speed.
- **Wallrun exits**: jump and dash leave the wall; Q does NOT — on a wall
  it's a stick-and-slide. A dash off the wall is a full jump-grade
  dismount with the dash impulse stacked on top, arming the longer
  `dash_wall_rearm_time` (anti-pogo). Dismount/coyote boosts are capped
  at `terminal_velocity` (uncapped, the dash-off→re-attach loop
  compounded to hundreds of m/s — shipped once).
- **Dash is Shift + held WASD, camera-aimed** (full camera basis incl.
  pitch); bare Shift is inert. **Q is the §4.4 down dash directly**, own
  `down_dash_*` tuning, no cooldown (fuel is its limiter).
- **Assists**: `apply_glide` runs after `move_and_slide` (except during
  wallrun) — a glancing hit against a wall-ish surface restores
  horizontal speed (`glide_speed_retention`) along the slide direction;
  impacts steeper than `glide_max_impact_angle_deg` still stop you
  UNLESS the collider carries `metadata/deflector = true` (pointed kite
  obstacles — capsule-vs-edge contact normals always read head-on).
  **Wall coyote**: falling off a wall arms `wall_coyote_timer`; jumping
  within it runs `coyote_walljump` — full dismount boost, no fuel
  (already granted at falloff). **Ground coyote** on walked-off edges
  (gated `velocity.y <= 1`). Air jump priority (in `air_move`): wall
  coyote → ground coyote → fueled double jump (fuel + short cooldown).

## Assertions

- Deterministic: no randomness, no wall-clock, no Input reads — the TAS
  ghost and prediction replays re-run these functions, and a pure
  refactor of them was verified bit-identical on the ghost trajectory
  fingerprint (2026-09-10).
- Wallrunning itself never costs fuel; **dismount is the only in-play
  refill** (§5.1) and all spends go through `p._spend`.
- `wall_normal` stays near-horizontal: `probe_wall_at` rejects
  `|normal.y| > 0.4`.
- `wallrun_move` bails to `dismount(false)` on floor contact, lost wall,
  timeout, or speed below `min_wallrun_speed`; `update_state` never
  overrides WALLRUN — only wallrun code exits wallrun.
- Glide only redirects horizontal speed — it must never add speed
  (`target` is capped by pre-impact speed × retention).
- Coyote walljump never grants fuel; jump dismounts clear
  `wall_coyote_timer` so boosts can't stack.
- Known structural literals (mirrored from the pre-split player.gd list):
  the vertical-settle rate `20.0` in `wallrun_move`, the 12-ray count,
  probe rotation `0.6`, the 25° rearm cone. New tunables go in
  `MovementConfig`.
- Params stay typed `CharacterBody3D` and enum access stays dynamic
  (`p.MoveState.*`) — naming `AirfuelPlayer` here creates a
  class-resolution cycle with player.gd.
