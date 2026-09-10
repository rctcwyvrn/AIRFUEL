# network.gd

## Function

Autoload `Net` — server-authoritative multiplayer (DESIGN.md §20.2, stage
N1). One netcode path everywhere: an authoritative process simulates every
body from per-tick input cmds (a `MatchHost` node driving DRIVEN bodies),
clients predict their own body (PREDICTED) and render opponents as REPLICA
puppets from server snapshots. This replaces the earlier client-authoritative
LAN-trust netcode entirely.

Three topologies:

- **LAN listen server** (`--server` / `--client <ip>`): the host simulates
  everyone; the host's own body is a zero-latency LOCAL; endless scoring.
- **Dedicated lobby** (`--dedicated`, shipped in `docker/`): matchmaker
  **only** — never loads the arena, never simulates. Players register a
  username (`--lobby <ip> --name <n>` → `src/lobby/`), challenge each other,
  and the lobby spawns one child match-server process per duel
  (`OS.create_process`) with a port from a rotating range, handing both
  clients the port + a one-time token.
- **Child match server** (`--match-server --port N --token T --win-kills K`,
  spawned internally): one arena, exactly two token-checked clients,
  first-to-N, then tells both clients, lingers 2 s to flush, and exits.
  Results travel back via the clients; the lobby keeps name-keyed W–L.

Offline play (no CLI args, no menu action) is untouched.

## Interface

- Autoload singleton `Net` (registered in project.godot).
- `Mode { OFFLINE, LAN, LOBBY, DEDICATED, MATCH_CLIENT, MATCH_SERVER }` in
  `mode`; `active` is true in every online mode (player.gd gates key off it).
- Public API: `host()` / `join(ip)` (LAN), `host_dedicated()`,
  `join_lobby(ip, username)`, `leave_lobby()` (full teardown → menu),
  `match_serve(port, token, win_kills)` (child boot), `display_name(id)`
  (lobby username, "P%d" fallback).
- Called by the local PREDICTED body: `send_cmd(c)` every tick. Called by
  MatchHost: `send_snapshot(id, ack, own, others)`, `broadcast_shot(...)`,
  `broadcast_damage(victim, attacker, hp_left)`,
  `broadcast_kill(killer, victim, kills)`,
  `finish_match(winner_id, forfeit, kills)` (winner 0 = draw).
- `match_host: MatchHost` — non-null **exactly** on the simulating process
  (LAN host, match child); everyone else (clients, the dedicated lobby) has
  null.
- Rpc naming: `_`-prefixed rpcs are internal protocol; the two unprefixed
  ones — `request_challenge(target_id)`, `challenge_reply(challenger, accept)`
  — are public because lobby.gd calls them with `.rpc_id(1, …)`.
- State read by others: `players` (peer id → AirfuelPlayer), `scores`
  (server-fed via `_ev_kill`), `last_roster`, `last_match_result`
  `{won, forfeit, text}` (lobby banner), `last_error` (menu),
  `cfg: ServerConfig` (preloaded `default_server.tres`).
- Signals: `kill_reported(killer, victim)`, `roster_updated(arr)`,
  `challenge_received(from_id, from_name)`, `challenge_ended(reason)`
  (declined / timeout / unavailable / withdrawn — withdrawn fires on the
  *target* when an offer expires), `net_error(message)` (also cached in
  `last_error`; a failure may land mid-scene-change).
- CLI (after `--`): the mode flags above, plus dev flags `--autoduel`
  (auto challenge/accept + autofire), `--fake-lag <ms>` (client-side
  artificial round-trip latency), `--spawn-gap <m>` (LOS test spawns,
  forwarded by the lobby to its children).
- Consts: `PORT` 27555 (lobby and LAN), `MAX_PEERS` 8 (LAN cap only — the
  lobby cap is `cfg.max_peers`), `DEFAULT_SERVER` play.airfuel-game.com for
  a blank JOIN SERVER field / bare `--lobby` — **must stay a DNS-only
  (grey-cloud) record**; Cloudflare's proxy can't carry the game's UDP (the
  bare domain is Proxied and serves the homepage).

## Implementation

**LAN listen server.** `host()` loads the arena, binds udp/27555, attaches a
MatchHost (`win_kills` 0 = endless, `child_mode` false), and spawns its own
body as LOCAL. `_on_peer_connected` replays the roster to the newcomer via
`_spawn_remote.rpc_id` using stored `_spawn_indices`, broadcasts the new
spawn, and spawns the newcomer DRIVEN. On clients `_spawn_remote` picks
PREDICTED for their own id, REPLICA otherwise.

