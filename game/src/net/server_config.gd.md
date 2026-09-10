# server_config.gd

## Function

Schema for dedicated lobby-server tuning. `duel_win_kills` carries the
§12.2 decision: 1v1 duels are **first to 5 kills** (2026-09-09, prototype
tier).

## Interface

- `class_name ServerConfig extends Resource`, pure data.
- Fields: `duel_win_kills` (5), `max_peers` (12 — the lobby cap; the LAN
  cap stays `Net.MAX_PEERS`), `challenge_timeout` (15 s),
  `max_name_length` (16).
- "Match Servers" export group (per-match child server plumbing):
  `match_port_start` (27600) + `match_port_count` (20) — the udp range
  handed to child servers via `Net._alloc_match_port` (forward/expose the
  whole range `[start, start + count)`); `match_hello_timeout` (60 s —
  child exits if two token-valid clients haven't arrived),
  `match_max_seconds` (600 s — child force-ends a match as a draw, orphan
  guard), `match_result_timeout` (900 s — lobby frees an unreported match
  record and its port).
- "Lag Compensation" export group (§20.2 N2): `rewind_max_ms` (250 ms) —
  server-side rewind window; hits are evaluated at the victim's position up
  to this far in the past (the shooter's rendered view), so it caps how far
  behind a laggy shooter can kill you. 0 disables rewind. Read via
  `Net.rewind_ms()`, where the `--rewind-ms` test override beats it.
- Consumed only by `Net` (`cfg`, preloaded from `default_server.tres`) —
  the lobby process and its match-server children, plus `rewind_max_ms` on
  any simulating process (a LAN listen-server host reads it through
  `Net.rewind_ms()` too).

## Implementation

Values are read server-side only (clients never gate on them), so a
mismatched client build can't desync match rules.

## Assertions

- Stays a pure Resource; shipping values live in `default_server.tres`
  (overrides-only, same rule as the other tres files).
- No lobby/match tunable may appear in `network.gd` — new knobs get a
  field here. (The child's 2 s post-match linger is deliberately hardcoded
  plumbing — it exists to flush final events, not to be tuned.)
