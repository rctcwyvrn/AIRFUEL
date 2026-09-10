# kite_wireframe.gd

## Function

Runtime edge-wireframe generator for the graybox corridor's kite obstacles:
draws opaque beams along every polygon edge (bottom rim, top rim, vertical
corners) of each sibling kite, giving the transparent kites their "lined
edges" borders (Lily's call, 2026-09-10) without hand-writing ~300 beam
nodes into the tscn.

## Interface

- `class_name KiteWireframe extends Node3D`; placed in a map scene as a
  sibling of the kite nodes (`KiteWireframes` in `graybox_corridor.tscn`).
- Exports: `beam_thickness` (0.18 m) and `beam_color` (the identity
  orange) — cosmetic only.
- Discovers targets at `_ready`: every sibling `CSGPolygon3D` with
  `metadata/deflector = true`. No other coupling; maps without tagged
  kites get an empty node.

## Implementation

For each kite, reads `polygon` + `depth` + `global_transform` and computes
the prism's corners: CSGPolygon3D depth-mode extrudes the local-XY polygon
along local −Z, so bottom = `T * (v.x, v.y, 0)` and top =
`T * (v.x, v.y, -depth)`. Emits one `MeshInstance3D` thin `BoxMesh` beam
per edge (n bottom + n top + n vertical = 12 for the rhombus kites), all
sharing one unshaded `StandardMaterial3D`, shadows off, aligned via
`look_at` with an up-vector fallback for near-vertical beams. Beams are
runtime children of this node — they never appear in the tscn diff.

## Assertions

- Pure visuals: no collision shapes, no gameplay reads/writes — deleting
  this node must change nothing but looks.
- Target discovery stays keyed on the `deflector` meta (the same tag the
  glide assist uses), so a new kite gets its wireframe by tagging alone.
- Beam length includes `+ beam_thickness` so corner beams overlap and
  joints read closed, not gapped.
