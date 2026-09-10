# default_server.tres

## Function

The shipping `ServerConfig` values for the dedicated lobby server.

## Interface

Preloaded by `network.gd` as `Net.cfg`. Currently all schema defaults
(first to 5 kills, 12 peers, 15 s challenge timeout, 16-char names, and the
Match Servers group: ports 27600–27619, 60 s hello / 600 s max-duration /
900 s result timeouts).

## Implementation

Overrides-only, like `default_tuning.tres` / `default_combat.tres`: a line
appears here iff it differs from the `server_config.gd` default.

## Assertions

- `duel_win_kills` is a design decision (DESIGN.md §12.2) — changing it is
  a design change, record it there.
