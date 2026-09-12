# player_movement.gd

## Function

The player's movement layer (DESIGN.md §4, §5) — since the Trellis-style
pilot (2026-09-12), a **module facade**: every mechanic lives in a
per-definition file under `movement/` (one pure static function + private
helpers over `MoveSim` data, each with its own `.tr`-style spec doc), and
this file delegates to them with the pre-pilot signatures so callers are
unchanged. It is also the movement layer's **node boundary**: the only
movement code allowed to touch node state.

## Interface

- `class_name PlayerMovement extends Object` — stateless static facade,
  params typed `CharacterBody3D` (never `AirfuelPlayer` — class-resolution
  cycle), reading `p.sim` / `p.config` / `p.combat` / `p.cmd_*` and node
  state, delegating to the `movement/*.gd` definitions.
- Called from `player.gd`'s `_simulate()`: `ground_move(p, wish, delta)`,
  `air_move(p, wish, delta)`, `wallrun_move(p, delta)`,
  `handle_dashes(p)`, `apply_speed_limits(p, delta)`,
  `apply_glide(p, pre_slide_velocity)`, `update_state(p)`,
  `wish_dir(p) -> Vector3`.
- Called from elsewhere: `dismount(p, jumped)` (PlayerCombat's wall
  lunge), `spend_fuel(p, amount) -> bool` (the body's `_spend`).
- `probe_wall_at(p, dir, dist_scale) -> Dictionary` — the wall-probe
  **capability's node-bound implementation** (world raycast from body
  center, filtered by `is_wall_normal`); `_probe_of(p)` binds it into the
  `probe: Callable` the wallrun/attach definitions take.
- `const WALL_NORMAL_MAX_Y := 0.4` + `is_wall_normal(n) -> bool` — the
  shared wall-ish predicate (accepts `|n.y| <= 0.4`); also used by
  `bot_controller.gd`'s own probes so the threshold can't drift.
- One `const <Name>Def := preload("movement/<name>.gd")` per definition —
  the module's import list.

## Implementation

- Each wrapper extracts plain data for its definition: `-p.global_transform
  .basis.z` as `facing`, the camera basis for dashes, `p.is_on_floor()`,
  `p.global_position`, and (for apply_glide) the tick's slide collisions
  flattened to `{normal, deflector}` rows. `apply_speed_limits` passes
  `p.combat.charge_speed_cap` as a float so definitions depend only on
  `MovementConfig`.
- Behavior parity with the pre-pilot monolith was verified bit-identical
  on the TAS trajectory fingerprint (`tools/fingerprint.tscn`,
  `tas/parkour.fingerprint`) and on a 200 ms fake-lag autoduel soak
  (2026-09-12).
- The old monolith's mechanics documentation now lives in the
  per-definition spec docs (`movement/<name>.gd.md`) — corner launch in
  wallrun_move.gd.md, re-attach guard in try_attach_wall.gd.md, air
  control in air_move.gd.md / air_accelerate.gd.md, dismount rewards in
  dismount.gd.md, assists in apply_glide.gd.md / coyote_walljump.gd.md /
  update_state.gd.md.

## Assertions

- Deterministic: no randomness, no wall-clock, no Input reads — prediction
  replays and TAS ghosts re-run everything here; the trajectory
  fingerprint must not move (gate: `tools/fingerprint.tscn` vs
  `tas/parkour.fingerprint`).
- This facade and `probe_wall_at` are the ONLY movement code that touches
  node state; definition files under `movement/` must stay pure over
  (`MoveSim`, `MovementConfig`, plain args, the probe Callable).
- Wallrunning itself never costs fuel; dismount is the only in-play
  refill (§5.1); every spend goes through the spend_fuel definition.
- Public signatures here keep the pre-pilot shapes (`p`-first) — callers
  and the sword-lunge dismount contract in PlayerCombat rely on them.
- `wall_normal` stays near-horizontal: `probe_wall_at` filters through
  `is_wall_normal` (`WALL_NORMAL_MAX_Y = 0.4`), and the bot's probes call
  the same predicate. The one intentional non-user: `apply_glide.gd`
  keeps its strict-`<` literal (a pure definition must not reach back
  into the facade, and its comparison direction differs at exactly 0.4).
