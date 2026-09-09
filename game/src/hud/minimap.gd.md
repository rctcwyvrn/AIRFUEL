# minimap.gd

## Function

The LAN minimap: the corridor volume as a compass-locked wireframe prism
(it turns with your facing) with live player dots, drawn entirely in 2D
via manual 3D projection.

## Interface

- Script of `MapPrism` (Control) in `hud.tscn`; `hud.gd` toggles its
  `visible` with `Net.active` (alongside the `MapBack` backdrop).
- `track: Node3D` — the local player, assigned by `hud.gd` at adoption;
  drives the compass-lock yaw.
- Reads `Net.players` directly each draw; you = orange dot, others = red.
- No exports, no signals.

## Implementation

Replaces a SubViewport/own-world approach that rendered blank on Lily's
editor build — `_draw` has no viewport/world/camera pipeline to misbehave.
Projection: yaw-rotate (compass-locked: `yaw = PI − player.rotation.y`,
smoothed with `lerp_angle`, so your facing points up-screen; `track` is
assigned by hud.gd) → fixed pitch tilt → orthographic drop with screen-x
NEGATED (chirality fix: without it left/right are mirrored),
`ZOOM` to fit the 220×160 rect. World positions divide by `MAP_DIV`
(3, 3, 12) — **non-uniform**: the 880 m corridor squashes 4× harder
lengthwise than in girth or the prism reads as a sliver (both failed
approaches are why these numbers exist). `queue_redraw` every frame while
visible.

## Assertions

- `HALF` must stay = corridor half-extents (40, 20, 440) ÷ `MAP_DIV`;
  changing the arena size means updating both.
- Marker projection must use the same `MAP_DIV`/`_project` as the prism,
  or dots drift off the geometry.
- The grey filled quad is the FLOOR face (corners 0,1,5,4 = y-negative);
  if corner index encoding changes, re-derive those indices.
- Keep `mouse_filter = 2` on the node (HUD-wide rule).