**Dedicated lobby (peer 1).** State: `roster` {peer id → name/wins/losses/
match_id}, `records` {username → W–L} which **survives reconnects and the
match hop because it is name-keyed**, `matches` {mid → a_name, b_name, port,
pid, deadline}, `pending_challenges`. `_register` dedupes names
(`_unique_name`: strip, clamp to `max_name_length`, numeric suffix) and
seeds the roster row from `records`. `request_challenge` rejects self / busy
/ already-pending pairs with `_challenge_result("unavailable")`; accept in
`challenge_reply` → `_start_match`.

`_start_match` allocates a port via `_alloc_match_port` — **rotating, not
first-free**: a just-finished child lingers ~2 s to flush its final events,
so its port must not be re-handed out immediately (bind failure); rotation
only revisits a port after the whole range
[`cfg.match_port_start`, +`match_port_count`) has cycled. It then spawns the
child via `OS.create_process(OS.get_executable_path(), …)` with `--headless`
(plus `--path` when run from the editor), a `randi()` token,
`--win-kills cfg.duel_win_kills`, and `--spawn-gap` if set; records the
match with `deadline = cfg.match_result_timeout`, marks both roster rows
in-match, and `_match_launch.rpc_id`s both duelists. `_process` ticks
challenge timeouts and match deadlines (an expired unreported match →
`_close_match(mid, "")`, freeing the port with no record change).

Results: both returning duelists send `_report_result(winner_name,
loser_name)`; the **first report finds the match (both names in its pair)
and closes it, the duplicate finds nothing and is ignored**. `_close_match`
settles name-keyed records (empty winner = abandoned, records untouched),
refreshes any present roster rows from `records`, frees the port, and
re-broadcasts the roster.

`_broadcast_roster` sends per-registrant `rpc_id` filtered to **live,
NOT-in-match** peers: duelists drop their lobby connection the moment
`_match_launch` lands, so sending them roster updates races their closed
channel (ENet send errors); they get a fresh roster when they return and
re-register. `_on_lobby_peer_disconnected` treats a matched player's
disconnect as expected (they hopped); the match record carries their *name*
until the result comes back.

**Child match server.** `match_serve` binds the given port (cap 2), sets
`match_token`, attaches a MatchHost (`child_mode` true), and arms two
timers: hello (`cfg.match_hello_timeout` — nobody showed → quit) and
max-duration (`cfg.match_max_seconds` — `match_host.end_match(0, false)`,
the stalemate-guard draw). `_hello(token, username)` must be each client's
first rpc: a bad token, or any connection after the match started (a stray
client pointed at a recycled port), is `disconnect_peer`ed so it fails fast.
Two valid hellos → `_begin_child_match`: ids sorted so the **lower peer id
deterministically gets side 0 (−z)**, `_begin_match.rpc_id` to both with
(ids, names, spawn_gap), arena load, both bodies spawned DRIVEN, then
`_respawn()` on both for the 3-2-1 countdown. On a decision `finish_match`
rpcs `_ev_match_over` to live clients, then a **2 s linger timer → quit**
(lets the final reliable events flush). `_on_peer_disconnected` in this mode
skips the despawn relay (see mitigations) and forwards to
`match_host.on_client_gone` (forfeit).

**Client match flow.** `_match_launch(port, token, opponent)` swaps the ENet
peer to `lobby_address:port` (mode MATCH_CLIENT); on connect it sends
`_hello.rpc_id(1, token, my_name)`. `_begin_match` mirrors names, zeroes
`scores`, loads the arena, and spawns self PREDICTED / opponent REPLICA in
the server's side order. Duel runs on the cmd/snapshot + event paths below.
`_ev_match_over` builds the banner text into `last_match_result`, stashes
`_pending_report` (winner/loser **by name**; none on a draw), and
`_return_to_lobby`: free bodies, clear match state, reset `_autoduel_sent`,
drop to OfflineMultiplayerPeer, then `join_lobby(lobby_address, my_name)` —
whose connected handler re-`_register`s and delivers `_pending_report` via
`_report_result.rpc_id(1, …)`. `server_disconnected` while MATCH_CLIENT also
just returns to the lobby (normal after `_ev_match_over` — the child exits;
anything earlier is a crash, same destination).

**Cmd / snapshot plumbing.** `send_cmd` → `_client_cmd` rpc (any_peer,
**unreliable_ordered**) → `match_host.queue_cmd(sender_id, cmd)` on the
simulating process. `send_snapshot` (per remote client, from MatchHost) →
`_snapshot` (authority, unreliable_ordered) → `_apply_snapshot`: the `own`
row goes to the local body's `on_server_snapshot(ack, own)` (PREDICTED
reconciliation), each `others` row to `apply_replica` on bodies that are
actually REPLICA (guard drops rows for anything else).

