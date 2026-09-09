# main_menu.gd

## Function

Entry menu logic: play solo, host a LAN game, join one by IP, or join a
dedicated lobby server with a username. The menu only collects the choice —
all networking lives in the `Net` autoload.

## Interface

- Script of `main_menu.tscn` root. No exports, no signals out.
- Calls: `get_tree().change_scene_to_file` with `ARENA` (solo corridor) or
  `PARKOUR` (parkour track), `Net.host()`,
  `Net.join(ip)` (blank IP field defaults to 127.0.0.1; Enter in the field
  submits), `Net.join_lobby(ip, username)` (JOIN SERVER row; blank name →
  "player", blank IP → `Net.DEFAULT_SERVER` (play.airfuel-game.com, also the
  field's placeholder), Enter in the server-IP field submits).
- Persists the last username + server IP to `user://settings.cfg`
  (`[lobby] name/ip`) and prefills them on launch.
- Connection feedback via `VBox/ErrorLabel`: grey "connecting to <ip>..."
  status on either join click, red failure text from `Net.net_error`; on
  `_ready` it also consumes `Net.last_error` (clearing it) so failures that
  landed while another scene was current (host died mid-lobby/mid-match)
  surface on return to the menu.
- Ensures the mouse is visible on entry (the player captures it later).

## Implementation

Buttons wired in `_ready` with lambdas; `ARENA` duplicates the path in
`Net` because the menu also starts solo games without touching Net.

## Assertions

- Node paths `VBox/SoloButton`, `VBox/ParkourButton`, `VBox/HostButton`,
  `VBox/JoinRow/IpEdit`, `VBox/JoinRow/JoinButton`, `VBox/ServerRow/NameEdit`,
  `VBox/ServerRow/ServerIpEdit`, `VBox/ServerRow/JoinServerButton`, and
  `VBox/ErrorLabel` are the contract with the scene.
- Solo must stay a pure scene change — no Net involvement, so offline play
  never depends on networking code.
