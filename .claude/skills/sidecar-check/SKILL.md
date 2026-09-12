---
name: sidecar-check
description: Verify every Godot file's sidecar doc (<file>.md) is present and correct — Interface matches the actual exports/node paths/actions, Assertions still hold in code, Implementation describes what the file really does. Use after any change to a .gd/.tscn/.tres/project.godot file, before ending a turn that touched game/, when asked to check/audit/sync sidecars or docs, or when a hook reminder mentions sidecars.
---

# sidecar-check

Confirms the sidecar-doc convention (see repo `CLAUDE.md`): every Godot file
in `game/` is paired with `<filename>.md`, and its content is **true**, not
just present. Two sidecar formats exist:

- **Four-section** (the default): Function, Interface, Implementation,
  Assertions. Used by node scripts, scenes, resources, tools, and facades.
- **`.tr`-style definition spec** (the Trellis-style pilot,
  `game/src/player/movement/`): YAML frontmatter with `name:`, prose, a
  ` ```gd-sig` block, optional ` ```requires`/` ```ensures` labelled
  clauses, named ` ```test` blocks, and an `## Implementation` section.
  Detected by the frontmatter + a `gd-sig` (or `gd-type`) fence. Used by
  per-definition files (one public static function or one data type per
  file).

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

**`.tr`-style spec docs** verify by their own parts:

- **`gd-sig`** — must match the actual static function's name, parameter
  names/types/order, and return type (for `gd-type`: the actual fields).
- **`requires`/`ensures`** — each labelled clause must hold in the code
  (treat like Assertions: code-violates-spec is a finding for the user,
  not a silent edit).
- **`test` blocks** — run them: `godot4 --headless --path game
  res://tools/spec_runner.tscn` (exit 0 = green; cfg is SCHEMA defaults
  from `movement_config.gd`, not `default_tuning.tres`). A failing case
  is drift in whichever side changed last.
- **Prose + `## Implementation`** — same truthfulness bar as
  Function/Implementation below.

**Four-section sidecars** must have all four sections. Then per section:

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
