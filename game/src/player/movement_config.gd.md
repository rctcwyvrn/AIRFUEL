# movement_config.gd

## Function

Schema for every movement tuning number — the code form of DESIGN.md
Appendix B ("Movement" block). Exists so that tuning is data (`.tres`), never
literals in scripts, and so numbers can be tweaked live in the inspector while
the game runs.

## Interface

- `class_name MovementConfig extends Resource` — plain data, no methods, no
  signals.
- Consumed by `player.gd` via its `config` export. Nothing else reads it yet
  (the HUD reaches it through `player.config`).
- Fields are grouped with `@export_group`: Fuel, Ground, Air, Dash, Wallrun,
  Dismount, Assists (glide retention/angle, coyote windows, jump buffer),
  Ramp Persistence, Misc. Units: meters/seconds/degrees; costs and
  grants in fuel points; `dismount_fuel_per_speed` is fuel per (m/s above
  `min_wallrun_speed`).

## Implementation

Defaults in this script are the fallback; the values that actually ship are in
`default_tuning.tres`. Keep both in sync when adding fields (a missing `.tres`
entry silently uses the script default — easy to miss).

## Assertions

- Adding a gameplay number to any script? It goes here + `default_tuning.tres`
  instead. Field names appear verbatim in the `.tres`, so renames must touch
  both files (and `player.gd`).
- Stays a pure `Resource` with no logic — it must remain safe to duplicate,
  serialize, and eventually ship per-server (DESIGN.md §19: tunable private
  servers).
