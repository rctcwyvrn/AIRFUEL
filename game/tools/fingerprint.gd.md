# fingerprint.gd

## Function

Headless trajectory-fingerprint harness: the regression gate that says "a
movement refactor changed nothing." Replays the checked-in parkour TAS tape
(`res://tas/parkour.tas`) through the real movement sim and hashes the
ghost's full rollback state every tick; identical code ⇒ identical SHA-256.
Makes the previously ad-hoc "TAS-ghost trajectory fingerprint" verification
(DESIGN.md §20.2 N1 note) a committed tool.

## Interface

- Root script of `tools/fingerprint.tscn`; run with
  `godot4 --headless --path game res://tools/fingerprint.tscn`.
- Prints exactly one line on success —
  `fingerprint sha256=<hex> ticks=<n>` — then quits 0.
- Quits 1 with a `push_error` if the tape never starts feeding within
  `STARTUP_GRACE_TICKS` (missing/empty tape).
- Baseline hash is checked in at `game/tas/parkour.fingerprint`;
  comparisons are same-machine/same-build only (float codegen may differ
  across machines).
- Depends on: `parkour_track.tscn` node paths `GhostRunner` +
  `GhostRunner/TasController`, `TasGhostController.tape`/`.tick`, and
  `PlayerState.capture()`'s layout (any codec layout change changes the
  hash — re-baseline deliberately when that happens).

## Implementation

Instances the parkour track as a child and reads the ghost through the
`TasController`'s own counters rather than keeping its own clock:
`process_physics_priority = 100` puts the capture after every body's tick
(the controller writes cmds at −1, bodies simulate at 0), and a capture
happens only when `_tas.tick` has advanced past the last captured value —
so spawn-countdown holds contribute nothing and exactly one state row is
hashed per consumed tape row. Hashing is incremental
(`HashingContext.update` per tick, 42 floats → `to_byte_array`), and the
run ends when the tape's final row has been consumed — before the
controller's loop `_restart()` would splice a second lap into the hash.

## Assertions

- One `PlayerState.capture` row hashed per tape row (currently 3805) —
  `ticks=` in the output must equal the loaded tape's row count.
- Capture must stay AFTER body simulation in the tick order
  (`process_physics_priority` > 0).
- The harness must quit before the ghost's loop restart; a second lap in
  the hash makes the fingerprint depend on loop timing.
- No writes to any game state — the harness only reads.
