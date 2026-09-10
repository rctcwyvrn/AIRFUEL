# player_state.gd

## Function

Rollback-state codec for `AirfuelPlayer` (DESIGN.md §20.2 stage N1):
everything a `_simulate()` tick's outcome depends on, packed as a
fixed-layout `PackedFloat32Array`. The server captures post-tick to build
snapshots; a predicting client captures after every tick and, on a
misprediction, restores the server's state and replays. `agree()` is the
misprediction test. Also houses the cmd wire codec, whose last slot
carries the client's rewind echo for §20.2 N2 lag compensation.

## Interface

- `class_name PlayerState extends Object` — all-static codec, never
  instanced.
- `const SIZE := 42` — every array produced/consumed here has exactly this
  length.
- `static capture(p: CharacterBody3D) -> PackedFloat32Array` — snapshot of
  the player's full sim state.
- `static restore(p: CharacterBody3D, s: PackedFloat32Array) -> void` —
  writes a captured state back onto a body.
- `static agree(a, b) -> bool` — do a predicted state and the server's
  state match closely enough for the prediction to stand?
- `const CMD_SIZE := 8` — the cmd wire format:
  `[0] tick, [1-2] move.x/y, [3] vert, [4] flags, [5] yaw, [6] pitch,
  [7] seen_server_tick`.
- `static encode_cmd(p) -> PackedFloat32Array` /
  `static apply_cmd(p, c) -> void` — pack a body's per-tick cmd fields /
  write a cmd onto a body (DRIVEN on the server, or a history entry
  during a reconciliation replay). Flags bit order is
  jump|dash|fireL|fireR|swap|respawn, identical to the TAS tape. Slot
  [7] `seen_server_tick` is the newest server tick the client had
  rendered when it issued the cmd — the echoed rewind target: the
  server-side rewind (§20.2 N2) evaluates this player's shots against
  victims' positions at that tick. `apply_cmd` writes it onto
  `p.seen_server_tick`; view angles are likewise applied directly
  (client-authoritative, never part of captured state).
- Consumers: `player.gd` wraps capture/restore as
  `capture_state()`/`restore_state()`; `_maybe_reconcile` calls `agree`.
  `MatchHost` captures server bodies for snapshots.
- `PENDING_CODES` — the 5 possible pending-fire queue orderings (see
  Implementation).

## Implementation

**Fixed 42-slot layout** (documented in the script header; slot indices are
the format):

| slots | contents |
|---|---|
| 0–2 / 3–5 | position / velocity |
| 6 / 7 | fuel / move state (`MoveState` as float) |
| 8–10 / 11 / 12 | wall normal / wall speed / wallrun time |
| 13–15 / 16 | last wall normal / wall rearm timer |
| 17–20 | ramp grace, dash cd, double jump, wall coyote timers |
| 21–23 / 24 | coyote wall normal / coyote wall speed |
| 25 / 26 / 27 | ground coyote, jump buffer, countdown |
| 28 / 29 | hp / shot gap timer |
| 30–31 / 32 / 33 | sword cooldowns / sword active / sword side (0=L, 1=R) |
| 34 | loadout index |
| 35–37 / 38–40 | arm L / arm R (state, charge, cooldown) |
| 41 | pending-fire queue code |

- **View angles are deliberately absent.** Yaw/pitch are
  client-authoritative and travel with cmds (`encode_cmd`/`apply_cmd`, also housed here);
  restoring them from a snapshot would yank the player's mouse.
- **Pending-fire queue encoding**: `pending_arms` is an ordered FIFO
  (press order matters for the dual-rail gap), but with only two arms
  there are exactly 5 possible queues — `[]`, `[L]`, `[R]`, `[L,R]`,
  `[R,L]` — so slot 41 is just the index into `PENDING_CODES`.
  `_encode_pending` uses `maxi(0, find(...))` so an unrepresentable queue
  degrades to empty instead of crashing; `_restore_pending` clamps the
  code before indexing.
- **`restore` ordering is load-bearing**: the loadout is applied first
  (via `set_loadout`, only when it differs — it resets arms, clears
  `pending_arms`, zeroes sword cds, and swaps visuals), *then* the sword,
  arm (`state`/`charge`/`cooldown` written directly onto the RailArm
  nodes), and pending slots overwrite those side effects with the captured
  values. `move_locked` is not stored — it's derived, recomputed from
  `is_locking()` at the end of restore.
- **`agree` epsilons**: analog fields tolerate cross-machine float drift —
  position ≤ 0.02 m, velocity ≤ 0.1, fuel ≤ 0.5, countdown ≤ 0.1.
  Discrete fields must match exactly: move state (7), hp (28), loadout
  (34), both arm states (35, 38), pending code (41). A size mismatch
  (either side not `SIZE`, e.g. no history entry for the acked tick)
  counts as disagreement, forcing a rewind-and-replay.

## Assertions

- `SIZE` and the slot meanings are a shared format between server and
  client (snapshots on the wire, per-tick history compared index-by-index
  in `agree`): never reorder or repurpose slots — append and bump `SIZE`.
  The same rule holds for the cmd layout and `CMD_SIZE`.
- Any new field that `_simulate()`'s outcome depends on MUST be added to
  `capture`/`restore` (and to `agree` if its divergence matters);
  a missing field is a silent desync bug.
- No view angles (yaw/pitch/head rotation) may ever be added to the state —
  they belong to the cmd stream.
- `restore` must leave a body that continues exactly as the captured body
  would have: `set_loadout` side effects run before the arm/sword/pending
  slots are written, and derived state (`move_locked`) is recomputed, not
  stored.
- `agree` returns false on any size mismatch — never index past bounds,
  never treat a missing prediction as agreement.
- Epsilons are for float drift only: discrete slots (states, hp, loadout,
  pending) always compare exact.
