# project.godot

## Function

Godot 4.6 project configuration for the Step 1 prototype.

## Interface

- Main scene: `res://maps/graybox_corridor.tscn`.
- Input actions defined here and consumed by `player.gd`:
  `move_forward/back/left/right` (WASD), `jump` (Space), `dash` (Shift),
  `down_dash` (Ctrl and C), `respawn` (R). All use `physical_keycode`
  (layout-independent). `ui_cancel` (Esc) is the built-in default.
- `physics/common/physics_ticks_per_second = 120`.

## Implementation

120 Hz physics because the movement ceiling (~55 m/s terminal) makes 60 Hz
tunneling and wall-probe misses likelier; the controller does all its work in
`_physics_process`, so this is also the input sampling rate for movement.
Window 1600×900. `config/features` says 4.6 — opening in another 4.x minor
just warns.

## Assertions

- New abilities get a named action here, not hard-coded keycodes in scripts.
- Renaming an action must touch every `Input.is_action_*` / `Input.get_vector`
  call in `game/src/` (grep for the action string).
- If `physics_ticks_per_second` changes, re-test wallrun attach/maintain — the
  probe distances in `default_tuning.tres` were tuned against 120 Hz.
