---
name: update_state
---

# update_state

The post-slide state transition, run at the end of every simulated tick.
WALLRUN is sticky — only wallrun_move's own exits leave it, never this
function. Otherwise: floor contact means GROUNDED; leaving the ground
without jumping (vertical velocity still ≤ 1.0 — a walked-off edge, not a
launch) arms the ground-coyote window; and any airborne tick immediately
tries to acquire a wall via try_attach_wall.

```gd-sig
update_state : (sim: MoveSim, cfg: MovementConfig, on_floor: bool, origin: Vector3, probe: Callable) -> void
```

```ensures
wallrun sticky: old state == WALLRUN implies nothing changes
floor grounds: otherwise on_floor implies state == GROUNDED and nothing else changes
walk-off coyote: GROUNDED -> AIRBORNE with velocity.y <= 1.0 arms sim.ground_coyote_timer == cfg.ground_coyote_time
```

```test wallrun-sticky-even-on-floor
with sim = {state: WALLRUN, wall_normal: [1, 0, 0]}
with probe = fake_probe {}
(sim, cfg, true, [0, 0, 0], probe) => {state: WALLRUN}
```

```test landing-grounds
with sim = {state: AIRBORNE, velocity: [0.0, -2.0, 0.0]}
with probe = fake_probe {}
(sim, cfg, true, [0, 0, 0], probe) => {state: GROUNDED}
```

```test walk-off-arms-coyote
with sim = {state: GROUNDED, velocity: [10.0, 0.0, 0.0]}
with probe = fake_probe {}
(sim, cfg, false, [0, 0, 0], probe) => {state: AIRBORNE, ground_coyote_timer: 0.12}
```

## Implementation

The `velocity.y <= 1.0` gate distinguishes walking off an edge from a jump
that left the floor this tick (jump velocity is 9). The tail call into
try_attach_wall is why going airborne can land you in WALLRUN within the
same tick — a body sliding off a ramp beside a wall attaches instantly,
which is what makes ramp→wall chains feel seamless. The WALLRUN early
return happens before the floor check on purpose: wallrun_move already
handled floor contact this tick (it dismounts), so a WALLRUN state reaching
here means the wall tick decided to stay.
