# hud.gd

## Function

Steps 1–3 diagnostic HUD (DESIGN.md §15 at prototype tier — the instruments
the prototype questions need): Airfuel meter, horizontal speed,
movement state, ramp-grace countdown, per-arm charge bars, crosshair,
hitmarker, a LOCKED indicator during the charge freeze, a controls
highlighter (bottom-left key cluster that lights up pressed inputs), the
current loadout (bottom-right), a red death flash on the `died` signal, a 3-2-1 countdown + GO flash (center, orange, after every reset),
a run timer (top-center,
mm:ss.mmm — visible only when a `"finish"`-group zone exists in the
scene, green once finished),
and — LAN only — a kill scoreboard (top-right, YOU first, from
`Net.players`/`Net.scores`) plus the rotating-prism minimap
(see `minimap.gd` — hud.gd only toggles its visibility with `Net.active`).

Step 3 duel feedback layer (§15.2, §8.2): directional **threat ring** around
the crosshair (enemy rail charges as escalating wedges — warn on EVERY
charge, no filtering — and incoming-damage arcs toward the attacker, drawn
by `threat_ring.gd`), **HP pips** above the crosshair with a persistent
low-HP vignette at 1 hp, an orange **hit flash** on `damaged`, the
"SWORD NEARBY — LEFT/RIGHT/AHEAD/BEHIND" proximity warning
(within `combat.sword_warning_range`, pulsing), and — via
`Net.kill_reported` — a fading kill feed (under the minimap) plus a
"YOU KILLED Px" / "KILLED BY Px" center banner.

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
  `move_locked`, `loadout_name()`, `hp`, `combat.hp_max`,
  `combat.sword_warning_range`; on enemy puppets: `arm_types`,
  `remote_arm_progress(i)`, `global_position`. Connects to `shot_fired`
  (hitmarkers), `damaged` (hit flash + damage arc), `died` (death flash),
  and the autoload signal `Net.kill_reported` (feed/banner).
- Expected children: `FuelBar`, `ChargeL`, `ChargeR` (ProgressBars),
  `FuelLabel`, `SpeedLabel`, `StateLabel`, `HitLabel`, `LockLabel` (Labels),
  `Crosshair` (ColorRect), `ControlsHint` (empty Control anchor —
  `_ready` builds the key grid into it from `KEY_LAYOUT`), `HitFlash`
  (ColorRect), `ThreatRing` (`threat_ring.gd`), `HpPips` (empty Control —
  pips are built at adoption from `hp_max`), `SwordWarnLabel`, `KillBanner`
  (Labels), `KillFeed` (VBoxContainer — feed labels are runtime-built).

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

`_scan_threats` (every frame) walks group `"player"` for enemy puppets —
skipping self, ghosts, and any `is_multiplayer_authority()` body, so offline
it finds nothing and the whole layer is silently inert. Rail arms with
synced progress > 0 become `{angle, progress}` wedges on the ThreatRing
(progress > 0 is exactly CHARGING/PENDING — RailArm.progress() is 0 in
cooldown, so no false warning after the shot); the nearest sword carrier in
range drives the warning label, side text from the yaw-relative bearing
(`_bearing_to`: 0 = ahead, +PI/2 = right; ±45° AHEAD, ±135°+ BEHIND).
`damaged` freezes the attacker's bearing at hit time into a fading arc.
Kill feed labels self-fade over 4 s then free; the banner shows 1.8 s.

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
- The charge warning must key off synced puppet progress
  (`remote_arm_progress`), never local arm state — an invisible enemy charge
  would gut the dodge duel (§8.1's loud-tell rule).
- Warn on EVERY enemy rail charge — no range gate, no aim filter (the
  aim-cone filter died with aim crush; §15.2 defers filtering to
  playtesting).
- Runtime-built Controls (pips, feed labels) get `MOUSE_FILTER_IGNORE`,
  same as the key grid.
