# bot_controller.gd

## Function

The practice-opponent AI (DESIGN.md Appendix A: a bot as an
always-available *practice* tool — Appendix A forbids re-proposing it as
the Step 3 validity test; LAN 1v1s remain the playtest instrument).
Drives a real `AirfuelPlayer` (its parent, spawned with
`bot_controlled = true` by `PracticeSpawner`) through the actual
movement/combat physics by writing its `cmd_*` inputs each tick, exactly
like the TAS ghost — fuel, cooldowns, and gravity are all real. Two
layers, the §19.3 intent-level shape: a slow brain (`brain_hz`, ~8 Hz)
switches intents and rolls dice; the per-tick actuator steers, aims,
dodges, and pulls triggers.

**The bot-only aim crush**: the player mechanic stays cut (Appendix A —
it felt bad to a human shooter), but this bot's tracking rate degrades
from `turn_rate_free` to `turn_rate_charged` as its own charge builds, so
a terminal-window dash outruns its aim exactly when a shot is about to
land — charge → tell → dodge stays winnable against it.

## Interface

- `class_name BotController extends Node`, child of the bot's
  `AirfuelPlayer`; `process_physics_priority = -1` (cmds written BEFORE
  the body's tick). All tuning via `bot: BotConfig` export.
- **`static var pending_loadout := -1`** — the menu → `PracticeSpawner`
  handoff: `main_menu.gd` writes the chosen AI loadout index (0-2),
  the spawner consumes it (resets to -1) on arena load. -1 = no duel.
- Connects to the parent's `respawned` signal (clears all transient AI
  state so rounds start identical).
- Reads from the opponent only what a human perceives: `global_position`
  / `camera.global_position` (staleness via `aim_lag`), `arm_types` +
  `display_arm_progress(i)` (charge tell — globally warned, §15.2),
  `sim.move_locked` (the visible charge freeze), `horizontal_speed()`,
  `combat.charge_time`. Never the opponent's `cmd_*` or fuel.
- Own-body movement reads go through the body's `sim` (`MoveSim`, since
  the Trellis-style pilot): `sim.fuel`, `sim.state` (vs
  `MoveSim.MoveState.*`), `sim.wallrun_time`, `sim.double_jump_timer`,
  `sim.dash_cooldown_timer`, `sim.move_locked`.

## Implementation

- **Per tick** (`_physics_process`): clear all cmds (so every `true` is a
  one-tick pulse — the body treats fire/jump/dash as just-pressed) → hold
  during the reset countdown → sample opponent position into the aim ring
  buffer → detect new enemy charges → maybe think → then per intent:
  ENGAGE aims/orbits/fights, REFUEL runs a wall. Dodge execution runs
  after movement (it overrides `cmd_move` on the dash tick) and before
  `_combat` (which skips a tick that dashed).
- **Think** (`brain_hz`): rolls `want_stagger`, `want_jump`, re-rolls the
  Gaussian aim-noise offsets; switches ENGAGE ↔ REFUEL on the fuel
  thresholds; re-picks the refuel wall while approaching.
