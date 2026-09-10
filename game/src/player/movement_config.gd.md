# movement_config.gd

## Function

Schema for every movement tuning number — the code form of DESIGN.md
Appendix B ("Movement" block). Exists so that tuning is data (`.tres`), never
literals in scripts, and so numbers can be tweaked live in the inspector while
the game runs.

## Interface

- `class_name MovementConfig extends Resource` — plain data, no methods, no
  signals.
- Consumed by `player.gd` via its `config` export. Nothing else references
  the resource directly (the HUD and the parkour ghost reach it through the
  player's `config`).
- Fields are grouped with `@export_group`: Fuel, Ground, Air, Dash, Wallrun,
  Dismount, Assists (glide retention/angle, coyote windows, jump buffer),
  Ramp Persistence, Misc. Units: meters/seconds/degrees; costs and
  grants in fuel points; `dismount_fuel_per_speed` is fuel per (m/s above
  `min_wallrun_speed`).
- Wallrun group includes the corner-launch band (2026-09-10):
  `wallrun_corner_dismount_deg` (50) / `wallrun_corner_wrap_deg` (80) — a
  convex per-tick normal jump inside [50°, 80°) ejects the runner with
  velocity kept (wall-wedge apexes); below tracks as a curve, at/above
  wraps as a hairpin. Chosen so the parkour track's 45° corner blends keep
  wrapping (the shipped TAS tape depends on it) while the 62° wedge apexes
  launch. See player.gd.md `_wallrun_move`.

## Implementation

Defaults in this script ship unless `default_tuning.tres` overrides them —
the `.tres` is overrides-only (Lily's call, 2026-09-09): a line appears there
iff the value differs from the schema default, so changing a default here
changes live tuning.

## Assertions

- Adding a gameplay number to any script? It goes here instead (plus a
  `default_tuning.tres` line only if the shipped value differs from the
  default — overrides-only). Field names appear verbatim in the `.tres` when
  overridden, so renames must touch both files (and `player.gd`).
- Stays a pure `Resource` with no logic — it must remain safe to duplicate,
  serialize, and eventually ship per-server (DESIGN.md §19: tunable private
  servers).
