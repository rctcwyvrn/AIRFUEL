---
name: apply_glide
---

# apply_glide

Momentum-preserving glide (Celeste-style), run after `move_and_slide`
except during wallrun: when a slide collision ate horizontal speed, a
glancing hit on a wall-ish surface (|normal.y| < 0.4) redirects the
pre-impact speed along the surface at `glide_speed_retention` instead of
letting the wall eat it. Near-head-on impacts — beyond
`glide_max_impact_angle_deg` from the surface plane — still stop you:
commitment reads as a real collision, grazing doesn't. Map-authored
deflector geometry (`metadata/deflector`, the pointed kite obstacles) skips
the head-on rejection: even a dead-center hit splits you around it.

Collisions arrive as plain data rows `{normal: Vector3, deflector: bool}`,
extracted from the physics result by the facade.

```gd-sig
apply_glide : (sim: MoveSim, cfg: MovementConfig, pre_vel: Vector3, collisions: Array[Dictionary]) -> void
```

```requires
post-slide: sim.velocity is the post-move_and_slide velocity of the same tick as pre_vel
```

```ensures
never adds speed: new horizontal speed <= pre-impact horizontal speed * cfg.glide_speed_retention
only helps: velocity changes only when the redirect target beats the post-slide speed
vertical untouched: velocity.y never changes
only velocity changes: no other sim field is written
```

```test glancing-redirect
with sim = {velocity: [0.0, -2.0, -1.0]}
(sim, cfg, [0.0, -2.0, -20.0], [{normal: [1, 0, 0], deflector: false}]) => {velocity: [0.0, -2.0, -18.0]}
```

```test head-on-stops
with sim = {velocity: [-0.5, 0.0, 0.0]}
(sim, cfg, [-5.0, 0.0, 0.0], [{normal: [1, 0, 0], deflector: false}]) => {velocity: [-0.5, 0.0, 0.0]}
```

```test deflector-splits
with cfg = {glide_max_impact_angle_deg: 45.0}
with sim = {velocity: [0.0, 0.0, -0.5]}
(sim, cfg, [-4.0, 0.0, -3.0], [{normal: [1, 0, 0], deflector: true}]) => {velocity: [0.0, 0.0, -4.5]}
```

```test floor-hit-ignored
with sim = {velocity: [1.0, 0.0, 0.0]}
(sim, cfg, [-20.0, 0.0, 0.0], [{normal: [0, 1, 0], deflector: false}]) => {velocity: [1.0, 0.0, 0.0]}
```

## Implementation

Early-outs in order: no collisions; pre-impact speed under 0.5 (too slow to
care); post-slide kept ≥ 98% of pre (nothing was eaten); no wall-ish
normal among the collisions; head-on without deflector; slide vector under
0.05 (perfectly axial hit — nothing to redirect along). The deflector
exists because capsule-vs-edge contact normals always read head-on — a
pointed obstacle would otherwise stop dead-center hits the map intends to
split. Epsilons (0.5 / 0.98 / 0.05) are structural, not config. The
head-on threshold compares |pre_dir·normal| against
`sin(glide_max_impact_angle_deg)` — angle measured from the surface plane,
not the normal.
