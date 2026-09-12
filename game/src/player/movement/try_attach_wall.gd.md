---
name: try_attach_wall
---

# try_attach_wall

Airborne wall acquisition: 12 horizontal radial probes from the body
center; a candidate hit is rejected if the re-attach guard is active
(within `wall_rearm_time` of a dismount AND its normal is within 25° of
`last_wall_normal` — anti-pogo) or if the body is receding from it
(`velocity.dot(normal) > 2.0`); the nearest surviving hit wins. Attaching
seeds the run: normal adopted, run clock zeroed, wall speed = current
along-wall speed, coyote window cancelled, state WALLRUN. Below
`min_wallrun_speed` horizontal, no probes fire at all.

Probe capability as in wallrun_move: `probe.call(dir, dist_scale) ->
Dictionary`.

```gd-sig
try_attach_wall : (sim: MoveSim, cfg: MovementConfig, origin: Vector3, probe: Callable) -> void
```

```requires
airborne: sim.state == AIRBORNE  (caller-gated, in update_state)
probe is honest: probe returns {} or a hit with abs(normal.y) <= 0.4 and a position
```

```ensures
attach is all-or-nothing: state becomes WALLRUN with all five run fields seeded, or nothing changes
speed carried in: attached implies sim.wall_speed == horizontal velocity slid along the new normal
no fuel involved: sim.fuel unchanged
```

```test attaches-nearest
with sim = {velocity: [0.0, 0.0, -10.0], state: AIRBORNE}
with probe = fake_probe {normal: [1, 0, 0], position: [0.65, 0.0, 0.0]}
(sim, cfg, [0, 0, 0], probe) => {wall_normal: [1, 0, 0], wall_speed: 10.0, wallrun_time: 0.0, wall_coyote_timer: 0.0, state: WALLRUN}
```

```test receding-rejected
with sim = {velocity: [8.0, 0.0, 0.0], state: AIRBORNE}
with probe = fake_probe {normal: [1, 0, 0], position: [0.65, 0.0, 0.0]}
(sim, cfg, [0, 0, 0], probe) => {state: AIRBORNE, wall_normal: [0, 0, 0]}
```

```test rearm-cone-rejected
with sim = {velocity: [0.0, 0.0, -10.0], wall_rearm_timer: 0.1, last_wall_normal: [1, 0, 0], state: AIRBORNE}
with probe = fake_probe {normal: [1, 0, 0], position: [0.65, 0.0, 0.0]}
(sim, cfg, [0, 0, 0], probe) => {state: AIRBORNE}
```

```test too-slow-no-probes
with sim = {velocity: [0.0, 0.0, -5.0], state: AIRBORNE}
with probe = fake_probe {normal: [1, 0, 0], position: [0.65, 0.0, 0.0]}
(sim, cfg, [0, 0, 0], probe) => {state: AIRBORNE}
```

## Implementation

Structural literals (deliberate): 12 rays (`TAU * i / 12`), the 25° rearm
cone, the `2.0` receding-velocity reject. The origin parameter exists only
for the nearest-hit distance test — the probe capability already encodes
the ray start. `velocity.dot(normal) > 2.0` uses the full 3D velocity, so
falling fast past a wall you're barely approaching still attaches (the
vertical component is orthogonal to any legal wall normal's dominant axis
by the |normal.y| ≤ 0.4 probe filter — it contributes at most 0.4·|vy|).
