---
name: handle_dashes
---

# handle_dashes

The dash layer, run after the state move every tick, inert while
charge-locked. Q is the down dash (DESIGN.md §4.4): its own tuning, no
cooldown (fuel is the limiter), legal airborne or on a wall — on a wall you
STAY attached and slide down fast; it floors vertical velocity at
`-down_dash_speed`. Shift+WASD is the camera-aimed directional dash: bare
Shift is inert (a dash needs held WASD), it shares one cooldown and costs
`air_dash_cost`, and the impulse goes wherever the camera looks (pitch
included). Dashing off a wall is a real dismount — full jump-grade grant
and boost with the dash impulse stacked on top — and arms the longer
`dash_wall_rearm_time` (anti-pogo: dashing straight back in compounded
boosts to absurd speeds).

```gd-sig
handle_dashes : (sim: MoveSim, cfg: MovementConfig, move_input: Vector2, down_dash: bool, dash: bool, cam_basis: Basis, facing: Vector3) -> void
```

```requires
facing is planar unit: facing.y == 0.0 and facing is normalized
```

```ensures
locked is inert: sim.move_locked implies nothing changes
bare shift inert: dash without move_input changes nothing (down dash aside)
spends are gated: fuel changes only via spend_fuel; a failed spend leaves everything unchanged
down dash is a floor: it only ever lowers velocity.y, never raises it
wall dash is a dismount: dashing while WALLRUN ends in AIRBORNE with sim.wall_rearm_timer == cfg.dash_wall_rearm_time
```

```test down-dash-floors
with sim = {velocity: [0.0, 0.0, 0.0], fuel: 100.0, state: AIRBORNE}
(sim, cfg, [0, 0], true, false, BASIS_IDENTITY, [0, 0, -1]) => {velocity: [0.0, -30.0, 0.0], fuel: 88.0}
```

```test bare-shift-inert
with sim = {velocity: [0.0, 0.0, 0.0], fuel: 100.0, state: AIRBORNE}
(sim, cfg, [0, 0], false, true, BASIS_IDENTITY, [0, 0, -1]) => {velocity: [0.0, 0.0, 0.0], fuel: 100.0}
```

```test camera-aimed-dash
with sim = {velocity: [0.0, 0.0, 0.0], fuel: 100.0, state: AIRBORNE}
(sim, cfg, [0, -1], false, true, BASIS_IDENTITY, [0, 0, -1]) => {velocity: [0.0, 0.0, -18.0], fuel: 75.0, dash_cooldown_timer: 0.8}
```

```test locked-inert
with sim = {velocity: [0.0, 0.0, 0.0], fuel: 100.0, move_locked: true, state: AIRBORNE}
(sim, cfg, [0, -1], true, true, BASIS_IDENTITY, [0, 0, -1]) => {velocity: [0.0, 0.0, 0.0], fuel: 100.0}
```

## Implementation

Down dash and directional dash are deliberately independent gates in one
pass — Q+Shift+W in one tick performs both (down floor, then impulse).
`on_wall` is latched before the dismount so the directional dash knows it
left a wall. The dash direction formula
`(cam_basis.x * input.x + -cam_basis.z * -input.y).normalized()` matches
wish_dir's but over the *camera* basis — W+Shift dashes into the camera's
pitch, which is the whole point (down-strafe was cut 2026-09-10; Q owns
straight-down). The GROUNDED state is excluded from the down dash by the
`on_wall or AIRBORNE` gate, not from the directional dash — a grounded
Shift+WASD dash is legal and is the ground-escape tool.
