# main_menu.gd

## Function

Entry menu logic: play solo, duel the practice AI (with a bot-loadout
picker), host a LAN game, join one by IP, or join a dedicated lobby
server with a username. The menu only collects the choice — all
networking lives in the `Net` autoload.

## Interface

- Script of `main_menu.tscn` root. No exports, no signals out.
- Calls: `get_tree().change_scene_to_file` with `ARENA` (solo corridor) or
  `PARKOUR` (parkour track), `Net.host()`,
  `BotController.pending_loadout = 0/1/2` + `ARENA` (`_start_practice`,
  from the AI-loadout picker buttons; DUEL VS AI itself only toggles the
  `AiLoadoutRow` visibility — the arena's `PracticeSpawner` consumes the
  static and spawns the bot),
  `Net.join(ip)` (blank IP field defaults to 127.0.0.1; Enter in the field
  submits), `Net.join_lobby(ip, username)` (JOIN SERVER row; blank name →
  "player", blank IP → `Net.DEFAULT_SERVER` (play.airfuel-game.com, also the
  field's placeholder), Enter in the server-IP field submits).
- Persists the last username + server IP to `user://settings.cfg`
  (`[lobby] name/ip`) and prefills them on launch.
- Shows the build version in `VersionLabel` (bottom-right): reads
  `application/config/version` — "dev" in-repo shows verbatim, a
  CI-stamped release number gets a "v" prefix ("v0.4.0"). Playtest use:
  "which build are you on?" (release CI is
  `.github/workflows/release.yml`).
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

- Node paths `VBox/SoloButton`, `VBox/DuelAiButton`, `VBox/AiLoadoutRow`
  (+ its `RailRailButton`/`RailSwordButton`/`SwordSwordButton`),
  `VBox/ParkourButton`, `VBox/HostButton`,
  `VBox/JoinRow/IpEdit`, `VBox/JoinRow/JoinButton`, `VBox/ServerRow/NameEdit`,
  `VBox/ServerRow/ServerIpEdit`, `VBox/ServerRow/JoinServerButton`, and
  `VBox/ErrorLabel` are the contract with the scene.
- Solo AND the practice duel must stay pure scene changes — no Net
  involvement, so offline play never depends on networking code.
- Picker button order must match `AirfuelPlayer.LOADOUTS` indices
  (0 rail+rail, 1 rail+sword, 2 sword+sword).
