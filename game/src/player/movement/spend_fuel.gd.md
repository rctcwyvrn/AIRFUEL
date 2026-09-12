---
name: spend_fuel
---

# spend_fuel

The all-or-nothing fuel spend — the only way anything drains fuel
(DESIGN.md §5). Succeeds and deducts exactly `amount` if the tank covers
it; otherwise deducts nothing and reports failure. Callers gate their
ability on the return value, so a too-expensive ability simply doesn't
happen — there is no partial spend and no debt.

```gd-sig
spend_fuel : (sim: MoveSim, amount: float) -> bool
```

```requires
non-negative cost: amount >= 0.0
```

```ensures
all or nothing: result implies sim.fuel decreased by exactly amount; not result implies sim.fuel unchanged
never negative: sim.fuel >= 0.0
only fuel changes: no other sim field is written
```

```test covers-it
with sim = {fuel: 20.0}
(sim, 8.0) => true, {fuel: 12.0}
```

```test cannot-afford
with sim = {fuel: 5.0}
(sim, 8.0) => false, {fuel: 5.0}
```

```test exact-tank
with sim = {fuel: 8.0}
(sim, 8.0) => true, {fuel: 0.0}
```

## Implementation

Absorbed from `AirfuelPlayer._spend` in the pilot; the body method now
delegates here (via the `PlayerMovement.spend_fuel` facade) so combat's
sword-lunge spend and every movement spend share one definition.
