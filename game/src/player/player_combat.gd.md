# player_combat.gd

## Function

The player's combat layer (DESIGN.md §7, §8), split out of player.gd
2026-09-10: arm triggering + dual-rail sequencing, the rail shot
(offline and lag-compensated netplay branches), the sword lunge + hit
check, loadout visuals, and the per-frame weapon viewmodel glow.

## Interface

- `class_name PlayerCombat extends Object` — stateless static functions
  over the player body (`PlayerState` pattern: params typed
  `CharacterBody3D`, never `AirfuelPlayer`; other bodies are recognized
  by **group `"player"` membership**, not `is AirfuelPlayer`, for the
  same cycle-avoidance reason). ALL state lives on the player.
- Simulation-side (called from `_simulate()`): `handle_arms(p)` (swap +
  triggers + min-gap FIFO firing), `trigger_arm(p, index)`,
  `sword_hit_check(p)`, `fire_rail(p, arm)`.
- Visual-side (render tick / on loadout change):
  `apply_loadout_visuals(p)`, `update_viewmodels(p, delta)`.
- Uses `Net` (match host presence, headless/active flags), `PlayerFx`
  (beam/canister one-shots), `RailArm`, `TargetDummy`.

## Implementation

- **Firing (§7.1, §8.1)**: `handle_arms` starts charges on trigger
  press; completed charges queue in `p.pending_arms` (FIFO = press
  order) and fire no closer than `min_shot_gap` apart, sequenced by
  `p.shot_gap_timer` — a tick timer captured in state, never wall clock
  (prediction replays re-run this code).
- **`fire_rail`** is role-dependent: `arm.on_fired()` always advances
  the state machine; `p.replaying` short-circuits everything else.
  **Authoritative netplay** (`Net.match_host != null`, not PREDICTED):
  `eval_rail_hit` tests victims at their §20.2 N2 *rewound* positions;
  a victim takes `apply_damage`, whose bool picks "kill" vs "body".
  **Offline / PREDICTED**: local camera-center raycast (mask = player
  mask OR layer 2), `hit_zone` meta for dummy body/head damage; against
  player-group bodies a PREDICTED shot is muzzle-flash only ("body"
  visual — the server decides), while a LOCAL shot (offline practice
  duel) applies real `apply_damage`. Local fx (viewmodel kick,
  `PlayerFx.spawn_beam`/`spawn_canister`/`play_rail_sound` at the
  muzzle) are gated on `not Net.headless`; `shot_fired` emits directly
  only offline.
- **Sword (§8.2)**: `trigger_arm` on a sword side lunges toward the
  camera — full-commit redirect to `sword_lunge_speed`, ramp grace,
  fueled via `p._spend`, per-arm cooldown, blocked only while
  charge-locked. **Lunging off a wall works and is a real dismount**
  (2026-09-10, Lily's call — same semantics as dashing off:
  `PlayerMovement.dismount(true)` fuel grant, then the longer
  `dash_wall_rearm_time` anti-pogo lockout; the lunge velocity replaces
  the dismount boost as the launch). The stab kick is skipped when
  `p.replaying`.
  `sword_hit_check` (while `sword_active`) kills the first player-group
  body or dummy within `sword_hit_range` (99 dmg, one hit per lunge),
  only where the sim is authoritative (PREDICTED returns early); in
  netplay reach is measured to `rewound_position` and reported via
  `match_host.on_shot`; offline practice emits the lunger's own
  `shot_fired` "kill" hitmarker. No freeze, no ranged component, ever.
- **Loadout visuals**: rail = chunky block held level, sword = long thin
  blade rolled inward/tilted up; pose stored as `pose_rot` meta so the
  recovery lerp returns to stance, not zero. On a `bot_controlled` body
  post-ready it also tints the puppet shoulder blocks per arm type.
- **`update_viewmodels`** (every rendered tick): per-side emission —
  rail: charge glow (progress × 3) warm-orange, or the **cooldown
  readout** (2026-09-10, Lily's spec): `VM_COOLDOWN_COLOR` yellow at
  intensity ∝ remaining cooldown fraction — brightest right after the
  shot, fading to nothing at ready. Sword: blue `SWORD_FLARE_COLOR`
  while lunging, the same yellow cooldown fade while `sword_cd[i]`
  runs, warm idle otherwise. Explicit emission color on every path —
  the material is shared per side across weapon swaps. Positions/
  rotations lerp back to `rest_pos`/`pose_rot` metas after kicks.

## Assertions

- Simulation-side functions must respect the `p.replaying` guard: a
  replayed tick advances arm state machines but never re-does damage,
  fx, kicks, or match-host reports.
- No charge cancel exists anywhere; a charge always ends in a shot.
  Dual shots never closer than `min_shot_gap`, FIFO through
  `pending_arms` + `shot_gap_timer` (tick timer, never wall clock).
- Only authoritative sims apply damage: PREDICTED shots and lunges are
  visuals/movement only; netplay hit tests go through the match host's
  rewind (`eval_rail_hit` / `rewound_position`), never live positions.
- Bodies are identified via group `"player"` + duck typing — never
  `is AirfuelPlayer` (class-resolution cycle); ghosts
  (`ghost_controlled`) are excluded from all damage.
- The cooldown glow is first-person viewmodel feedback ONLY — enemy
  puppet shoulder blocks show charge (the §8.1 tell) and must not gain
  a cooldown readout without a design decision.
- Params stay typed `CharacterBody3D`; enum access stays dynamic for
  player enums (`p.NetRole.*`) and via the global `MoveSim.MoveState`
  for move state (the enum moved into MoveSim in the Trellis-style
  pilot). Movement state reads/writes go through `p.sim`
  (`move_locked`, `state`, `wall_rearm_timer`, `ramp_grace_timer`) —
  and the lunge launch writes `p.sim.velocity`, never the body's
  `velocity` mirror.
