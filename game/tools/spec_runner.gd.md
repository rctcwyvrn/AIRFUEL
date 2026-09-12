# spec_runner.gd

## Function

Executes the `.tr`-style definition specs: parses every ` ```test` block in
`game/src/player/movement/*.gd.md`, builds the fixtures its `with` lines
describe, calls the paired definition, and compares outcomes. Turns the
pilot's spec tests from aspirational into the movement layer's unit-test
gate (the fingerprint harness remains the integration gate).

## Interface

- Root script of `tools/spec_runner.tscn`; run with
  `godot4 --headless --path game res://tools/spec_runner.tscn`.
- Prints `spec-runner: N cases, F failed, X xfail`; each failure is a
  `push_error` with block#case, field, expected vs got. Exits 0 when all
  green, 1 otherwise. An `xfail`-marked block must fail (a pass is
  reported as XPASS and counts as a failure).
- Spec syntax understood (the contract with the spec docs, also noted in
  `CLAUDE.md`): `with sim = {…}` (unlisted fields keep `MoveSim` defaults),
  `with cfg = {…}` (overrides on `MovementConfig.new()` — **schema
  defaults, not `default_tuning.tres`**), `with probe = fake_probe {…}`
  (every call returns that hit; `fake_probe {}` always misses); case lines
  `(args) => {changed sim fields}` / `=> value` / `=> value, {fields}`;
  identifiers `sim`, `cfg`, `probe`, `BASIS_IDENTITY`, `MoveState` names.
- `DEFS` maps definition names to their preloaded scripts — a new
  definition file must be added there (and only files present in `DEFS`
  are run, so `move_sim.gd.md`'s type spec is naturally skipped).

## Implementation

- The function to call and its parameter types come from each spec's
  ` ```gd-sig` fence, so the runner needs no per-definition knowledge
  beyond the `DEFS` preload table; static calls go through
  `Callable(script, func_name).callv(args)`.
- Values are parsed by a small recursive scanner (arrays, bare-key dicts,
  raw scalar tokens); scalars resolve lazily — literal args by the
  declared parameter type, expected/`with` fields by `typeof` the value
  already in the target (`sim.get(field)`), which is how `state: WALLRUN`
  resolves through `MoveSim.MoveState` without a type table.
- Float comparisons are `is_equal_approx` (specs carry decimal literals;
  derived doubles like `20 + 1.4` differ from the literal in the last
  ulps). Discrete values compare exact.
- Each case gets fresh fixtures — cases in one block are independent, so
  a mutating definition can't leak state into the next case.

## Assertions

- The runner never touches scene/node state — definitions are called pure
  over `MoveSim`/`MovementConfig`/plain args/fake probes; if a definition
  ever *needs* a node here, the definition is wrong, not the runner.
- `cfg` stays schema-defaults (`MovementConfig.new()`): spec expected
  values pin the schema, so live `default_tuning.tres` changes must never
  break spec tests.
- Exit code is the gate: 0 all green, 1 any failure/XPASS — keep it
  usable from `check`-style scripting.
- Every file in `game/src/player/movement/` with test blocks must appear
  in `DEFS` — a spec silently not running is drift.
