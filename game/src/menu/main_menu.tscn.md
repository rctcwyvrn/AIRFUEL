# main_menu.tscn

## Function

The game's main scene: title + three ways in (solo / host / join-by-IP).

## Interface

- Root `MainMenu` (full-rect Control, `main_menu.gd`).
- Children the script requires: `VBox/SoloButton`, `VBox/HostButton`,
  `VBox/JoinRow/IpEdit` (LineEdit), `VBox/JoinRow/JoinButton`.

## Implementation

Dark full-screen ColorRect + centered VBoxContainer. Default Control theme —
deliberately unstyled at prototype stage. The hint label states the port so
LAN debugging doesn't require reading code.

## Assertions

- This scene must never capture the mouse; menu is always cursor-driven.
- Keep it dependency-free apart from `Net` — it loads before everything.
