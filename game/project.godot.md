# project.godot

## Function

Godot project configuration for the Steps 1+2 prototype. The `features` tag
tracks whichever editor last saved the project (currently 4.7 — Lily's
editor; the nix devshell verify binary is 4.6.1, which warns but runs).

## Interface

- Main scene: `res://src/menu/main_menu.tscn` (menu → corridor).
- Autoload: `Net` (`src/net/network.gd`) — LAN multiplayer; inert without
  `--server`/`--client` user args.
- Input actions defined here and consumed by `player.gd`:
  `move_forward/back/left/right` (WASD), `strafe_down` (Q),
  `jump` (Space), `dash` (Shift, combines with held direction keys),
  `fire_left` (mouse left), `fire_right` (mouse right), `respawn` (T — moved off R, too close to E). Keys
  use `physical_keycode` (layout-independent). `ui_cancel` (Esc) is the
  built-in default.
- `physics/common/physics_ticks_per_second = 120`.

## Implementation

120 Hz physics because the movement ceiling (~55 m/s terminal) makes 60 Hz
tunneling and wall-probe misses likelier; the controller does all its work in
`_physics_process`, so this is also the input sampling rate for movement.
Window 1600×900. The editor rewrites this file on save (header comment,
event formatting, features tag) — hand edits survive but expect churny diffs.

## Assertions

- New abilities get a named action here, not hard-coded keycodes in scripts.
- Renaming an action must touch every `Input.is_action_*` / `Input.get_vector`
  call in `game/src/` (grep for the action string).
- If `physics_ticks_per_second` changes, re-test wallrun attach/maintain — the
  probe distances in `default_tuning.tres` were tuned against 120 Hz.
