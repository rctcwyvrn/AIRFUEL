# network.gd

## Function

Autoload `Net` — prototype multiplayer in two flavors sharing one
client-authoritative LAN-trust netcode (DESIGN.md §20.2's real architecture
is server-authoritative with rewind; this is NOT that):

- **LAN listen-server** (the original Step-4 precursor): host is a player,
  every peer spawns every body, state is broadcast.
- **Dedicated lobby server** (the §24 Step 3 playtesting instrument, shipped
  in `docker/`): a matchmaker + relay that **never loads the arena and never
  simulates anything**. Players register a username, challenge each other
  from a lobby (`src/lobby/`), and fight private first-to-5 1v1s (§12.2's
  win condition). Concurrent matches are isolated for free: each pair loads
  its OWN local arena and all match traffic is `rpc_id`-targeted, so no
  third peer ever receives it.

## Interface

- Autoload singleton `Net` (registered in project.godot).
- `Mode { OFFLINE, LAN, LOBBY, DEDICATED }` in `mode`; `active` is true in
  every online mode (all of player.gd's gates key off it, unchanged).
- Public API: `host()` / `join(ip)` (LAN, unchanged), `host_dedicated()`,
  `join_lobby(ip, username)`, `leave_lobby()` (full client teardown → menu).
  CLI (after `--`): `--server`, `--client <ip>`, `--dedicated`,
  `--lobby <ip> --name <n>`, `--autoduel` (dev: auto challenge/accept for
  headless smoke tests — highest-id idle peer challenges lowest, once).
- Read by player.gd: `active`, `match_opponent` (nonzero exactly while in a
  lobby match — switches its state/fx sends to `rpc_id` and kill reports to
  `report_match_kill`). Read by the HUD: `players`, `scores`,
  `display_name(id)` (lobby usernames, "P%d" fallback). Read by the lobby
  scene: `last_roster`, `last_match_result`, signals below.
- Signals: `kill_reported(killer, victim)` (HUD feed/banner — emitted by
  LAN `report_kill` and lobby `match_score` alike), `roster_updated(arr)`,
  `challenge_received(from_id, from_name)`, `challenge_ended(reason)`
  (reasons: declined / timeout / unavailable / withdrawn — withdrawn fires
  on the *target* when an offer expires), `net_error(message)` (user-facing
  connection failures; also cached in `last_error` for a menu that isn't
  current yet — the menu consumes and clears it on `_ready`).
- Lobby protocol rpcs (all reliable; server = peer 1): client→server
  `register(name)`, `request_challenge(target_id)`,
  `challenge_reply(challenger_id, accept)`, `report_match_kill(killer_id)`
  (sent by the **victim**, mirroring LAN's flow); server→client
  `roster_sync(arr)`, `challenge_offer(from, name)`,
  `challenge_result(accepted, reason)`, `challenge_withdrawn()`,
  `match_start(opponent_id, opponent_name, side)`,
  `match_score(killer, victim, kills)`, `match_over(winner, forfeit, kills)`.
- `players: Dictionary` (peer id → node): LAN = full roster; lobby match =
  just the pair. Nodes are named `str(peer_id)` and get
  `set_multiplayer_authority(id)` **before** add.
- Config: `cfg: ServerConfig` (`default_server.tres` — duel_win_kills,
  max_peers, challenge_timeout, max_name_length). `MAX_PEERS` const remains
  the legacy LAN cap only.

## Implementation

**LAN** (unchanged): server-driven roster; `_on_peer_connected` sends
existing ids, broadcasts the new one, spawns locally — every peer runs the
same `_spawn_player` so state stays deterministic (spawn prints kept — they
caught the client-camera bug). `_load_arena` swaps scene, frees the offline
`Player` + `"target"` dummies. `_spawn_transform_for_index` alternates ends
(even → −z, odd → +z, +8 m lateral per pair). `report_kill` (any_peer,
call_local) tallies scores on every peer and round-resets the killer's own
player.

**Failure paths** (all flavors): every connection failure — create_server/
create_client error, `connection_failed`, `server_disconnected` (the LAN
client used to quit(); now it errors back to the menu like the lobby) —
goes through `_fail` (cache + push_error + `net_error`) and
`_teardown_to_menu` (free bodies, reset all session state,
`OfflineMultiplayerPeer`, land on the menu without reloading it if it's
already current — preserving typed fields and the just-shown error).
Teardown from inside a signal lambda is `call_deferred`.
`_clear_session_signals` purges Net's connections on the five multiplayer
signals before each session and during teardown — without it, a retry
would stack lambdas and double-fire with stale captured ips.

**Dedicated** (server side, peer 1): `roster` {id → name/wins/losses/
match_id}, `matches` {mid → a/b/kills}, `pending_challenges` with
`challenge_timeout` ticked in `_process` (the only per-frame work; expiry
sends `challenge_result("timeout")` to the challenger and
`challenge_withdrawn` to the target). `register` sanitizes + dedupes names
(`_unique_name`: strip, clamp to max_name_length, numeric suffix).
`request_challenge` rejects self/busy/already-pending pairs with
`challenge_result("unavailable")`. Accept → `_start_match`: sides are
challenger = 0 (−z), challenged = 1 (+z). `report_match_kill` trusts the
victim's report (LAN-trust), bumps kills, and either relays `match_score`
to both or ends the match at `cfg.duel_win_kills`. `_end_match` updates
W–L, notifies both, re-broadcasts the roster; a mid-match disconnect
forfeits to the survivor. The server holds no node state for matches —
score dicts only.

**Lobby client**: `join_lobby` registers on connect and enters
`lobby.tscn`; unlike the LAN client, a lost server returns to the menu
(`leave_lobby`) instead of quitting. `match_start` reuses `_load_arena()`
then spawns exactly the pair via `_spawn_player(id, index)` (index param
added for explicit sides; LAN sites still pass spawn order). `scores` is
server-fed; `match_score` emits `kill_reported` (HUD reuse) and
round-resets the killer's own body. `match_over` stores
`last_match_result`, frees the pair, returns to the lobby scene.

## Assertions

- Authority is set before `add_child`, on every peer identically — late
  authority flips would let two peers simulate one body.
- Offline (`active == false`) must remain a zero-cost no-op path.
- The transform passed pre-add IS the spawn (player `_ready` captures it
  as `spawn_transform` for kill-resets) — never move a player post-add
  expecting spawn_transform to follow.
- The dedicated server must never load the arena, spawn a body, or gain
  any simulation authority — it is bookkeeping + relay only. Match
  isolation depends on this plus rpc_id targeting: adding ANY broadcast
  rpc on the match path leaks one duel into another.
- Every lobby server→client handler must tolerate stale peers (roster
  lookups use `.get` with defaults) — clients can vanish between any two
  rpcs.
- LAN mode gameplay behavior is frozen: lobby changes must not touch the
  `host()`/`join()`/`report_kill`/broadcast-spawn paths. (Deliberate
  exception, 2026-09-09: failure handling — LAN now shares the
  error-to-menu path instead of quitting.)
- Session signal connections on `multiplayer` are exclusively Net's, and
  `_clear_session_signals` purges them wholesale — if anything else ever
  subscribes to those signals, that helper must become selective.
