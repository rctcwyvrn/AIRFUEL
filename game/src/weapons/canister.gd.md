# canister.gd

## Function

Despawn timer for the spent-canister prop (DESIGN.md 8.1 bolt action; 17
names canister ejection a load-bearing feedback beat).

## Interface

Script of `canister.tscn` root (RigidBody3D). Export: `lifetime` (s).
Spawner (`player.gd._spawn_canister`) sets position and linear/angular
velocity after instancing.

## Implementation

One `create_timer → queue_free`. Physics does the rest.

## Assertions

- Must always free itself — canisters are fired constantly; leaking them
  degrades long sessions.
- Keep it dumb: no gameplay effects, purely cosmetic.
