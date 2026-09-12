---
name: air_move
---

# air_move

One AIRBORNE-state tick: gravity; air control (free projection-capped
control up to base run speed, then the fueled strafe tier up to
`air_strafe_speed_cap`, draining `air_strafe_cost_per_sec` only when it can
actually add speed); the ramp-grace countdown (excess speed decays only
after grace expires); and, on a jump press while not charge-locked, the
air-jump priority ladder — wall coyote, then ground coyote, then the fueled
double jump (which floors vertical velocity at `double_jump_strength` and
arms its short cooldown).

```gd-sig
air_move : (sim: MoveSim, cfg: MovementConfig, wish: Vector3, jump: bool, facing: Vector3, delta: float) -> void
```

```requires
wish is planar unit or zero: wish == ZERO or (wish.y == 0.0 and wish is normalized)
facing is planar unit: facing.y == 0.0 and facing is normalized
```

```ensures
ladder is exclusive: at most one of {coyote walljump, ground-coyote jump, double jump} fires per tick
strafe never free: sim.fuel decreases only when the strafe tier or double jump actually applies
grace shields decay: sim.ramp_grace_timer > 0 implies horizontal overspeed is not decayed this tick
```

```test gravity-only
with sim = {velocity: [0.0, 0.0, 0.0]}
(sim, cfg, [0, 0, 0], false, [0, 0, -1], 0.1) => {velocity: [0.0, -1.4, 0.0]}
```

```test strafe-tier-drains-fuel
with sim = {velocity: [0.0, 0.0, 0.0], fuel: 100.0}
(sim, cfg, [1, 0, 0], false, [0, 0, -1], 0.1) => {velocity: [3.1, -1.4, 0.0], fuel: 99.4}
```

```test double-jump
with sim = {velocity: [0.0, -5.0, 0.0], fuel: 100.0}
(sim, cfg, [0, 0, 0], true, [0, 0, -1], 0.1) => {velocity: [0.0, 8.0, 0.0], fuel: 92.0, double_jump_timer: 0.35}
```

```test coyote-outranks-double-jump
with sim = {velocity: [0.0, 0.0, -10.0], fuel: 100.0, wall_coyote_timer: 0.1, coyote_wall_speed: 20.0, coyote_wall_normal: [1, 0, 0]}
(sim, cfg, [0, 0, 0], true, [0, 0, -1], 0.1) => {velocity: [4.0, 6.0, -23.6], fuel: 100.0}
```

## Implementation

Composes four sibling definitions (air_accelerate, spend_fuel,
decay_excess_speed, coyote_walljump) via preloads. The strafe-tier gate
checks `velocity.dot(wish) < air_strafe_speed_cap` *before* spending, so
fuel drains only when the second air_accelerate can add something. The
double jump uses `maxf` (a floor, not an impulse): jumping while already
rising faster than `double_jump_strength` changes nothing. A jump press
consumes the jump buffer here even when the ladder has nothing to give —
the buffer is for landings, not a standing request. In the
strafe-tier test: free control adds 0.6 (cap 12), the gate passes
(0.6 < 18), 0.6 fuel drains, the strafe tier adds its full 2.5.
