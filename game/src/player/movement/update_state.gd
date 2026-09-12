extends Object

## Definition: the post-slide state transition — WALLRUN is sticky (only its
## own tick exits it), floor contact grounds, walking off an edge (not a
## jump) arms the ground-coyote window, and going airborne immediately tries
## to acquire a wall. Spec: update_state.gd.md.

const TryAttachWall := preload("try_attach_wall.gd")


static func update_state(
	sim: MoveSim, cfg: MovementConfig, on_floor: bool, origin: Vector3, probe: Callable
) -> void:
	if sim.state == MoveSim.MoveState.WALLRUN:
		return
	if on_floor:
		sim.state = MoveSim.MoveState.GROUNDED
		return
	if sim.state == MoveSim.MoveState.GROUNDED and sim.velocity.y <= 1.0:
		sim.ground_coyote_timer = cfg.ground_coyote_time  # walked off an edge, not a jump
	sim.state = MoveSim.MoveState.AIRBORNE
	TryAttachWall.try_attach_wall(sim, cfg, origin, probe)
