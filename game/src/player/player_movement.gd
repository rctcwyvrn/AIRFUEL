class_name PlayerMovement
extends Object

## Module header for the player's movement layer (DESIGN.md §4, §5), in the
## Trellis-style pilot shape: every mechanic is a per-definition file under
## movement/ (one pure static function + private helpers over MoveSim data,
## each with a .tr-style spec doc), and this facade delegates to them with
## the pre-pilot signatures, so callers (player.gd, PlayerCombat) are
## unchanged. This file is the node BOUNDARY: the only movement code allowed
## to touch node state — it extracts plain data (sim, config, facing, camera
## basis, floor contact, slide collisions) and hosts probe_wall_at, the
## raycast adapter bound into the `probe` capability the definitions take.
## Determinism rules are unchanged: everything here runs inside _simulate()
## (prediction replays and TAS ghosts re-run it — the trajectory fingerprint
## must not move; gate: tools/fingerprint.tscn).

const AirAccelerateDef := preload("movement/air_accelerate.gd")
const AirMoveDef := preload("movement/air_move.gd")
const ApplyGlideDef := preload("movement/apply_glide.gd")
const CoyoteWalljumpDef := preload("movement/coyote_walljump.gd")
const DecayExcessSpeedDef := preload("movement/decay_excess_speed.gd")
const DismountDef := preload("movement/dismount.gd")
const GroundMoveDef := preload("movement/ground_move.gd")
const HandleDashesDef := preload("movement/handle_dashes.gd")
const SpeedLimitsDef := preload("movement/speed_limits.gd")
const SpendFuelDef := preload("movement/spend_fuel.gd")
const TryAttachWallDef := preload("movement/try_attach_wall.gd")
const UpdateStateDef := preload("movement/update_state.gd")
const WallrunMoveDef := preload("movement/wallrun_move.gd")
const WishDirDef := preload("movement/wish_dir.gd")


static func ground_move(p: CharacterBody3D, wish: Vector3, delta: float) -> void:
	GroundMoveDef.ground_move(p.sim, p.config, wish, delta)


static func air_move(p: CharacterBody3D, wish: Vector3, delta: float) -> void:
	AirMoveDef.air_move(p.sim, p.config, wish, p.cmd_jump, -p.global_transform.basis.z, delta)


static func wallrun_move(p: CharacterBody3D, delta: float) -> void:
	WallrunMoveDef.wallrun_move(
		p.sim,
		p.config,
		p.is_on_floor(),
		p.cmd_jump,
		-p.global_transform.basis.z,
		_probe_of(p),
		delta
	)


static func dismount(p: CharacterBody3D, jumped: bool) -> void:
	DismountDef.dismount(p.sim, p.config, jumped, -p.global_transform.basis.z)


static func handle_dashes(p: CharacterBody3D) -> void:
	HandleDashesDef.handle_dashes(
		p.sim,
		p.config,
		p.cmd_move,
		p.cmd_down_dash,
		p.cmd_dash,
		p.camera.global_transform.basis,
		-p.global_transform.basis.z
	)


static func update_state(p: CharacterBody3D) -> void:
	UpdateStateDef.update_state(p.sim, p.config, p.is_on_floor(), p.global_position, _probe_of(p))


static func apply_glide(p: CharacterBody3D, pre_vel: Vector3) -> void:
	var collisions: Array[Dictionary] = []
	for i in p.get_slide_collision_count():
		var col: KinematicCollision3D = p.get_slide_collision(i)
		var body := col.get_collider() as Node
		collisions.append(
			{normal = col.get_normal(), deflector = body != null and body.has_meta("deflector")}
		)
	ApplyGlideDef.apply_glide(p.sim, p.config, pre_vel, collisions)


static func apply_speed_limits(p: CharacterBody3D, delta: float) -> void:
	SpeedLimitsDef.apply_speed_limits(p.sim, p.config, p.combat.charge_speed_cap, delta)


static func spend_fuel(p: CharacterBody3D, amount: float) -> bool:
	return SpendFuelDef.spend_fuel(p.sim, amount)


static func wish_dir(p: CharacterBody3D) -> Vector3:
	return WishDirDef.wish_dir(p.cmd_move, p.global_transform.basis)


## The wall-probe capability's node-bound implementation: a short world
## raycast from the body center; wall-ish surfaces only (|normal.y| <= 0.4).
static func probe_wall_at(p: CharacterBody3D, dir: Vector3, dist_scale := 1.0) -> Dictionary:
	var space := p.get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(
		p.global_position,
		p.global_position + dir.normalized() * p.config.wall_probe_distance * dist_scale,
		p.collision_mask,
		[p.get_rid()]
	)
	var hit := space.intersect_ray(params)
	if hit.is_empty() or absf(hit.normal.y) > 0.4:
		return {}
	return hit


static func _probe_of(p: CharacterBody3D) -> Callable:
	return func(dir: Vector3, dist_scale: float) -> Dictionary:
		return probe_wall_at(p, dir, dist_scale)
