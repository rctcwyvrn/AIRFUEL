class_name MoveSim
extends RefCounted

## The movement simulation state (DESIGN.md §4, §5) as plain data: everything
## the per-definition movement functions in this directory read or write.
## Owned by AirfuelPlayer (`p.sim`); the body mirrors `velocity` around
## move_and_slide() and rendering reads, but THIS is the authoritative
## storage — gameplay code writes here, never to the body field directly.
## No node dependencies: a MoveSim is constructible and simulable headless,
## which is what makes the movement definitions testable without a scene.

enum MoveState { GROUNDED, AIRBORNE, WALLRUN }

var velocity := Vector3.ZERO
var state := MoveState.AIRBORNE
var fuel := 0.0
var move_locked := false

var wall_normal := Vector3.ZERO
var wall_speed := 0.0
var wallrun_time := 0.0
var last_wall_normal := Vector3.ZERO
var wall_rearm_timer := 0.0

var ramp_grace_timer := 0.0
var dash_cooldown_timer := 0.0
var double_jump_timer := 0.0
var wall_coyote_timer := 0.0
var coyote_wall_normal := Vector3.ZERO
var coyote_wall_speed := 0.0
var ground_coyote_timer := 0.0
var jump_buffer_timer := 0.0
