# default_tuning.tres

## Function

The single source of truth for Step 1 movement numbers — a saved
`MovementConfig` instance. This file *is* the prototype: Step 1's whole job is
finding these values by playing (DESIGN.md §24, Appendix B).

## Interface

- Referenced by `player.tscn` (`config` export on the Player root).
- One `key = value` line per `MovementConfig` field, same names.

## Implementation

Hand-editable text resource. For live tuning, run the game from the editor,
select the resource in the inspector, and edit — changes apply next tick.
Current values are **first guesses, not decisions**; the design doc's only
firm steer is §5.3: fuel should be *generous* (a rhythm constraint, not
scarcity — running dry a few times a match, not constantly).

## Assertions

- Every `MovementConfig` field has a line here (missing lines silently fall
  back to script defaults).
- Keep it consistent with the design intent when tuning: dismount reward must
  scale with wall speed (§4.2), wallrun stays free, and terminal velocity
  stays finite (§4.1 — the unbounded-acceleration exploit is why it exists).
- When a value graduates from guess to playtested decision, record the finding
  in DESIGN.md (or its open-questions list), not just here.
