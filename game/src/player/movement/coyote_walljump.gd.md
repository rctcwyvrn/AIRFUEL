---
name: coyote_walljump
---

# coyote_walljump

The jump-dismount boost, applied during the wall-coyote window after the
wall already ended (Celeste-style): jumping within `wall_coyote_time` of
falling off a wall launches you exactly as a jump dismount would have —
banked coyote wall speed boosted by the dismount factor (capped at terminal
velocity), push-off along the remembered wall normal, the up-velocity
floor, and a fresh ramp-grace window. **No fuel** — the grant already
happened at falloff (see dismount); paying twice would make falling off
strictly better than jumping off.

```gd-sig
coyote_walljump : (sim: MoveSim, cfg: MovementConfig, facing: Vector3) -> void
```

```requires
window is open: sim.wall_coyote_timer > 0.0  (caller-gated, in air_move)
facing is planar unit: facing.y == 0.0 and facing is normalized
```

```ensures
no fuel granted: sim.fuel unchanged
boost capped: horizontal launch speed <= cfg.terminal_velocity + cfg.dismount_push_off
window consumed: sim.wall_coyote_timer == 0.0
grace armed: sim.ramp_grace_timer == cfg.ramp_grace_window
```

```test boost-along-motion
with sim = {velocity: [0.0, 0.0, -10.0], coyote_wall_speed: 20.0, coyote_wall_normal: [1, 0, 0], wall_coyote_timer: 0.1}
(sim, cfg, [0, 0, -1]) => {velocity: [4.0, 6.0, -23.6], ramp_grace_timer: 1.2, wall_coyote_timer: 0.0}
```

```test slow-fallback-to-facing
with sim = {velocity: [0.0, -2.0, 0.0], coyote_wall_speed: 20.0, coyote_wall_normal: [1, 0, 0], wall_coyote_timer: 0.1}
(sim, cfg, [0, 0, -1]) => {velocity: [4.0, 6.0, -23.6], wall_coyote_timer: 0.0}
```

## Implementation

Duplicates dismount's jump branch over the *coyote* copies of the wall
fields (`coyote_wall_speed` / `coyote_wall_normal`), because the live wall
fields were already cleared at falloff. The `flat.length() > 0.1` facing
fallback matches dismount's. Boost cap at `terminal_velocity` is
load-bearing: uncapped, the dash-off→re-attach loop compounded to hundreds
of m/s (shipped once).
