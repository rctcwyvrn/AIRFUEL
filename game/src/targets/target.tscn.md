# target.tscn

## Function

The practice dummy's geometry: a capsule with a distinct head sphere,
scaled 3× humanoid (body r 1.2 × 4.5 tall, head r 0.66) — oversized on
purpose for early range practice while aim crush is being tuned.

## Interface

- Root `Target` (Node3D, `target.gd`).
- `Body` (StaticBody3D at y 2.55, capsule r 1.2 × 4.5) with
  `metadata/hit_zone = "body"`; `Head` (StaticBody3D at y 5.55, sphere
  r 0.66) with `metadata/hit_zone = "head"`. Both live on
  **collision layer 2 / mask 0**: invisible to player movement and wallrun
  probes (mask 1), hit only by the rail hitscan (which ORs layer 2 in) — `player.gd` reads the
  `hit_zone` meta off the ray collider and calls `take_hit` on its parent.
- Instanced by maps; place the root at floor level (feet at origin).

## Implementation

Body is emissive red (highlight request), head orange — matches the "head is a distinct aim target"
readability goal. StaticBody3D (not Area3D) so hitscan rays hit them without
area-collision flags. Layer 2 keeps them shootable but not walkable — you
could previously wallrun off a dummy, which broke range practice.

## Assertions

- Both zone bodies keep the `hit_zone` metadata and remain direct children
  of the scripted root — the shooter resolves `collider.get_parent()` as
  the `TargetDummy`.
- Head must not overlap the body capsule enough for body rays to shadow it.
- Both zones stay on layer 2 (never 1) — layer 1 would make dummies
  collide with and wallrunnable by the player again.