- **Aim**: smoothed yaw/pitch toward the *oldest* buffered opponent
  position (`aim_lag`) — proportional (exponential, `aim_smoothing`)
  approach clamped by the turn-rate cap, so big swings run at the cap
  and arrivals decelerate instead of snapping (Lily's call 2026-09-10).
  Noise offsets ease (`noise_ease`) toward per-think re-rolled targets
  rather than jumping, and are **scaled by the opponent's speed relative
  to `base_run_speed`** — a stationary target dies, a dashing one
  survives (load-bearing: flat noise left the bot unable to finish
  stationary targets in headless tests). The rate cap lerps
  free → charged with the bot's own max rail progress (the aim crush).
- **Dodge pipeline** (Lily's spec): each enemy rail charge is an
  INDEPENDENT event per arm — detect (progress 0 → >0; no LOS needed,
  §15.2 warns every charge) → react after clamped-Gaussian
  `reaction_mean/dev/min/max` → roll once among dash / strafe-juke /
  nothing (`dodge_weight_*`) → a dash executes at charge-end minus
  `dodge_lead`±jitter (headless-verified landing at ~0.75 progress), a
  juke just flips `strafe_dir`. A rolled dash silently degrades to the
  juke when `move_locked`, dash cooldown, or fuel forbids it —
  mechanical scarcity, distinct from the deliberate no-dodge roll, and
  (with per-arm independence) the reason staggered dual-rail beats the
  bot organically. Sideways dashes are wall-checked (`dodge_probe_range`)
  and flip sides if blocked.
- **Engage movement**: held strafes flipped on `strafe_hold_*` timers
  (never per-tick jitter), advance/retreat at the band edges
  (`preferred_range_*`; `dual_sword_range_*` when both arms are swords),
  plus **air hunger** (`_air_habits`, 2026-09-10, Lily's call — the bots
  live in the air): hop off every floor contact, double-jump on fading
  arcs while fuel > `air_fuel_floor`, ride an engaged wall
  `engage_wall_ride_time` then jump off for the dismount grant, and
  spend surplus fuel (> `dash_fuel_floor`) on per-think movement dashes.
  Dodging keeps priority on the shared dash cooldown: no movement dash
  while an enemy charge is up or a dodge dash is owed. **Fuel management
  is wallrun-first** (Lily's call): below `wall_seek_fuel` the strafe
  side (`_pick_strafe_dir`) points at the nearest side wall (world-only
  raycasts both ways) so the orbit drifts into auto-attach and the
  ride/dismount habit farms the §5.1 grant mid-fight — the REFUEL
  intent stays the last resort.
- **Combat**: no arm commits on a dash tick or without LOS (world-only
  raycast, mask 1). Rails charge when aim error < `fire_cone_deg`, the
  arm is IDLE, and no dodge dash is owed (charging would freeze the bot
  through its own dodge window); the second rail staggers only on
  `want_stagger`. **Sword (Lily's gates)**: kill lunge needs the hard
  range gate (`sword_max_range`) AND a punish window (opponent
  `move_locked`, or already inside `sword_hit_range ×
  sword_commit_factor`), plus cooldown/fuel-reserve/aim-cone; dual
  sword's arm 0 may also lunge as a pure gap-closer beyond
  `dual_sword_range_max` (that kit's §8.3 identity) — a rail+sword bot
  never lunges as traversal.
- **Refuel** (fills the gap ghost.gd.md flagged as "Step 3 bot
  territory"): below `refuel_enter`, probe 8 horizontal rays for the
  nearest wall, steer toward a point `refuel_approach_lead` along it,
  jump to attach within `refuel_jump_dist`, ride `refuel_ride_time`,
  jump-dismount for the §5.1 fuel grant; back to ENGAGE at
  `refuel_exit`.

## Assertions

- Never touch the Input singleton — only the parent's `cmd_*`/rotation
  (same rule as the TAS ghost).
- Fairness: never read the opponent's `cmd_*` fields or fuel; position
  knowledge must go through the lagged sample buffer.
- `_clear_cmds` runs every tick before anything writes — a cmd that stays
  true across ticks re-triggers just-pressed semantics (sword lunges
  every tick was the failure mode).
- The aim turn rate must degrade with the bot's OWN charge
  (`_own_charge`) — removing that coupling removes the dodge window and
  re-breaks the mechanic the practice bot exists to teach.
- Dodge events are per-arm and independent — never merged, never
  re-rolled mid-charge (Lily's calls: independent events, flat weights,
  lateral-8-way only — no vertical dodge moves).
- This bot is practice-tier by design: do not grow it into a Step 3
  validity instrument (Appendix A) and do not add a difficulty knob
  without Lily (single tuning set is her call).
- Structural literals (allowed, same class as player.gd's probe
  constants): the 8-ray refuel probe count, the ±(PI/2−0.1) pitch clamp,
  and the 0.5 strafe coin flip. The wall-normal filter is no longer a
  local literal — both probes call `PlayerMovement.is_wall_normal`
  (shared threshold, can't drift). Gameplay-feel numbers stay in
  `BotConfig`.
