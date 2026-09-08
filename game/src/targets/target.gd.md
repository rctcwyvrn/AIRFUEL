# target.gd

## Function

Stationary practice dummy for roadmap Step 2 ("railgun against a stationary
target"). Carries the uniform-HP rule (DESIGN.md 9): 2 HP, so body shots
two-shot it and a headshot one-shots it. Self-respawns so range practice
never stalls.

## Interface

- `class_name TargetDummy extends Node3D`; exports `max_hp`, `respawn_delay`.
- `take_hit(damage: int) -> bool` — applies damage, returns true iff the hit
  killed. Called by `player.gd._fire_rail`, which computes damage from the
  hit zone; the target itself is zone-agnostic.
- Expects children `Body` and `Head` (StaticBody3D) — see `target.tscn.md`.

## Implementation

Hit feedback is a scale-punch tween (1.2 → 1.0). Death hides the whole node
and zeroes both bodies' `collision_layer` so rays pass through the corpse,
then a timer restores hp/visibility/collision **to layer 2** (the
shootable-but-not-walkable layer — never 1). `take_hit` on a dead target
returns false (guards a ray racing the death frame).

## Assertions

- HP semantics stay 2/1/2-damage-head — the matrix is design-fixed (9.2).
- Dead targets must be ray-transparent (collision_layer 0 on both zones) and
  must always come back; a permanently dead range target is a bug.
- Zone knowledge (head vs body damage) belongs to the shooter, not here.
