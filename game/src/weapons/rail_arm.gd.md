# rail_arm.gd

## Function

One arm mount's railgun charge cycle (DESIGN.md 7, 8.1): charge that cannot
be held or cancelled, auto-completion, per-arm cooldown. Two instances live
in `player.tscn` (`ArmLeft`, `ArmRight`).

## Interface

- `class_name RailArm extends Node`; export `config: CombatConfig`.
- API for the player: `try_charge() -> bool` (false unless IDLE),
  `on_fired()` (starts cooldown), `progress() -> float` (0–1, 1.0 while
  PENDING), `is_locking() -> bool` (CHARGING or PENDING — drives the
  movement freeze), `reset()` (hard idle — used on loadout swaps), signal
  `charge_complete`.
- States: `IDLE → CHARGING → PENDING → COOLDOWN → IDLE`.

## Implementation

Self-ticking in `_physics_process`. PENDING exists because a completed
charge may have to wait out the dual-rail minimum gap (7.1) — the arm has
committed but the *player* decides the exact fire tick and sequencing; the
arm never raycasts or spends anything itself. The freeze deliberately spans
PENDING: DESIGN.md 7.2 locks you "from first trigger press to second shot."

## Assertions

- No cancel path: nothing may transition CHARGING back to IDLE except
  completing (then firing). A mistimed charge fires into nothing — intended.
- `try_charge` while non-IDLE must stay a silent no-op.
- `is_locking()` true exactly during CHARGING and PENDING, never COOLDOWN.
- All timing numbers come from `config`; no literals.
