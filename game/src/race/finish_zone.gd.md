# finish_zone.gd

## Function

The race finish line: an Area3D that stops the local player's run timer
(and auto-saves an in-progress TAS recording) on touch.

## Interface

- `class_name FinishZone extends Area3D`, group `"finish"` (the HUD shows
  the run timer only when a finish zone exists in the scene).
- Calls `AirfuelPlayer.finish_run()` on the first authority, non-ghost
  player body that enters. No exports, no signals out.

## Implementation

Area3D with `collision_mask = 4` (the player layer). Placed by the track
generator just inside the green end wall, spanning the hallway
cross-section.

## Assertions

- Must filter out `ghost_controlled` bodies — the TAS ghost crossing the
  line must never stop your timer or recording.
- Keep it in group `"finish"`; the HUD keys timer visibility off that.
