# main_menu.tscn

## Function

The game's main scene: title + four ways in (solo / parkour / host or
join-by-IP LAN / join a lobby server with a username).

## Interface

- Root `MainMenu` (full-rect Control, `main_menu.gd`).
- Children the script requires: `VBox/SoloButton`, `VBox/ParkourButton`,
  `VBox/HostButton`,
  `VBox/JoinRow/IpEdit` (LineEdit), `VBox/JoinRow/JoinButton`,
  `VBox/ServerRow/NameEdit` + `ServerIpEdit` (LineEdits) +
  `JoinServerButton` (the dedicated-lobby entry), `VBox/ErrorLabel`
  (hidden; the script drives it — grey connecting status / red failures,
  autowrapped), and `VersionLabel` (bottom-right corner grey Label,
  in-scene text "dev"; `_ready` overwrites it with the build version from
  `application/config/version` — "v0.4.0" on CI-stamped release builds).

- `ControlsLabel` (Label, left side of the screen, outside `VBox`): static
  controls reference (WASD/Space/Q/Shift/LMB-RMB/Tab/T/Esc) added
  2026-09-10; purely informational, never referenced by the script.

## Implementation

Dark full-screen ColorRect (#16181C) + centered VBoxContainer, styled by an
inline Theme: grey StyleBoxFlat buttons that flip orange (#FF8C1A) on hover
with dark text, orange-underlined LineEdit, orange `>>>` + AIRFUEL title,
grey secondary text. This is the color identity: **orange on dark grey**,
shared with icon.svg/icon.ico, the HUD bars, and the in-world beam/cylinder
orange. The hint label walks through LAN setup (host on one machine, find
the local IP via ipconfig, enter it on the other) so joining doesn't
require reading code.

## Assertions

- This scene must never capture the mouse; menu is always cursor-driven.
- Keep it dependency-free apart from `Net` — it loads before everything.
