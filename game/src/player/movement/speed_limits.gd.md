---
name: speed_limits
---

# speed_limits

The end-of-tick velocity clamps, applied after the state move and dashes,
before the body slides: a soft overspeed ceiling — speed above
`terminal_velocity` (sword lunge) decays at `overspeed_decay` instead of
clamping, so the lunge spike reads as a rush, not a wall; the charge-freeze
cap — while move-locked, velocity is hard-limited to `charge_speed_cap`
(charging bleeds you down to a slower, more readable trajectory,
DESIGN.md §7.2); and the hard terminal-fall floor on vertical velocity.

```gd-sig
apply_speed_limits : (sim: MoveSim, cfg: MovementConfig, charge_speed_cap: float, delta: float) -> void
```

```requires
positive cap: charge_speed_cap > 0.0
```

```ensures
fall floored: sim.velocity.y >= -cfg.terminal_fall_speed
locked capped: sim.move_locked implies sim.velocity.length() <= charge_speed_cap
overspeed decays not clamps: speed above terminal drops by at most cfg.overspeed_decay * delta per tick
only velocity changes: no other sim field is written
```

```test overspeed-decays
with sim = {velocity: [60.0, 0.0, 0.0]}
(sim, cfg, 14.0, 0.1) => {velocity: [55.0, 0.0, 0.0]}
```

```test locked-cap
with sim = {velocity: [30.0, 0.0, 0.0], move_locked: true}
(sim, cfg, 14.0, 0.1) => {velocity: [14.0, 0.0, 0.0]}
```

```test terminal-fall-floor
with sim = {velocity: [0.0, -50.0, 0.0]}
(sim, cfg, 14.0, 0.1) => {velocity: [0.0, -40.0, 0.0]}
```

## Implementation

Absorbed from the orphaned clamps in `player.gd`'s `_simulate` (the pilot
move) — they were movement math living in the orchestrator.
`charge_speed_cap` arrives as a plain float because it belongs to
`CombatConfig`, and movement definitions depend only on `MovementConfig`;
the facade (`PlayerMovement.apply_speed_limits`) reads it off `p.combat`.
Order inside matters: the overspeed decay runs on the full vector first,
then the lock cap, then the fall floor — so a locked, falling body is
floored after capping (the floor wins).
