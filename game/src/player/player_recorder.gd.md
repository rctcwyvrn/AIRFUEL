# player_recorder.gd

## Function

TAS tape recording (F5, solo-only instrument), split out of player.gd
2026-09-10: the per-tick tape line, the tape header/restart, and the
start/stop toggle that writes `user://tas/`.

## Interface

- `class_name PlayerRecorder extends Object` — stateless statics over the
  player body (`PlayerState` pattern, params typed `CharacterBody3D`).
  The `recording` flag and `tape_lines: PackedStringArray` buffer live on
  the player.
- `record_tick(p)` — called every rendered LOCAL tick from
  `_physics_process`; no-ops unless `p.recording` and the reset
  countdown has finished (tapes start at GO, like ghost playback).
- `restart_tape(p)` — clears the buffer and writes the versioned header
  (`# airfuel-tas v1 map=… tick_hz=… loadout=…`). Called on record start
  and by `_respawn` while recording — a tape is always one clean
  spawn-to-finish attempt, never a spliced teleport.
- `toggle(p)` — F5 (via `_gather_input`, `not Net.active` only) and
  `finish_run()`: starting respawns the player first (clean spawn
  state), stopping writes `user://tas/run_<datetime>.tas` and prints the
  real filesystem path.

## Implementation

One line per physics tick: absolute yaw/pitch + cmd fields + button
bitmask. Bit order (jump|dash|fireL|fireR|swap|respawn) is shared with
`PlayerState.encode_cmd` — the two encoders must never drift apart.
Toggle-start calls `p._respawn()` while `recording` is still false, so
the respawn's own tape-restart branch is skipped and the header is
written exactly once.

## Assertions

- Tape format is versioned (`# airfuel-tas v1`): change the line schema →
  bump the header and keep `TasGhostController`'s loader backward-aware.
- The flags bit order must stay identical to `PlayerState.encode_cmd`/
  `apply_cmd`.
- Recording is a solo instrument: `toggle` is only reachable offline
  (`not Net.active` gate in `_gather_input`), and `record_tick` only
  runs on the LOCAL path of `_physics_process`.
- Countdown ticks are never recorded — a tape and its ghost replay stay
  tick-aligned from GO.
