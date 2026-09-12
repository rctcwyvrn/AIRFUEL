---
name: MoveSim
---

# MoveSim

The movement simulation state (DESIGN.md §4, §5) as a plain-data type: one
instance per player body (`p.sim`), holding everything the movement
definitions in this directory read or write. No node dependencies —
constructible and simulable headless, which is what makes every definition
here testable without a scene. Defaults are the pre-first-tick state of a
freshly instanced body (airborne, empty tank until `_ready` fills it).

```gd-type
MoveSim = {
  velocity: Vector3,            # authoritative; body mirrors it (player.gd)
  state: MoveState,             # GROUNDED | AIRBORNE | WALLRUN
  fuel: float,
  move_locked: bool,            # derived each tick from arm charge state
  wall_normal: Vector3,
  wall_speed: float,
  wallrun_time: float,
  last_wall_normal: Vector3,
  wall_rearm_timer: float,
  ramp_grace_timer: float,
  dash_cooldown_timer: float,
  double_jump_timer: float,
  wall_coyote_timer: float,
  coyote_wall_normal: Vector3,
  coyote_wall_speed: float,
  ground_coyote_timer: float,
  jump_buffer_timer: float,
}
```

```invariant
fuel bounded: 0.0 <= fuel and fuel <= cfg.fuel_max
timers non-negative: every *_timer field >= 0.0, except ramp_grace_timer which may sit up to one tick's delta below zero (air_move decays it unclamped; it is only ever compared > 0)
wall normal near-horizontal: wall_normal == ZERO or abs(wall_normal.y) <= 0.4
wallrun has a wall: state == WALLRUN implies wall_normal != ZERO
```

## Implementation

- The `MoveState` enum lives here (moved from `player.gd` in the pilot) so
  definition files can name it without touching `AirfuelPlayer` — naming
  the player class in helper files creates a class-resolution cycle.
- `move_locked` is **derived** state: recomputed every tick by the shell
  (`player.gd`) and by `PlayerState.restore`, never persisted in the
  rollback codec.
- The rollback codec (`player_state.gd`) packs these fields into slots
  3–26 of its 42-float layout; `velocity` is slots 3–5. Field changes here
  require a codec change *and* a deliberate fingerprint re-baseline.
- `RefCounted`, mutated in place by the definitions — no per-tick
  allocation; the reconciliation replay reuses the same instance.
