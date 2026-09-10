# default_combat.tres

## Function

The shipping `CombatConfig` values — Step 2's tuning surface, the counterpart
of `default_tuning.tres` for combat.

## Interface

Referenced by `player.tscn` three times: the Player root's `combat` export
and both `ArmLeft`/`ArmRight` `config` exports — all share this one resource.

## Implementation

The two lines actually in the file are sword overrides:
`sword_lunge_cooldown = 3` (schema default 1.2 — a lunge is a commitment,
not a spammable dash) and `sword_active_time = 0.2` (default 0.35 — a
shorter live-blade window). Both are feel knobs from sword playtesting.

The rail values all ship at schema defaults (so no lines here):
`charge_time` 1.0 is pinned by DESIGN.md 8.1 ("~1s") and the fixed-rhythm
principle — every shot takes the same time so the dodge is learnable.
Damage (1 body / 2 head vs 2 HP) is design-fixed, not really tunable.
`min_shot_gap` is the "generous defender window" knob (7.1) — tune by feel.

Aim crush is gone entirely (cut 2026-09-09, DESIGN.md Appendix A; it had
already been tuned to a no-op here on 2026-09-08). The shooter tracks freely
while charging — the dodge lives in the last-instant 8-direction dash.

## Assertions

- Overrides-only: a line appears here iff the value differs from the
  `CombatConfig` schema default (same rule as `default_tuning.tres`,
  Lily's call 2026-09-09).
- Do not tune `charge_time` per-arm or per-anything — fixed rhythm is a
  design feature, not an oversight.
- Playtested conclusions go back into DESIGN.md, not just this file.
