# hud.gd

## Function

Steps 1+2 diagnostic HUD (DESIGN.md §15 is far future — this is just the
instruments the prototype questions need): Airfuel meter, horizontal speed,
movement state, ramp-grace countdown, per-arm charge bars, crosshair,
hitmarker, and a LOCKED indicator during the charge freeze.

## Interface

- Extends `CanvasLayer`; script of `hud.tscn`'s root.
- Finds the player via group `"player"` (first node), lazily in `_process` —
  no exports to wire, works in any map that instances both scenes in either
  order.
- Reads only public player surface: `fuel`, `config.fuel_max`,
  `ramp_grace_timer`, `horizontal_speed()`, `state_name()`,
  `arm_progress_left/right()`, `move_locked`; connects to the player's
  `shot_fired(side, result)` signal for hitmarkers.
- Expected children: `FuelBar`, `ChargeL`, `ChargeR` (ProgressBars),
  `FuelLabel`, `SpeedLabel`, `StateLabel`, `HitLabel`, `LockLabel` (Labels),
  `Crosshair` (ColorRect).

## Implementation

Mostly polling in `_process` (charge bars, lock label, fuel); the one
signal is `shot_fired`, connected lazily when the player is first found,
because hitmarkers are events, not state. Hit results map to distinct
text+color (HIT white / HEADSHOT orange / KILL red — §17's "distinct for
body vs head"), shown for 0.45s. Misses show nothing. `fuel_bar.max_value`
is re-set from config every frame so live tuning reflects immediately.

## Assertions

- One-way dependency: HUD reads player; `player.gd` must never know the HUD
  exists.
- Must not crash when no player exists yet (null-guard stays).
- Speed shown is *horizontal* speed — that's the number the wallrun economy
  cares about; don't switch it to `velocity.length()` without also showing
  horizontal separately.
- Hitmarker must stay visually distinct per zone (body vs head vs kill) —
  §17 makes unambiguous hit confirmation load-bearing.
