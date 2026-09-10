# bot_config.gd

## Function

Tuning schema for the practice bot (DESIGN.md Appendix A: the bot returned
as an always-available *practice* opponent — never the Step 3 validity
test). Same convention as `MovementConfig`/`CombatConfig`: every bot
gameplay number is a field here, values live in `default_bot.tres`, no
literals in `bot_controller.gd`.

## Interface

- `class_name BotConfig extends Resource`; consumed only by
  `BotController.bot` (assigned by `PracticeSpawner` from
  `default_bot.tres`).
- **Brain**: `brain_hz` — intent/dice tick rate (§19.3's intent-level
  shape: slow goals, per-tick execution).
- **Aim**: `turn_rate_free` / `turn_rate_charged` (rad/s) — the bot-only
  aim crush: tracking degrades toward `turn_rate_charged` as the bot's own
  rail charge builds. `aim_smoothing` (per-second proportional gain — the
  tracking eases into targets instead of slam-stopping; the rate cap
  still binds on big swings), `noise_ease` (per-second easing of the
  noise offsets toward their per-think targets — no 8 Hz snapping),
  `aim_lag` (s of target-position staleness), `aim_noise_deg` (Gaussian
  wander, scaled live by target speed), `fire_cone_deg` (max aim error
  to start a charge), `stagger_chance` (per-think odds the second rail
  charges while the first is locking).
- **Dodge**: `reaction_mean/dev/min/max` (s, clamped Gaussian reaction to
  an enemy charge), `dodge_weight_dash/strafe/none` (response roll),
  `dodge_lead` ± `dodge_lead_jitter` (s before shot-land to dash),
  `dodge_probe_range` (wall check before dashing sideways).
- **Movement**: `strafe_hold_min/max` (s between strafe flips),
  `preferred_range_min/max` (rail orbit band),
  `dual_sword_range_min/max` (much closer band for sword+sword), and the
  air-hunger knobs (2026-09-10, Lily's calls — bots live in the air,
  and fuel management is wallrun-first, not dash-first):
  `air_fuel_floor` (80 — fuel below which double jumps stop),
  `dash_fuel_floor` (100 — movement dashes are the luxury spend, gated
  higher than double jumps; dodge dashes are unaffected),
  `wall_seek_fuel` (120 — below this the engage orbit drifts toward the
  nearest side wall to farm ride/dismount fuel mid-fight),
  `move_dash_chance` (per-think odds of a movement dash),
  `engage_wall_ride_time` (wall time before jumping off for the
  dismount grant), `double_jump_fall_speed` (falling speed that
  triggers a fueled double jump). Ordering invariant:
  `refuel_enter < air_fuel_floor < dash_fuel_floor < wall_seek_fuel` —
  income behaviors engage before spends shut off, and last-resort
  REFUEL stays the bottom of the ladder.
- **Fuel**: `refuel_enter`/`refuel_exit` (fuel thresholds for the
  wallrun-refuel intent), `refuel_ride_time` (wall time before the
  dismount jump), `refuel_probe_range`, `refuel_approach_lead` (how far
  along the wall to aim the approach), `refuel_jump_dist` (wall distance
  that triggers the attach jump).
- **Sword**: `sword_max_range` (hard gate — no kill lunge beyond it),
  `sword_fuel_reserve` (fuel that must remain after a lunge),
  `sword_aim_cone_deg`, `sword_commit_factor` (× `sword_hit_range` =
  "already committed" reach that also opens the kill window).

## Implementation

Defaults in the schema are the shipped values; `default_bot.tres`
currently overrides nothing. There is deliberately **no difficulty knob**
(Lily's call) — one tuning set, edited in the tres.

## Assertions

- Any new bot behavior number gets a field here, never a literal in
  `bot_controller.gd`.
- `turn_rate_charged` must stay well below `turn_rate_free` — the gap IS
  the dodge window; closing it silently makes the bot untrackably strong
  and re-breaks charge → tell → dodge.
- `dodge_weight_*` are relative weights (any positive scale), not
  probabilities that must sum to 1.
