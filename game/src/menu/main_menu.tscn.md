# main_menu.tscn

## Function

The game's main scene: title + three ways in (solo / host / join-by-IP).

## Interface

- Root `MainMenu` (full-rect Control, `main_menu.gd`).
- Children the script requires: `VBox/SoloButton`, `VBox/ParkourButton`,
  `VBox/HostButton`,
  `VBox/JoinRow/IpEdit` (LineEdit), `VBox/JoinRow/JoinButton`.

## Implementation

Dark full-screen ColorRect (#16181C) + centered VBoxContainer, styled by an
inline Theme: grey StyleBoxFlat buttons that flip orange (#FF8C1A) on hover
with dark text, orange-underlined LineEdit, orange `>>>` + AIRFUEL title,
grey secondary text. This is the color identity: **orange on dark grey**,
shared with icon.svg/icon.ico, the HUD bars, and the in-world beam/cylinder
orange. The hint label states the port so LAN debugging doesn't require
reading code.

## Assertions

- This scene must never capture the mouse; menu is always cursor-driven.
- Keep it dependency-free apart from `Net` — it loads before everything.
