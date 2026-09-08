---
name: sidecar-check
description: Verify every Godot file's sidecar doc (<file>.md) is present and correct — Interface matches the actual exports/node paths/actions, Assertions still hold in code, Implementation describes what the file really does. Use after any change to a .gd/.tscn/.tres/project.godot file, before ending a turn that touched game/, when asked to check/audit/sync sidecars or docs, or when a hook reminder mentions sidecars.
---

# sidecar-check

Confirms the sidecar-doc convention (see repo `CLAUDE.md`): every Godot file
in `game/` is paired with `<filename>.md` containing four sections —
Function, Interface, Implementation, Assertions — and those sections are
**true**, not just present.

## Procedure

### 1. Deterministic pre-pass

Run `.claude/skills/sidecar-check/check_pairs.sh` (repo-root relative). It
reports MISSING, STALE? (mtime-based hint only), and ORPHAN entries, and
lists all pairs. Exit 1 means structural problems exist.

### 2. Scope the semantic check

- If specific files were just edited this session, check those pairs plus any
  the pre-pass flagged.
- If invoked as a standalone audit (`/sidecar-check` with no context), check
  **every** pair.

### 3. Verify each pair (read both files, compare claim-by-claim)

The sidecar must have all four sections. Then per section:

- **Interface** — every claim must be verifiable in the file: `class_name`,
  exports and their types, public fields/methods other files rely on, node
  names/paths and scene hierarchy, groups, consumed input actions, signals.
  Also check the reverse: interface surface that *exists* in the file but is
  missing from the doc (new exports, new public methods, renamed nodes).
- **Assertions** — each invariant must actually hold in the current code.
  Examples from this repo: fuel bounded by `fuel_max` with all-or-nothing
  spends; dismount is the only in-play fuel refill; wall probes reject
  `|normal.y| > 0.4`; CSG geometry keeps `use_collision = true`; every
  `MovementConfig` field has a line in `default_tuning.tres`.
- **Implementation** — spot-check that described mechanisms still exist
  (function names, algorithms, tick ordering, magic values it documents).
- **Function** — only wrong if the file's purpose changed; flag, don't nitpick.

Cross-file checks that pure pair-reading misses:
- Input actions named in scripts all exist in `project.godot` (and the
  `project.godot.md` action list matches).
- `movement_config.gd` fields ↔ `default_tuning.tres` lines ↔ any field
  lists in their sidecars.
- Node paths in `@onready` vars ↔ the paired `.tscn` ↔ both sidecars.

### 4. Resolve findings

- **Sidecar wrong, code right** → fix the sidecar. This is the common case.
- **Code violates a documented Assertion** → do NOT silently edit either
  side. The assertion is a spec; report the violation to the user as a likely
  bug and ask which side is right (unless the same session deliberately
  changed that behavior — then update the assertion and say so).
- **Missing sidecar** → write it (four sections, follow existing sidecars'
  style). **Orphan** → delete it, or flag if deletion looks accidental.

### 5. Report

End with a compact per-file verdict list: `OK`, `FIXED (what)`, or
`VIOLATION (what, needs user decision)`. If everything was already correct,
one line saying so is enough.
