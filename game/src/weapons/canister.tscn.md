# canister.tscn

## Function

The physical spent canister ejected on every rail shot.

## Interface

Root `Canister` (RigidBody3D, `canister.gd`). Instanced only by `player.gd`
(preloaded `CANISTER` const), which positions it and sets velocities.

## Implementation

Small brass-colored box (0.06×0.06×0.18) with matching box collision on
default layers, so it tumbles off corridor geometry. Deliberately tiny scene
— feel polish (bounce sound, glow) belongs here later.

## Assertions

- Root must stay a RigidBody3D — the spawner casts to it and sets
  `linear_velocity`/`angular_velocity`.
- Keep collision on default layer 1 so it lands on CSG geometry.
