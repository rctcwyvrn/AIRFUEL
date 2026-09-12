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
and — netplay only — a kill scoreboard (top-right, YOU first, from
`Net.players`/`Net.scores` — scores are server-fed by the kill events)
plus the rotating-prism minimap
(see `minimap.gd` — hud.gd toggles its visibility with `Net.active` and
assigns its `track` target to the local player).

Step 3 duel feedback layer (§15.2, §8.2): directional **threat ring** around
the crosshair (enemy rail charges as escalating wedges — warn on EVERY
charge, no filtering — and incoming-damage arcs toward the attacker, drawn
by `threat_ring.gd`), **HP pips** in the bottom-right corner (above the
loadout label) with a persistent
low-HP vignette at 1 hp, an orange **hit flash** on `damaged`, the
sword proximity warning ("🗡WARNING️🗡 — AHEAD/BEHIND/LEFT/RIGHT",
within `combat.sword_warning_range`, pulsing), and — via
`Net.kill_reported` — a fading kill feed (under the minimap) plus a
"YOU KILLED Px" / "KILLED BY Px" center banner.

## Interface

- Extends `CanvasLayer`; script of `hud.tscn`'s root.
- Finds the player via group `"player"`, picking the node that
  `is_multiplayer_authority()` AND is not `ghost_controlled` AND not
  `bot_controlled` (offline: you, never the TAS ghost or the practice
  bot; networked: yours, not a remote puppet), lazily in `_process`,
  re-resolving if it's freed. Shows `player.hp` in the state line.
- Reads only public player surface: `sim.fuel`, `config.fuel_max`,
  `sim.ramp_grace_timer`, `horizontal_speed()`, `state_name()`,
  `arm_progress_left/right()` (rail charge, or sword cooldown-readiness),
  `sim.move_locked`, `loadout_name()`, `hp`, `combat.hp_max`,
  `combat.sword_warning_range`, `run_time`, `run_finished`, `countdown`,
  `recording`; on enemy bodies: `arm_types`,
  `display_arm_progress(i)`, `global_position`. Connects to `shot_fired`
  (hitmarkers), `damaged` (hit flash + damage arc), `died` (death flash),
  and the autoload signal `Net.kill_reported` (feed/banner). In netplay
  those three player signals are emitted by Net's server-event handlers
  (`_ev_shot` / `_ev_damage` fan-out — authoritative results, §20.2 N1),
  not by local simulation; offline the player emits them directly. The
  HUD doesn't care which — same signals either way.
- Expected children (`@onready` paths): `FuelBar`, `ChargeL`, `ChargeR`
  (ProgressBars), `FuelLabel`, `SpeedLabel`, `StateLabel`, `HitLabel`,
  `LockLabel`, `ScoreLabel`, `LoadoutLabel`, `TimerLabel`, `CountdownLabel`
  (Labels), `ControlsHint` (empty Control anchor — `_ready` builds the key
  grid into it from `KEY_LAYOUT`), `HitFlash`, `DeathFlash`, `MapBack`
  (ColorRects), `ThreatRing` (`threat_ring.gd`), `HpPips` (Control holding
  only the scene's `Back` backdrop — pips are built at adoption from
  `hp_max`; `_build_hp_pips` frees only `pip_rects`, so Back
  survives rebuilds), `SwordWarnLabel`, `KillBanner`
  (Labels), `KillFeed` (VBoxContainer — feed labels are runtime-built),
  `MapPrism` (`minimap.gd`). The scene's `Crosshair` is layout-only —
  the script never touches it.

## Implementation

Mostly polling in `_process` (charge bars, lock label, fuel); the player
signals (`shot_fired`, `damaged`, `died`) are connected lazily when the
player is first found (`Net.kill_reported` in `_ready`), because
hitmarkers, flashes, and feed lines are events, not state. Hit results map to distinct
text+color (HIT white / HEADSHOT orange / KILL red — §17's "distinct for
body vs head"), shown for 0.45s. Misses show nothing. `fuel_bar.max_value`
is re-set from config every frame so live tuning reflects immediately.
The controls highlighter is data-driven: `KEY_LAYOUT` rows are
`[action, label, x, y, width]`; `_ready` builds a ColorRect+Label per row
(skipping the respawn key when `Net.active` — T is solo-only)
and `_process` polls `Input.is_action_pressed` to swap KEY_DIM/KEY_LIT.

`_scan_threats` (every frame) walks group `"player"` for enemy bodies —
skipping self, ghosts, and any `is_multiplayer_authority()` body UNLESS
it's `bot_controlled` (the offline practice bot is an authority body but
a real enemy: its charges and sword must warn like a puppet's). Plain
offline solo finds nothing and the whole layer is silently inert. Rail arms with
`display_arm_progress(i)` > 0 become `{angle, progress}` wedges on the
ThreatRing — snapshot-fed on REPLICA puppets, real arm state on a LAN
host's DRIVEN bodies (the host IS the sim there); progress > 0 is exactly
CHARGING/PENDING — RailArm.progress() is 0 in
cooldown, so no false warning after the shot. The nearest sword carrier in
range drives the warning label, side text from the yaw-relative bearing
(`_bearing_to`: 0 = ahead, +PI/2 = right; ±45° AHEAD, ±135°+ BEHIND).
`damaged` freezes the attacker's bearing at hit time into a fading arc
(the attacker resolves through `Net.players`; offline that misses, so it
falls back to the `bot_controlled` body — the only possible offline
attacker).
Kill feed labels self-fade over 4 s then free; the banner shows 1.8 s.
Peer tags (`_peer_tag`) resolve through `Net.display_name(id)` — real
usernames in dedicated-server matches, "P%d" fallback in LAN.

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
- The charge warning must key off `display_arm_progress` — the role-aware
  source (snapshot-fed for replicas; a LAN host's DRIVEN bodies answer
  from real arm state, which is authoritative there) — never a replica's
  local `RailArm` nodes, which don't simulate. An invisible enemy charge
  would gut the dodge duel (§8.1's loud-tell rule).
- Warn on EVERY enemy rail charge — no range gate, no aim filter (the
  aim-cone filter died with aim crush; §15.2 defers filtering to
  playtesting).
- Runtime-built Controls (pips, feed labels) get `MOUSE_FILTER_IGNORE`,
  same as the key grid.
