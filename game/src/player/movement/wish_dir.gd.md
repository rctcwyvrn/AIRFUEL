---
name: wish_dir
---

# wish_dir

WASD input to a world-space horizontal wish direction through the body's
yaw basis: `x` strafes along the basis X, forward is `-basis.z` (Godot
convention; input `y` is negative-forward, hence the double negation).
Zero input is zero wish; anything else normalizes, so diagonals aren't
faster.

```gd-sig
wish_dir : (move_input: Vector2, basis: Basis) -> Vector3
```

```requires
yaw-only basis: basis has no roll/pitch (the body yaws; the head pitches)
```

```ensures
unit or zero: result == ZERO or result is normalized
planar: yaw-only basis implies result.y == 0.0
pure: no sim access at all — a value function
```

```test forward
([0, -1], BASIS_IDENTITY) => [0.0, 0.0, -1.0]
```

```test strafe-right
([1, 0], BASIS_IDENTITY) => [1.0, 0.0, 0.0]
```

```test zero
([0, 0], BASIS_IDENTITY) => [0.0, 0.0, 0.0]
```

## Implementation

The only movement definition with no MoveSim parameter — kept as its own
file anyway because the shell zeroes the wish while charge-locked
(`player.gd` computes `wish` once per tick and hands it to the state
moves), so the mapping deserves its own spec. The same formula over the
*camera* basis lives in handle_dashes for the pitched dash.
