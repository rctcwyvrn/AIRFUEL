# Airfuel — Godot prototype

**Roadmap Step 1: movement alone** (see `../design/DESIGN.md` §24).
Gray box corridor, one player. Wallrun economy, dismount grants, ramp
persistence, air/down dash, terminal velocity, Airfuel meter.

## Run

```sh
nix-shell                      # from the repo root
godot4 --path game --editor    # open in editor
godot4 --path game             # just play
```

## Controls

| Input | Action |
|---|---|
| WASD + mouse | Move / look |
| Space | Jump / double jump (fuel) / wallrun dismount |
| Shift | Omnidirectional dash (fuel, camera-aimed) |
| Ctrl or C | Down dash (fuel) |
| R | Respawn |
| Esc | Release mouse |

## What to test (Step 1 questions from the design doc)

- Does chained-short-runs feel emerge from the dismount reward?
- Is curved-surface wallrun viable (orange cylinders)?
- How far apart can platforms be before flow breaks (floor gaps, teal panels)?
- How long should the corridor actually be?

## Tuning

Every number lives in `src/player/default_tuning.tres`
(schema: `src/player/movement_config.gd`, mirrors DESIGN.md Appendix B).
Edit it in the inspector while the game runs for live tuning.

## Layout

- `src/player/` — kinematic controller (`CharacterBody3D` base, radial ray
  probes for flat + curved walls), tuning resource
- `src/hud/` — fuel bar, speed, state readout
- `maps/graybox_corridor.tscn` — the test corridor (main scene)
