extends Object

## Definition: the dash layer — Q's straight-down dash (on a wall: slide down
## without detaching), and the camera-aimed WASD+Shift dash, which off a wall
## is a real dismount with a longer anti-pogo lockout. Spec:
## handle_dashes.gd.md.

const Dismount := preload("dismount.gd")
const SpendFuel := preload("spend_fuel.gd")


static func handle_dashes(
	sim: MoveSim,
	cfg: MovementConfig,
	move_input: Vector2,
	down_dash: bool,
	dash: bool,
	cam_basis: Basis,
	facing: Vector3,
) -> void:
	if sim.move_locked:
		return
	var on_wall: bool = sim.state == MoveSim.MoveState.WALLRUN
	if down_dash:
		# Q is the down dash (DESIGN.md 4.4): own tuning, no cooldown. On a
		# wall you STAY attached and slide down it fast. Independent of
		# Shift — pressing Q always means straight down.
		if (
			(on_wall or sim.state == MoveSim.MoveState.AIRBORNE)
			and SpendFuel.spend_fuel(sim, cfg.down_dash_cost)
		):
			sim.velocity.y = minf(sim.velocity.y, -cfg.down_dash_speed)
	if not dash:
		return
	if move_input == Vector2.ZERO:
		return  # bare Shift is inert: a directional dash needs held WASD
	if sim.dash_cooldown_timer > 0.0 or not SpendFuel.spend_fuel(sim, cfg.air_dash_cost):
		return
	if on_wall:
		# Dashing off the wall is a real dismount: same fuel grant and speed
		# boost as jumping off, with the dash impulse stacked on top — but
		# the wall you left is locked out for longer (anti-pogo: dashing
		# straight back in compounded boosts to absurd speeds)
		Dismount.dismount(sim, cfg, true, facing)
		sim.wall_rearm_timer = cfg.dash_wall_rearm_time
	# Camera-aimed: W+Shift dashes wherever you're looking (pitch included)
	var dir := (cam_basis.x * move_input.x + -cam_basis.z * -move_input.y).normalized()
	sim.velocity += dir * cfg.air_dash_impulse
	sim.dash_cooldown_timer = cfg.air_dash_cooldown
