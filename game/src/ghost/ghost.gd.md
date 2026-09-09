# ghost.gd

## Function

`TasGhostController` — drives a real `AirfuelPlayer` (its parent, spawned
with `ghost_controlled = true`) through the ACTUAL movement physics by
writing the player's `cmd_*` inputs each tick. Jumps and dashes cost real
fuel, cooldowns apply, gravity is real: the ghost's pace is whatever the
movement system yields, not an animation. Demonstrates a line through the
parkour track; resets with the player.

## Interface

- `class_name TasGhostController extends Node`, child of the ghost player.
- Exports: `waypoints` (baked by the track generator), `tape_path`
  (a `.tas` recording; empty = waypoint autopilot), `turn_rate`
  (rad/s steering cap — human-plausible), `arrive_dist`.
- Connects to the real player's `respawned` signal → both restart.

## Implementation

Two modes. **Tape replay** (when `tape_path` is set): loads a `.tas`
recording (made in-game with F5) and executes it verbatim — absolute
yaw/pitch plus the recorded command fields each tick, looping from spawn
at tape end. This is the true fixed-input TAS; a tape silently assumes
the movement tuning and map it was recorded under. The header's
`loadout=` is applied to the body at start and on every loop/restart —
replays must begin from the recorded loadout, not whatever the ghost
last had. **Waypoint autopilot**
(no tape): the reactive fallback described below — deterministic, but
closed-loop.

`process_physics_priority = -1` so commands are written BEFORE the body's
physics tick consumes them. Playback (tape ticks AND autopilot) holds
while the body's reset countdown runs — replays start at GO like the
recording did. Waypoint chase: rate-limited yaw, near-level
head pitch (dashes are camera-aimed; steep pitch balloons the flight),
hold-W, jump on floor when the line rises or speed drops, double-jump on
fading climbs, dash only below 26 m/s with fuel to spare. A waypoint
counts as reached when close OR passed (behind while near) — orbiting was
the classic failure. 8 s without progress snaps the body back onto the
line at the previous waypoint (velocity zeroed, tank refilled) — a splice,
not a full-track restart.
Fuel is honest: the controller never refuels, so it runs dry and slows —
a wallrun behavior would fix that (Step 3 bot territory).

## Assertions

- Never touch the Input singleton — only the parent's `cmd_*`/rotation.
- Tape format is versioned (`# airfuel-tas v1`): change the line schema →
  bump the header and keep the loader backward-aware.
- Regenerate waypoints whenever the track regenerates.
- The ghost body must stay `ghost_controlled` (camera/HUD/combat all
  key off that flag).
