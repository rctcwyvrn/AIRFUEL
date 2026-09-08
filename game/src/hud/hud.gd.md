# hud.gd

## Function

Steps 1+2 diagnostic HUD (DESIGN.md §15 is far future — this is just the
instruments the prototype questions need): Airfuel meter, horizontal speed,
movement state, ramp-grace countdown, per-arm charge bars, crosshair,
hitmarker, a LOCKED indicator during the charge freeze, a controls
highlighter (bottom-left key cluster that lights up pressed inputs), the
current loadout (bottom-right), a red death flash on the `died` signal, a run timer (top-center,
mm:ss.mmm — visible only when a `"finish"`-group zone exists in the
scene, green once finished),
and — LAN only — a kill scoreboard (top-right, YOU first, from
`Net.players`/`Net.scores`) plus the rotating-prism minimap
(see `minimap.gd` — hud.gd only toggles its visibility with `Net.active`).

## Interface

- Extends `CanvasLayer`; script of `hud.tscn`'s root.
- Finds the player via group `"player"`, picking the node that
  `is_multiplayer_authority()` AND is not `ghost_controlled` (offline: you,
  never the TAS ghost; networked: yours, not a remote puppet), lazily in
  `_process`, re-resolving if it's freed.
  Shows `player.hp` in the state line.
- Reads only public player surface: `fuel`, `config.fuel_max`,
  `ramp_grace_timer`, `horizontal_speed()`, `state_name()`,
  `arm_progress_left/right()` (rail charge, or sword cooldown-readiness),
  `move_locked`, `loadout_name()`; connects to `shot_fired` (hitmarkers)
  and `died` (death flash).
- Expected children: `FuelBar`, `ChargeL`, `ChargeR` (ProgressBars),
  `FuelLabel`, `SpeedLabel`, `StateLabel`, `HitLabel`, `LockLabel` (Labels),
  `Crosshair` (ColorRect), `ControlsHint` (empty Control anchor —
  `_ready` builds the key grid into it from `KEY_LAYOUT`).

## Implementation

Mostly polling in `_process` (charge bars, lock label, fuel); the one
signal is `shot_fired`, connected lazily when the player is first found,
because hitmarkers are events, not state. Hit results map to distinct
text+color (HIT white / HEADSHOT orange / KILL red — §17's "distinct for
body vs head"), shown for 0.45s. Misses show nothing. `fuel_bar.max_value`
is re-set from config every frame so live tuning reflects immediately.
The controls highlighter is data-driven: `KEY_LAYOUT` rows are
`[action, label, x, y, width]`; `_ready` builds a ColorRect+Label per row
(skipping the respawn key when `Net.active` — T is solo-only)
and `_process` polls `Input.is_action_pressed` to swap KEY_DIM/KEY_LIT.

## Assertions

- One-way dependency: HUD reads player; `player.gd` must never know the HUD
  exists.
- Must not crash when no player exists yet (null-guard stays).
- Speed shown is *horizontal* speed — that's the number the wallrun economy
  cares about; don't switch it to `velocity.length()` without also showing
  horizontal separately.
- Hitmarker must stay visually distinct per zone (body vs head vs kill) —
  §17 makes unambiguous hit confirmation load-bearing.
- Every runtime-built key Control gets `MOUSE_FILTER_IGNORE` — same
  mouse-look-eating hazard as the hud.tscn assertion.
- `KEY_LAYOUT` action names must exist in project.godot; renaming an input
  action must touch this table too.
