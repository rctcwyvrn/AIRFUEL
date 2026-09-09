# kill_zone.gd

## Function

Instant-reset trap under floorless track sections: entering it respawns
the player (with the reset countdown) the moment they drop through where
the floor would have been.

## Interface

- `class_name KillZone extends Area3D`, `collision_mask = 4` (players).
- Calls `AirfuelPlayer._respawn()` on any authority player body. The TAS
  ghost's body is on layer 0, so zones never see it — a desynced ghost
  falls to the global `kill_y` instead, which is fine.

## Implementation

Placed by the track generator: one rotated volume per hallway part and
corner, 6 m below track level, wider than the hallway to catch off-wall
drift. Same pattern as FinishZone.

## Assertions

- Mask stays 4 — widening it to layer 1 would collide-with-world nonsense.
- Zones must sit BELOW wall bottoms, never overlapping playable air.
