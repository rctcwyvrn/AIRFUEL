# lobby.gd

## Function

The dedicated-server lobby screen (DESIGN.md §24 Step 3 instrument): shows
the roster with session W–L tallies, lets you challenge an idle player,
answers incoming challenges, shows the last match result, and leaves back
to the menu.

## Interface

- Script of `lobby.tscn` root (full-rect Control). Entered/exited only by
  `Net` (`join_lobby` connect and `match_over` both change_scene here;
  LEAVE calls `Net.leave_lobby()`).
- Consumes `Net.roster_updated`, `Net.challenge_received`,
  `Net.challenge_ended`, plus the caches `Net.last_roster` /
  `Net.last_match_result` on entry (so a scene entered after the signals
  fired still renders).
- Sends exactly three rpcs, all to peer 1: `Net.request_challenge`,
  `Net.challenge_reply` — nothing else touches the network.
- Expected children: `VBox/RosterBox` (rows built at runtime),
  `VBox/ResultLabel`, `VBox/ChallengeBox/{ChallengeLabel,AcceptButton,
  DeclineButton}`, `VBox/StatusLabel`, `VBox/LeaveButton`.

## Implementation

Pure view: all state lives in `Net`; `_rebuild` re-creates the roster rows
(HBox: name + "(you)" marker, W–L label, then IN MATCH label / CHALLENGE
button) on every `roster_updated`. `challenger_id` is the only local state
— the pending incoming challenge; "withdrawn" (offer expired server-side)
clears it silently, other `challenge_ended` reasons surface on
StatusLabel. Mouse is made visible on entry (players arrive from a
mouse-captured match).

## Assertions

- View-only: never mutate Net state directly; only the three rpcs above.
- Must render correctly from the caches alone (entering the lobby between
  roster broadcasts is the common case, straight after a match).
- Rows are rebuilt, never patched — stale-row bugs aren't worth the
  optimization at 12 peers.
