# graybox_corridor.tscn

## Function

The Step 1 test corridor — built to answer DESIGN.md §24's questions: does
chaining emerge from dismount rewards, is curved wallrun viable, how far can
gaps stretch before flow breaks, how long should the corridor be. It is the
main scene.

## Interface

- Root `GrayboxCorridor` (Node3D); instances `player.tscn` (at z = -100,
  y = 2, rotated 180° to face +Z), `hud.tscn`, and three `target.tscn`
  dummies: Target1 (0, 0, −75) straight down the spawn sightline, Target2
  (10, 0, 5) mid-corridor, Target3 (−2, 12.5, 92) on the high platform.
- Any replacement map must provide the same two instances and solid geometry
  with default collision layers — the player probes walls via ray queries
  against `collision_mask` default.

## Implementation

All geometry is CSG with `use_collision = true` — cheapest possible editing
while the layout is in flux (swap for meshes + static bodies only when a
layout stabilizes). Corridor runs along +Z, 30 m wide, ~220 m long, walls
12 m high. Color code:

- **Gray floors** — three segments with two 10 m gaps (z −30…−20 and 40…50)
  over the void; falling below `kill_y` respawns.
- **Blue-gray walls** — staggered left/right segments so chaining requires
  crossing the corridor.
- **Orange cylinders** (r 2.5) — the curved-wallrun risk test (§22); two are
  placed to carry a runner across the floor gaps.
- **Teal panels** — floating mid-air walls forming a second vertical layer.
- **Purple platform** (y = 12, far end) — down-dash target.
- **Green/orange dummies** — Step 2 rail targets, placed for a point-blank
  test, a mid-range shot, and a long vertical shot.

Lighting: one DirectionalLight3D + ProceduralSky environment with
`glow_enabled` — glow is what makes the beam and charging-viewmodel emissive
materials actually bloom; enough to read speed and depth, nothing more.

## Assertions

- Every solid CSG node keeps `use_collision = true` — a decorative-only shape
  silently breaks wallrun probing and floor detection.
- Wallrunnable surfaces must be near-vertical: the controller rejects normals
  with `|y| > 0.4`.
- Player spawn stays above floor level (body origin is capsule center —
  y ≥ ~1) and inside the corridor.
- Layout changes are the *experiment* of Step 1: record distance/length
  findings in DESIGN.md §24 / Appendix B ("Corridor length" is explicitly
  blocked on this scene).
