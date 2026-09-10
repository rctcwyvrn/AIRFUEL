# player_trails.gd

## Function

Render-side trail cosmetics for one player body, split out of `player.gd`
(1200-line lint cap): the orange flight-path line (DESIGN.md §17 readability
of movement) and the strong blue sword-lunge ribbon (§8.2 — the lunge tell,
2026-09-10). Pure visuals: nothing here may read anything but render state
or ever affect simulation.

## Interface

- `class_name PlayerTrails extends Node` — created in code by
  `player.gd._ready()` (`_trails = PlayerTrails.new(); add_child(...)`);
  no scene file, no exports.
- Expects its **parent** to be the player body (read via `get_parent()` as
  `CharacterBody3D`); reads only `global_position` and `sword_active` from
  it, dynamically typed like `PlayerState` does (avoids a cyclic
  class_name reference to `AirfuelPlayer`).
- `clear()` — respawn hook, called by `player.gd._respawn()`: drops the
  flight-path history so the line never connects across a teleport.
- Calls `PlayerFx.spawn_sword_trail` for ribbon segments and
  `PlayerFx.play_slash_sound` on the lunge's rising edge.

## Implementation

- Runs in `_process` on every body that renders (LOCAL, PREDICTED, REPLICA
  — replicas get `sword_active` via the 13-float render row —, DRIVEN on a
  LAN host's screen, the TAS ghost). On the headless server `_ready`
  detects `DisplayServer.get_name() == "headless"` and disables processing
  entirely — no meshes are ever built there.
- **Flight line** (`_update_trail_line`, verbatim from the old
  `player.gd` version): 2 m position samples into a rolling 150-point /
  4 s window, rebuilt every frame as an ImmediateMesh LINE_STRIP on a
  `top_level` MeshInstance3D (identity transform — points are world
  space), vertex-color orange with alpha ramping toward the tail.
- **Sword ribbon** (`_update_sword_trail`): while the parent's
  `sword_active > 0`, drop a `PlayerFx.spawn_sword_trail` segment (parented
  beside the player) every 0.4 m of travel at chest height (+0.7); the
  first frame of a lunge only anchors the start point and plays the slash
  activation sound (§16) — the same rising edge for every rendered role, so
  an opponent's lunge is audible exactly when its ribbon starts.
  `_sword_live` latches so each lunge starts a fresh anchor instead of
  connecting to the previous lunge's end.

## Assertions

- Pure visuals: must never write to the parent player or influence a
  tick's outcome — prediction/replay correctness assumes trails are
  render-only.
- Headless stays inert: `set_process(false)` path must survive edits (the
  match server runs DRIVEN bodies with `_process` enabled otherwise).
- The line-strip mesh needs ≥ 2 points before `surface_begin` — a 1-point
  strip is a render error.
- `clear()` keeps getting called from `_respawn`, or teleports draw a
  giant straight line across the map.
