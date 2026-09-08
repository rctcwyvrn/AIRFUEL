# Airfuel — Godot prototype

**Roadmap Steps 1 + 2** (see `../design/DESIGN.md` §24). Gray box corridor,
one player, three stationary targets. Wallrun economy, dismount grants, ramp
persistence, dashes, terminal velocity, Airfuel meter — plus dual railgun
arms: 1s auto-firing charge, movement freeze / trajectory lock, aim crush,
staggered dual-rail gap, hitscan (2 body / 1 head), canister ejection.

## Run

```sh
nix-shell                      # from the repo root
godot4 --path game --editor    # open in editor
godot4 --path game             # just play
```

## Controls

| Input | Action |
|---|---|
| WASD + mouse | Strafe / look |
| E / Q | Strafe up / down in the air (fuel) |
| Space | Jump / double jump (fuel) / wallrun dismount |
| Shift + WASD/E/Q | Dash in that direction (fuel); Shift+Q alone = down dash |
| LMB / RMB | Charge left / right rail arm (auto-fires after 1s, locks movement) |
| R | Respawn |
| Esc | Release mouse |

Bare Shift does nothing — a dash always needs a held direction. WASD dashes
are in the facing (yaw) plane; E/Q dash straight up/down.

## What to test (Step 1 + 2 questions from the design doc)

- Does chained-short-runs feel emerge from the dismount reward?
- Is curved-surface wallrun viable (orange cylinders)?
- How far apart can platforms be before flow breaks (floor gaps, teal panels)?
- How long should the corridor actually be?
- Does the rail charge feel good to commit to? (freeze + aim crush + no cancel)
- Is the dual-rail stagger a usable rhythm instrument?

## Tuning

Movement numbers: `src/player/default_tuning.tres` (schema
`movement_config.gd`). Combat numbers: `src/weapons/default_combat.tres`
(schema `combat_config.gd`). Both mirror DESIGN.md Appendix B; edit in the
inspector while the game runs for live tuning.

## Layout

- `src/player/` — kinematic controller (`CharacterBody3D` base, radial ray
  probes for flat + curved walls), movement tuning resource
- `src/weapons/` — rail arm state machine, combat tuning, canister prop
- `src/targets/` — self-respawning 2 HP practice dummy (orange head = lethal)
- `src/hud/` — fuel bar, speed/state readout, charge bars, hitmarkers
- `maps/graybox_corridor.tscn` — the test corridor (main scene)
