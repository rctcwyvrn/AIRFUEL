# default_combat.tres

## Function

The shipping `CombatConfig` values — Step 2's tuning surface, the counterpart
of `default_tuning.tres` for combat.

## Interface

Referenced by `player.tscn` three times: the Player root's `combat` export
and both `ArmLeft`/`ArmRight` `config` exports — all share this one resource.

## Implementation

`charge_time = 1.0` is pinned by DESIGN.md 8.1 ("~1s") and the fixed-rhythm
principle: every shot takes the same time so the dodge is learnable. Damage
(1 body / 2 head vs 2 HP) is design-fixed, not really tunable.
`min_shot_gap` is the "generous defender window" knob (7.1) — tune by feel.

## Assertions

- Every `CombatConfig` field has a line here.
- Do not tune `charge_time` per-arm or per-anything — fixed rhythm is a
  design feature, not an oversight.
- Playtested conclusions go back into DESIGN.md, not just this file.
