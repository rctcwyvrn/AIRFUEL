---
name: dismount
---

# dismount

Leaving a wall, in any way. The fuel grant scales with along-wall speed
*above* `min_wallrun_speed` (slow wall-hugging gives near-nothing), capped
at `dismount_fuel_max` and the tank — **this is the only in-play fuel
refill** (DESIGN.md §5.1). A jump dismount (`jumped = true`) also gets the
launch: banked wall speed boosted by `dismount_boost_factor` (capped at
terminal velocity) along current motion, push-off along the wall normal,
and an up-velocity floor. Falling off or timing out (`jumped = false`)
grants fuel only and arms the wall-coyote window so the jump stays
available briefly. Either way: ramp grace arms, the wall just left is
locked out for `wall_rearm_time`, the run's bookkeeping clears, and the
state is AIRBORNE.

```gd-sig
dismount : (sim: MoveSim, cfg: MovementConfig, jumped: bool, facing: Vector3) -> void
```

```requires
facing is planar unit: facing.y == 0.0 and facing is normalized
```

```ensures
fuel capped: sim.fuel <= cfg.fuel_max
fuel never drops: sim.fuel >= old sim.fuel
boost capped: jumped implies horizontal launch speed <= cfg.terminal_velocity + cfg.dismount_push_off
coyote exclusivity: jumped implies sim.wall_coyote_timer == 0.0; not jumped implies sim.wall_coyote_timer == cfg.wall_coyote_time
lockout armed: sim.wall_rearm_timer == cfg.wall_rearm_time and sim.last_wall_normal == old sim.wall_normal
run cleared: sim.wallrun_time == 0.0 and sim.wall_speed == 0.0 and sim.state == AIRBORNE
```

```test jump-dismount
with sim = {velocity: [0.0, 0.0, -20.0], wall_speed: 30.0, fuel: 10.0, wall_normal: [1, 0, 0], state: WALLRUN}
(sim, cfg, true, [0, 0, -1]) => {fuel: 43.6, velocity: [4.0, 6.0, -35.4], wall_coyote_timer: 0.0, ramp_grace_timer: 1.2, last_wall_normal: [1, 0, 0], wall_rearm_timer: 0.18, wallrun_time: 0.0, wall_speed: 0.0, state: AIRBORNE}
```

```test falloff-arms-coyote
with sim = {velocity: [0.0, -3.0, -8.0], wall_speed: 20.0, fuel: 0.0, wall_normal: [1, 0, 0], state: WALLRUN}
(sim, cfg, false, [0, 0, -1]) => {fuel: 19.6, velocity: [0.0, -3.0, -8.0], wall_coyote_timer: 0.15, coyote_wall_normal: [1, 0, 0], coyote_wall_speed: 20.0, state: AIRBORNE}
```

```test wall-hugging-grants-nothing
with sim = {velocity: [0.0, 0.0, -6.0], wall_speed: 6.0, fuel: 50.0, wall_normal: [1, 0, 0], state: WALLRUN}
(sim, cfg, false, [0, 0, -1]) => {fuel: 50.0}
```

## Implementation

The largest multi-field write in the movement layer (10 fields) — write
order is load-bearing only at the end: `last_wall_normal` must copy
`wall_normal` *before* the run bookkeeping clears, and the coyote copies
(`coyote_wall_normal/speed`) must be taken before `wall_speed` zeroes.
The `flat.length() > 0.1` check falls back to `facing` (the body's −Z)
when dismounting with no horizontal motion. Boost cap at
`terminal_velocity` is load-bearing (compounding dash-off→re-attach,
shipped once). Callers: wallrun_move (all four exits), handle_dashes and
PlayerCombat's wall lunge (both as `jumped = true`, both then arming the
longer `dash_wall_rearm_time` on top).
