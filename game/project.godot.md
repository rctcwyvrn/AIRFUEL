# project.godot

## Function

Godot project configuration for the Steps 1+2 prototype. The `features` tag
is 4.7, matching the pinned toolchain (shell.nix: godot 4.7.2-stable;
docker/Dockerfile: `GODOT_VERSION=4.7.2` — keep all three in step).

## Interface

- Main scene: `res://src/menu/main_menu.tscn` (menu → corridor).
- Runtime/window icon: `res://icon.svg` (orange `>>>` chevrons — the brand
  mark, matching `icon.ico` used by the Windows export preset). Boot splash
  background is the identity dark grey (#16181C).
- Autoload: `Net` (`src/net/network.gd`) — server-authoritative multiplayer
  (§20.2 N1): LAN listen server, dedicated lobby, and per-match child
  servers; inert without net user args
  (`--server`/`--client`/`--lobby`/`--dedicated`/`--match-server`).
- Input actions defined here and consumed by `player.gd` (`hud.gd`'s
  controls-hint widget polls the same action names to light up keys):
  `move_forward/back/left/right` (WASD), `down_dash` (Q),
  `jump` (Space), `dash` (Shift, combines with held direction keys),
  `fire_left` (mouse left), `fire_right` (mouse right), `swap_loadout`
  (Tab, cycles the three 8.3 loadouts), `respawn` (T — moved off R, too close to E), `record` (F5, TAS tape). Keys
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
