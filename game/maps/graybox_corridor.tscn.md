# graybox_corridor.tscn

## Function

The Step 1 test corridor — built to answer DESIGN.md §24's questions: does
chaining emerge from dismount rewards, is curved wallrun viable, how far can
gaps stretch before flow breaks, how long should the corridor be. Loaded from
the main menu (PLAY SOLO) and by `network.gd` as the netplay arena — on
LAN hosts/clients, on lobby-match clients, and headless on each per-match
child server (which strips the offline Player and dummies, then spawns
per-peer bodies) — the project's main scene is the menu, not this map.

## Interface

- Root `GrayboxCorridor` (Node3D); instances `player.tscn` (at z = −430,
  y = 2.6, rotated 180° to face +Z), `hud.tscn`, a `PracticeSpawner`
  node (`src/bot/practice_spawner.gd` — dormant unless the menu queued a
  DUEL VS AI; spawns the practice bot at its default `bot_spawn`,
  (0, 2.6, 430) — the opposite end of the corridor, facing the player
  spawn — and removes all dummies for the duel), and
  15 `target.tscn` dummies (`Target1-15`): Target1
  (0, 0, −405) down the spawn sightline, the rest scattered at ground level
  every ~60–80 m across varied x (Target16-17 were removed with the
  elevated platforms they stood on, 2026-09-10).
- `Bgm` (AudioStreamPlayer, `src/props/bgm_player.gd`): combat background
  music — `res://sounds/bgm.wav` at −10 dB, forward-looped via its
  `.import` (`edit/loop_mode=1`). The script (not the autoplay flag)
  starts it so the headless server stays silent; the menu and parkour
  map have no BGM by design (Lily, 2026-09-10: "bgm for combat").
- Any replacement map must provide the same two instances (plus a
  `PracticeSpawner` if it should support DUEL VS AI) and solid geometry
  with default collision layers — the player probes walls via ray queries
  against `collision_mask` default.

## Implementation

All geometry is CSG with `use_collision = true` — cheapest possible editing
while the layout is in flux (swap for meshes + static bodies only when a
layout stabilizes). Corridor runs along +Z, **80 m wide, 880 m long**
(z −440…440), fully sealed: two continuous 40 m walls (x = ±40), a roof at
y 40, and end walls (`EndWallN`/`EndWallS` at z = ±440) — the map is a
closed box; falling out is impossible (kill_y remains as a safety net). The node placement is loop-generated in
bands (see git history for the generator) but checked in as plain tscn.
Color code:

- **Gray floor** — one continuous 80×880 slab, no holes; with the sealed
  box, `kill_y` is unreachable in practice.
- **Blue-gray walls** (x = ±40) — continuous, floor to roof; you cannot
  fall out the sides. Infinite parallel wallrun surfaces, so interior
  features are what force crossings now. Slightly translucent
  (2026-09-10: `mat_wall` alpha 0.75) so the spacescape sky shows through;
  their `cast_shadow` is OFF to match — an opaque shadow from a
  see-through wall reads as a bug.
- **Roof** (y 40.5, gray) — `cast_shadow` is OFF so the sun still lights
  the interior; don't turn it on without adding interior lighting.
- **Roof lights** — `LightPanel1-11` (emissive 6×6 strips under the roof
  every 80 m) each paired with an `OmniLight3D` (energy 0.8, range 55).
- **Tan wall wedges** — `LWedge1-4` / `RWedge1-4`, symmetric triangular
  CSGPolygon3D kickers spanning the FULL wall height (floor to roof,
  y 0-40; was 6 m at alternating bases until 2026-09-10, Lily's call),
  6 m peak jut at mid-run over a 20 m footprint — a kite in plan view,
  a vertical ridge in elevation (deepened from 3 m/10 m on 2026-09-10:
  the shallow apex let wallrun tracking fold around it and killed the
  launch). Both slanted faces sit at ~31° — rideable — and the ~62° apex
  flip lands in the movement system's convex corner-launch band
  (`wallrun_corner_dismount_deg`, see player.gd.md), so a runner crossing
  the apex ejects with velocity intact from either approach direction
  (rig-verified: 51 m/s carried off the lip). Polygon local frame:
  X = world X, Y = world Z, extrusion rises upward (basis maps −Z to
  +Y).
- **Kites** — every interior obstacle is now a rhombus prism (all-kite
  pass 2026-09-10; the obround slots' rounded caps could stop a
  dead-center runner): `BigKite1-6` (24 × 12, 36 tall), `MidKite1-7`
  (20 × 10, 32 tall) at x = ±15, `CenterKite1-5` (16 × 8, 40 tall) on the
  center line (CenterKite1 at z −336, shifted 6 m south — overlap fix),
  and `LongKite1-6` (60 × 5, 36 tall) zigzagging the outer lanes at
  x = ±22. Noses along ±z; faces are glancing to corridor travel (Big
  ~27°, Long ~5°). Every kite carries `metadata/deflector = true`: the
  glide assist skips its head-on rejection for tagged geometry, so even a
  dead-center nose hit splits you around it at glide retention
  (rig-verified) — bumping a kite can never stop you. Nose-corner normal
  flips land in the wallrun corner-launch band where wide enough (Big
  ~53°), so running a face off a nose ejects like the wall kites.
  Rendered as transparent orange (`mat_kite_glass`, alpha 0.32) with
  opaque wireframe borders on the actual edges — beams generated at
  runtime by the sibling `KiteWireframes` node (`kite_wireframe.gd`,
  discovers kites by the `deflector` meta; 12 beams per kite).
- **Removed 2026-09-10** (Lily's look experiment — corridor stripped to
  shell + kites + slots + ribs; revert via git if it reads wrong): teal
  panel ladder lines, outer panels, purple platforms, diag/spine panels,
  the two platform-top targets, and (Lily's own editor pass) the Tower
  pillars and low Cover boxes. Note: duel cover near the spawn ends went
  with the Covers — revisit before the next playtest round.

Lighting: one DirectionalLight3D (shadow distance raised to 400 for the long
corridor) + a **spacescape sky** (2026-09-10): the Environment's Sky uses a
ShaderMaterial on `res://maps/space_sky.gdshader` (procedural stars/nebulae
+ a sun disc aligned to the DirectionalLight — see its sidecar). Because
the space sky contributes almost no light, ambient is explicit:
`ambient_light_source = 2` (color) with a blue-grey color at energy 1.6 —
without it the corridor interior goes murky (verified via screenshot rig).
`glow_enabled` stays on — glow is what makes the beam and
charging-viewmodel emissive materials actually bloom.

## Assertions

- Every solid CSG node keeps `use_collision = true` — a decorative-only shape
  silently breaks wallrun probing and floor detection.
- Wallrunnable surfaces must be near-vertical: the controller rejects normals
  with `|y| > 0.4`.
- Player spawn stays above floor level (body origin is capsule center of
  the dummy-sized 4.5 m capsule — y ≥ ~2.3) and inside the corridor.
- Layout changes are the *experiment* of Step 1: record distance/length
  findings in DESIGN.md §24 / Appendix B ("Corridor length" is explicitly
  blocked on this scene).
