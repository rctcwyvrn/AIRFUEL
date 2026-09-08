# combat_config.gd

## Function

Schema for combat tuning — DESIGN.md Appendix B "Combat" block (railgun
portion). Same philosophy as `MovementConfig`: numbers are data, not literals.

## Interface

- `class_name CombatConfig extends Resource`, pure data.
- Consumed by `player.gd` (`combat` export) and both `RailArm` nodes
  (`config` export). Groups: Railgun (charge_time, cooldown, damage_body/head,
  range_max, charge_speed_cap, hp_max), Aim Crush (floor = sensitivity
  multiplier at full charge, exponent = curve shape), Dual Rail
  (min_shot_gap), Sword (lunge cost / `sword_lunge_speed` — a burst ABOVE terminal
  velocity that the movement system's overspeed decay bleeds back down —
  cooldown, hit range, active window; 8.2: cheaper per meter and longer
  than a dash).

## Implementation

Damage values are per-hit against uniform 2 HP (DESIGN.md 9.2): body 1
(two-shot), head 2 (lethal). Aim crush multiplier =
`lerp(1, floor, progress^exponent)` — exponent > 1 keeps early charge
steerable and crushes late.

## Assertions

- Values that actually ship live in `default_combat.tres`; keep fields and
  lines in sync when adding.
- No partial charge / hold / early-release fields should ever appear here —
  explicitly cut (DESIGN.md Appendix A).
- Stays a pure Resource (per-server tunability, DESIGN.md 19).
