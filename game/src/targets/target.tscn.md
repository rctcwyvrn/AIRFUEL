# target.tscn

## Function

The practice dummy's geometry: a humanoid-proportioned capsule with a
distinct head sphere, sized so headshots are a deliberate aim choice.

## Interface

- Root `Target` (Node3D, `target.gd`).
- `Body` (StaticBody3D at y 0.85, capsule r 0.4 × 1.5) with
  `metadata/hit_zone = "body"`; `Head` (StaticBody3D at y 1.85, sphere
  r 0.22) with `metadata/hit_zone = "head"` — `player.gd` reads the
  `hit_zone` meta off the ray collider and calls `take_hit` on its parent.
- Instanced by maps; place the root at floor level (feet at origin).

## Implementation

Head is orange, body green — matches the "head is a distinct aim target"
readability goal. StaticBody3D (not Area3D) so hitscan rays hit with default
`intersect_ray` settings.

## Assertions

- Both zone bodies keep the `hit_zone` metadata and remain direct children
  of the scripted root — the shooter resolves `collider.get_parent()` as
  the `TargetDummy`.
- Head must not overlap the body capsule enough for body rays to shadow it.
