# match_host.gd

## Function

Authoritative match simulation driver (DESIGN.md §20.2, stage N1). Lives as
a child of `Net` (node name "MatchHost") on whichever process owns the
truth: a per-match dedicated child server (`child_mode`, first-to-N, reports
and exits) or a LAN listen-server host (endless, dynamic peers; the host's
own LOCAL body simulates itself and needs nothing from this node). For each
remote client's DRIVEN body it pops that client's queued cmds and writes
them onto the body every tick, then sends state snapshots back.

## Interface

- `class_name MatchHost extends Node`. Created and configured only by
  `Net._attach_match_host` — fields set before add: `win_kills` (0 =
  endless LAN; >0 = first-to-N lobby duel), `child_mode` (forfeit on
  disconnect, quit after).
- Called by Net: `queue_cmd(id, c)` (on `_client_cmd` rpc arrival),
  `on_client_gone(id)` (peer disconnect on a match child).
- Called by bodies: `on_damage(victim, attacker_id)` (from the victim's
  `apply_damage`, server side), `on_shot(shooter, side, muzzle, end, result)`.
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
`Net.send_snapshot(id, ack, capture_state(), others)` where `others` is
every *other* body's `render_state` row.

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
