# server_config.gd

## Function

Schema for dedicated lobby-server tuning. `duel_win_kills` carries the
§12.2 decision: 1v1 duels are **first to 5 kills** (2026-09-09, prototype
tier).

## Interface

- `class_name ServerConfig extends Resource`, pure data.
- Fields: `duel_win_kills` (5), `max_peers` (12 — the lobby cap; the legacy
  LAN cap stays `Net.MAX_PEERS`), `challenge_timeout` (15 s),
  `max_name_length` (16).
- Consumed only by `Net` (`cfg`, preloaded from `default_server.tres`).

## Implementation

Values are read server-side only (clients never gate on them), so a
mismatched client build can't desync match rules.

## Assertions

- Stays a pure Resource; shipping values live in `default_server.tres`
  (overrides-only, same rule as the other tres files).
- No lobby/match literal may appear in `network.gd` — new knobs get a
  field here.
