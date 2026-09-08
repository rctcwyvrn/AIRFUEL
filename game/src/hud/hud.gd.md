# hud.gd

## Function

Step 1 diagnostic HUD (DESIGN.md §15 is far future — this is just the
instruments the prototype questions need): Airfuel meter, horizontal speed,
movement state, ramp-grace countdown.

## Interface

- Extends `CanvasLayer`; script of `hud.tscn`'s root.
- Finds the player via group `"player"` (first node), lazily in `_process` —
  no exports to wire, works in any map that instances both scenes in either
  order.
- Reads only public player surface: `fuel`, `config.fuel_max`,
  `ramp_grace_timer`, `horizontal_speed()`, `state_name()`.
- Expected children: `FuelBar` (ProgressBar), `FuelLabel`, `SpeedLabel`,
  `StateLabel` (Labels).

## Implementation

Pure polling in `_process`, no signals — at prototype scale the cost is nil
and it keeps the player script free of UI coupling. `fuel_bar.max_value` is
re-set from config every frame so live tuning of `fuel_max` reflects
immediately.

## Assertions

- One-way dependency: HUD reads player; `player.gd` must never know the HUD
  exists.
- Must not crash when no player exists yet (null-guard stays).
- Speed shown is *horizontal* speed — that's the number the wallrun economy
  cares about; don't switch it to `velocity.length()` without also showing
  horizontal separately.
