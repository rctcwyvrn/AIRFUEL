# main_menu.gd

## Function

Entry menu logic: play solo, host a LAN game, or join one by IP. The menu
only collects the choice — all networking lives in the `Net` autoload.

## Interface

- Script of `main_menu.tscn` root. No exports, no signals out.
- Calls: `get_tree().change_scene_to_file(ARENA)` (solo), `Net.host()`,
  `Net.join(ip)` (blank IP field defaults to 127.0.0.1; Enter in the field
  submits).
- Ensures the mouse is visible on entry (the player captures it later).

## Implementation

Buttons wired in `_ready` with lambdas; `ARENA` duplicates the path in
`Net` because the menu also starts solo games without touching Net.

## Assertions

- Node paths `VBox/SoloButton`, `VBox/HostButton`, `VBox/JoinRow/IpEdit`,
  `VBox/JoinRow/JoinButton` are the contract with the scene.
- Solo must stay a pure scene change — no Net involvement, so offline play
  never depends on networking code.