**Event fan-out.** `broadcast_shot/damage/kill` and `finish_match` run on
the simulating process and rpc `_ev_*` (reliable) to `_client_peer_ids()`:
DRIVEN bodies whose peer id is still in `multiplayer.get_peers()`. The
filter exists because DRIVEN bodies can outlive their client for a beat
(e.g. a pending charge resolving right after match end) and events aimed at
a dropped peer just spam ENet send errors. `_host_plays()` (LAN host, also a
player) additionally handles each event locally by direct call — no
self-rpc. `_handle_shot`: own id → `shot_fired` (authoritative hitmarker;
the beam was predicted), REPLICA shooter → `_spawn_beam` opponent fx (a
LOCAL/DRIVEN shooter drew its own). `_handle_damage`: only the victim
reacts, via the body's own `on_net_damage(attacker, hp_left)` (which syncs
hp and emits `damaged`/`died` in-class — signals stay class-internal, no
UNUSED_SIGNAL warning). `_ev_kill` replaces `scores` wholesale and
emits `kill_reported`.

**Dev flags.** `--autoduel`: in `_roster_sync` the highest-id idle peer
challenges the lowest, once per lobby visit (`_autoduel_sent`, **reset in
`_return_to_lobby` so soak runs loop matches endlessly**); `_challenge_offer`
auto-accepts. `--fake-lag <ms>`: half the value on each leg — outgoing cmds
queue in `_lag_out`, incoming snapshots in `_lag_in`, both flushed by wall
clock in `_process` (client roles only: the flush gates on
MATCH_CLIENT / non-host LAN). `--spawn-gap <m>`: the lobby forwards it to
children and `_begin_match` to clients; `_spawn_transform_for_index` then
puts side 1 at the clear −z end, `gap` meters from side 0 and facing it —
line of sight for headless autofire duels.

**Spawn bookkeeping.** `_spawn_player(id, index, role)`: authority set
before `add_child`, transform from `_spawn_transform_for_index` (even index
→ −z end facing +z, odd → +z end facing −z, +8 m lateral per pair; index is
server spawn order, so it's identical everywhere), recorded in
`_spawn_indices` for LAN late-joiner replay. Spawn prints kept.

**Failure paths.** Unchanged pattern: both join paths run `_resolve_or_fail`
first (blocking DNS pre-check — an unresolvable hostname would otherwise
surface as create_client's generic ERR_CANT_CREATE "error 20"); every
failure goes through `_fail` (cache `last_error` + push_error + `net_error`,
codes via `error_string()`); `_teardown_to_menu` frees bodies, resets all
session state including `match_host`, installs OfflineMultiplayerPeer, and
lands on the menu without reloading it if already current (keeps typed
fields + the just-shown error). Teardown from signal lambdas is
`call_deferred`. `_clear_session_signals` purges Net's connections on the
five multiplayer signals before each session and on teardown — a retry
would otherwise stack lambdas and double-fire with stale captured ips.
`_load_arena` swaps scene, then frees the offline `Player` and the
`"target"` dummies (no practice dummies in netplay); peers are created
*after* it, so no spawn rpc can arrive while the menu is still current.

**ENet-noise mitigations + residual race.** The filtered roster sync and
the no-despawn-relay-on-match-children rule remove the *systematic* error
spam when duelists hop connections. One benign race remains: a send can
still hit a channel that closed microseconds earlier (both duelists leaving
a finished match); the engine prints an error, functionally harmless.

## Assertions

- The dedicated lobby (Mode.DEDICATED) never loads the arena, never spawns
  a body, never gains simulation authority — matchmaker bookkeeping + rpc
  relay only.
- Authoritative simulation exists **exactly** where `match_host != null`
  (LAN host, match child) — nowhere else. Damage/kill authority is
  server-side only: clients learn hp and kills exclusively via
  `_ev_damage` / `_ev_kill`.
- Offline (no CLI args, no menu action) stays a zero-cost no-op path:
  `active == false`, Mode.OFFLINE, no peer, no MatchHost.
- Authority is set before `add_child`, identically on every peer; the
  transform passed pre-add IS the spawn (player `_ready` captures it as
  `spawn_transform`) — never move a player post-add expecting
  spawn_transform to follow.
- Event sends go only to `_client_peer_ids()` (live DRIVEN peers) and match
  children never relay despawns — violating either reintroduces the ENet
  error spam.
- W–L records are keyed by **username**, never peer id — they must survive
  the lobby→match→lobby peer hop and reconnects. Both duelists report; the
  first report closes the match, the duplicate must stay a no-op.
- `PORT` (27555) and DEFAULT_SERVER's DNS-only (grey-cloud) requirement
  stand — Cloudflare's proxy can't carry the game's UDP.
- Session signal connections on `multiplayer` are exclusively Net's, and
  `_clear_session_signals` purges them wholesale — if anything else ever
  subscribes to those signals, that helper must become selective.
- Every lobby server-side handler must tolerate stale peers and rpcs from
  vanished clients (roster lookups guarded; `_report_result` ignores
  unmatched names).
