# match_host.gd

## Function

Authoritative match simulation driver (DESIGN.md §20.2, stages N1 + N2).
Lives as a child of `Net` (node name "MatchHost") on whichever process owns
the truth: a per-match dedicated child server (`child_mode`, first-to-N,
reports and exits) or a LAN listen-server host (endless, dynamic peers; the
host's own LOCAL body simulates itself and needs nothing from this node).
For each remote client's DRIVEN body it pops that client's queued cmds and
writes them onto the body every tick, then sends state snapshots back. It
also owns server-side rewind lag compensation (stage N2): a per-body
position history lets hits be evaluated at the victim's position as the
shooter's client had rendered it.

## Interface

- `class_name MatchHost extends Node`. Created and configured only by
  `Net._attach_match_host` — fields set before add: `win_kills` (0 =
  endless LAN; >0 = first-to-N lobby duel), `child_mode` (forfeit on
  disconnect, quit after).
- Called by Net: `queue_cmd(id, c)` (on `_client_cmd` rpc arrival),
  `on_client_gone(id)` (peer disconnect on a match child).
- Called by bodies: `on_damage(victim, attacker_id)` (from the victim's
  `apply_damage`, server side), `on_shot(shooter, side, muzzle, end, result)`.
- Lag-compensated hit queries (server side): `eval_rail_hit(shooter, from,
  dir, max_range)` → `{end: Vector3, victim: AirfuelPlayer or null}` (the
  rail's authoritative hitscan), `rewound_position(victim, shooter)` (the
  sword's reach check).
- `end_match(winner_id, forfeit)` — also called by Net's max-duration timer
  with `(0, false)` = draw.
- `kills: Dictionary` (peer id → kills), read via `Net.broadcast_kill` /
  `finish_match` payloads.
- Consts: `CMD_QUEUE_MAX` 4, `SNAPSHOT_INTERVAL` 2 ticks (120 Hz sim →
  60 Hz snapshots).

## Implementation

**Priority −1.** `_ready` sets `process_physics_priority = -1`, so this
node's `_physics_process` runs before every body's — queued cmds are applied
to DRIVEN bodies *before* they simulate the tick, and `_acks[id]` records
the applied cmd's tick (`c[0]`).

**Snapshot correctness.** `_send_snapshots` runs at the *start* of
`_physics_process`, before that tick's cmds are applied. So a snapshot sent
at the top of tick T+1 captures exactly the post-tick-T state, paired with
ack = the last cmd tick applied through T — precisely the (tick, state)
pair the client's prediction replay (`on_server_snapshot`) needs. Sending
at the end of the same tick instead would be equivalent; sending after
applying the next cmd would be off by one.

**Tick labeling (rewind ⇄ snapshot agreement).** `_record_history` and
`_send_snapshots` both run at handler start, *pre*-increment of
`_tick_count`: the state visible there is labeled server tick `_tick_count`,
recorded into `_pos_history` under that key, and stamped onto the outgoing
snapshot as that same tick. So the tick a client later echoes back as
`seen_server_tick` ("what I had rendered when I pulled the trigger")
indexes `_pos_history` exactly — no off-by-one between what a client saw
and what the rewind reproduces.

**Rewind history (§20.2 N2).** `_pos_history` is a per-peer-id
{server tick → Vector3 global_position} ring, recorded each tick for every
`sim_active()` body and pruned past `_rewind_window_ticks()` — the window
comes from `Net.rewind_ms()` (config `rewind_max_ms`, or the `--rewind-ms`
test override; 0 ms = zero window = rewind effectively off), converted as
`ceil(ms / 1000 × physics_ticks_per_second)` ticks.

**Rewind tick.** `_rewind_tick_for(shooter)`: a LOCAL shooter (the LAN
host — zero latency, sees the present) or one that has never echoed a
snapshot (`seen_server_tick == 0`) gets `_tick_count` — no rewind.
Otherwise the shooter's `seen_server_tick`, clamped to
[`_tick_count − window`, `_tick_count`] so a laggy (or lying) client can't
reach further into the past than the window allows.
`rewound_position(victim, shooter)` reads the victim's history at that
tick, falling back to the current position when history is missing.

**`eval_rail_hit`.** Lag-compensated rail hitscan, split in two so no
physics body ever moves mid-tick: the *static world* is raycast at its live
state (mask 1 — walls don't move, so live occlusion is correct), while
*player victims* are tested analytically as capsules (`_ray_capsule_hit`:
cylinder quadratic plus sphere end caps, entry distance or −1) at their
REWOUND positions, capsule height/radius read from each victim's
`CollisionShape3D` at runtime so hitboxes can't drift from the scene.
Skips the shooter, non-`sim_active()` bodies, and `ghost_controlled` ones;
nearest of wall vs victims wins. When a hit actually rewound
(`rewind_tick != _tick_count`) it logs "rewound hit" with the tick and ms
delta — the observable for A/B-testing lag compensation. Avoiding
physics-server mutation entirely (vs. the classic move-bodies-back /
raycast / restore dance) sidesteps every mid-tick sync hazard.

**Snapshot payload.** Stamped with the server tick (see tick labeling) and
`others` is packed as `[id: int, row]` pairs — the peer id must ride as a
real int, because 10-digit ENet peer ids don't survive a float32 round trip
(this shipped as a real bug: ids corrupted inside a PackedFloat32Array
row).

**Cmd queue.** `queue_cmd` rejects undersized cmds and stale/rewound ticks
(`c[0]` ≤ last queued; unreliable_ordered transport already drops most).
Backlog is capped at `CMD_QUEUE_MAX` by dropping the oldest cmd — but its
one-shot flags field (`c[4]`) is OR-ed into the new front of the queue, so
a queued jump/fire/dash press survives the drop instead of vanishing.

**Loss coasting.** `_pop_cmd` on an empty queue duplicates the last applied
cmd with `c[4]` zeroed: held directional input (`move`, `vert`) and view
angles coast through a packet gap, while flags — which are all one-shots —
are stripped so a press can't repeat.

**Snapshots.** Per DRIVEN body only (a LOCAL host body has no client):
`Net.send_snapshot(id, _tick_count, ack, capture_state(), others)` where
`others` is every *other* body's `[id, render_state()]` pair.

**Kill flow.** `on_damage` broadcasts the damage event; at hp ≤ 0 it scores
the attacker, respawns **both** duelists (design §9: kills reset the
round), broadcasts the kill, and — if `win_kills > 0` and the attacker
reached it — ends the match.

**Match end.** `end_match` is idempotent (`_ending`); it stops its own
physics *and* freezes every body (`set_physics_process(false)`) — a pending
rail charge resolving after the clients leave would fire events into their
closed channels — then hands off to `Net.finish_match` (rpc both clients,
2 s linger, quit). `on_client_gone`: child mode only, a mid-match
disconnect forfeits to the surviving player.

## Assertions

- `process_physics_priority = -1` must survive: cmd application must precede
  body simulation within the same physics tick, and snapshots must be sent
  before that tick's cmds are applied (state = post-previous-tick).
- Coasted cmds never carry a one-shot flag; dropped queue entries never lose
  one (flags are OR-carried forward).
- This node exists only on the simulating process — `Net.match_host` is
  non-null exactly where a MatchHost lives.
- `end_match` freezes all bodies before (or with) the final events; nothing
  may un-freeze them afterward.
- Stale/rewound cmd ticks are rejected — `_acks` must be monotonic per peer
  or prediction replay breaks.
- Peer ids never ride inside a `PackedFloat32Array` — float32 corrupts
  10-digit ENet peer ids. Snapshot `others` rows travel as `[id: int, row]`
  pairs for exactly this reason.
- `_record_history` and the snapshot tick stamp both happen at handler
  start, pre-increment of `_tick_count` — history keys and snapshot tick
  labels must stay the same numbering, or a client's echoed
  `seen_server_tick` indexes the wrong position.
- `eval_rail_hit` never mutates physics state or moves a body — victims are
  tested analytically at rewound positions; only the static world (mask 1)
  is raycast, at live state.
- LOCAL shooters and shooters with `seen_server_tick == 0` are never
  rewound, and no rewind ever exceeds the `Net.rewind_ms()` window.
