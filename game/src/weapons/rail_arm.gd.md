# rail_arm.gd

## Function

One arm mount's railgun charge cycle (DESIGN.md 7, 8.1): charge that cannot
be held or cancelled, auto-completion, per-arm cooldown. Two instances live
in `player.tscn` (`ArmLeft`, `ArmRight`).

## Interface

- `class_name RailArm extends Node`; export `config: CombatConfig`.
- API for the player: `step(delta)` (advances the charge cycle one tick —
  the arm does NOT self-process), `try_charge() -> bool` (false unless
  IDLE), `on_fired()` (starts cooldown), `progress() -> float` (0–1, 1.0
  while PENDING), `is_locking() -> bool` (CHARGING or PENDING — drives the
  movement freeze), `reset()` (hard idle — used on loadout swaps), signal
  `charge_complete`.
- States: `IDLE → CHARGING → PENDING → COOLDOWN → IDLE`.
- The `state`/`charge`/`cooldown` fields are read and written directly by
  the `PlayerState` rollback codec (slots 35–40) — keep them plain,
  restorable values with no hidden companion state.

## Implementation

Not self-ticking: the owning player calls `step(delta)` at the **end** of
its `_simulate()` so the whole player tick is one re-runnable unit for
client prediction replay. That placement also preserves the old ordering
(the arm used to be a self-processing child node, which ran after its
parent): a charge that completes this tick fires next tick, never the
tick it completes. PENDING exists because a completed
charge may have to wait out the dual-rail minimum gap (7.1) — the arm has
committed but the *player* decides the exact fire tick and sequencing; the
arm never raycasts or spends anything itself. The freeze deliberately spans
PENDING: DESIGN.md 7.2 locks you "from first trigger press to second shot."

## Assertions

- No player-facing cancel path: no input may transition CHARGING back to
  IDLE except completing (then firing) — `reset()` (loadout-swap/respawn
  housekeeping, never bound to a cancel input) is the sole exception. A
  mistimed charge fires into nothing — intended.
- `try_charge` while non-IDLE must stay a silent no-op.
- `is_locking()` true exactly during CHARGING and PENDING, never COOLDOWN.
- All timing numbers come from `config`; no literals.
- No `_physics_process`/`_process`: the arm advances only when the owning
  player calls `step()` — a self-ticking arm would advance outside the
  player's re-runnable tick and desync prediction replays.
