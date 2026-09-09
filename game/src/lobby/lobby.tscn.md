# lobby.tscn

## Function

Layout for the dedicated-server lobby screen (`lobby.gd`).

## Interface

- Root `Lobby` (full-rect Control, `lobby.gd`).
- Children the script requires: `VBox/RosterBox` (VBoxContainer, rows
  runtime-built), `VBox/ResultLabel` (green, hidden until a match result
  exists), `VBox/ChallengeBox` (HBox, hidden; `ChallengeLabel` +
  `AcceptButton` + `DeclineButton`), `VBox/StatusLabel` (grey, hidden),
  `VBox/LeaveButton`.

## Implementation

Same orange-on-dark-grey identity as `main_menu.tscn`, via the same inline
Theme approach (grey StyleBoxFlat buttons flipping orange on hover, dark
#16181C backdrop) at a smaller button scale for roster rows.

## Assertions

- This scene must never capture the mouse; it is always cursor-driven.
- Keep it dependency-free apart from `Net` — the roster renders from Net
  caches/signals only.
