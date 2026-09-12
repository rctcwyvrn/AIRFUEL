class_name PlayerCombat
extends Object

## The player's combat layer (DESIGN.md §7, §8), split out of player.gd:
## arm triggering and dual-rail sequencing, the rail shot itself, the sword
## lunge hit check, and the weapon viewmodel visuals. Same pattern as
## PlayerState: stateless static functions over the player body (typed
## CharacterBody3D — never AirfuelPlayer, so no class-resolution cycle);
## other bodies are recognized by group "player" membership instead of an
## `is AirfuelPlayer` check for the same reason. ALL state stays on the
## player. handle_arms/trigger_arm/sword_hit_check/fire_rail run inside
## _simulate() and must respect the `replaying` guard (prediction replays
## never re-do damage or effects); the visuals at the bottom are
## render-tick only.


static func handle_arms(p: CharacterBody3D) -> void:
	if p.cmd_swap:
		p.set_loadout((p.loadout_index + 1) % p.LOADOUTS.size())
	if p.cmd_fire_l:
		trigger_arm(p, 0)
	if p.cmd_fire_r:
		trigger_arm(p, 1)
	if p.pending_arms.is_empty():
		return
	# 7.1: completed charges fire in press order, never closer than min_shot_gap
	# (tick-timer, not wall clock: prediction replays re-run this code)
	if p.shot_gap_timer <= 0.0:
		fire_rail(p, p.pending_arms.pop_front())
		p.shot_gap_timer = p.combat.min_shot_gap


static func trigger_arm(p: CharacterBody3D, index: int) -> void:
	if p.arm_types[index] == "rail":
		(p.arm_left if index == 0 else p.arm_right).try_charge()
		return
	# Sword lunge (DESIGN.md 8.2): movement ability that is also the kill.
	# Cheaper per meter and longer than a dash, per-arm cooldown, no freeze.
	if p.sim.move_locked:
		return
	if p.sword_cd[index] > 0.0 or not p._spend(p.combat.sword_lunge_cost):
		return
	if p.sim.state == MoveSim.MoveState.WALLRUN:
		# Lunging off a wall is a real dismount, same as dashing off (fuel
		# grant + the longer anti-pogo rearm); the lunge velocity below is
		# the launch — it replaces the dismount boost entirely.
		PlayerMovement.dismount(p, true)
		p.sim.wall_rearm_timer = p.config.dash_wall_rearm_time
	p.sword_cd[index] = p.combat.sword_lunge_cooldown
	p.sword_active = p.combat.sword_active_time
	p.sword_side = "L" if index == 0 else "R"
	p.sim.velocity = -p.camera.global_transform.basis.z * p.combat.sword_lunge_speed
	p.sim.ramp_grace_timer = p.config.ramp_grace_window
	if p.replaying:
		return
	var vm: MeshInstance3D = p.vm_left if index == 0 else p.vm_right
	vm.position += Vector3(0.0, -0.06, -0.5)
	vm.rotation.x += 0.4


## While the blade is live, anything in reach dies (one hit per lunge).
## Kills only happen where the sim is authoritative: offline (dummies,
## practice duels) and on the server (players). A PREDICTED lunge is pure
## movement — the server's copy of the same lunge lands the kill and the
## event comes back.
static func sword_hit_check(p: CharacterBody3D) -> void:
	if p.role == p.NetRole.PREDICTED:
		return
	var candidates: Array[Node] = []
	candidates.append_array(p.get_tree().get_nodes_in_group("player"))
	candidates.append_array(p.get_tree().get_nodes_in_group("target"))
	for node: Node in candidates:
		var is_body: bool = node.is_in_group("player")
		if node == p or (is_body and node.ghost_controlled):
			continue
		var pos := (node as Node3D).global_position
		if node is TargetDummy:
			pos += Vector3.UP * 2.55
		elif is_body and Net.match_host != null:
			# Lag compensation (§20.2 N2): reach is measured against where
			# the victim was on this lunger's screen, same as rail hits.
			pos = Net.match_host.rewound_position(node, p)
		if p.global_position.distance_to(pos) > p.combat.sword_hit_range:
			continue
		p.sword_active = 0.0
		if node is TargetDummy:
			node.take_hit(99)
			p.shot_fired.emit(p.sword_side, "kill")
		elif is_body:
			node.apply_damage(99, p.get_multiplayer_authority())
			if Net.match_host != null:
				Net.match_host.on_shot(p, p.sword_side, Vector3.ZERO, Vector3.ZERO, "kill")
			elif not Net.active:
				p.shot_fired.emit(p.sword_side, "kill")  # offline practice hitmarker
		return


static func fire_rail(p: CharacterBody3D, arm: RailArm) -> void:
	arm.on_fired()
	if p.replaying:
		# Replayed ticks keep the arm state machine honest but never re-do
		# damage or effects — those happened when the tick first ran.
		return
	var side: String = "L" if arm == p.arm_left else "R"
	var cam: Transform3D = p.camera.global_transform
	var from := cam.origin
	var to: Vector3 = from + -cam.basis.z * p.combat.range_max
	var end := to
	var result := "miss"
	if Net.match_host != null and p.role != p.NetRole.PREDICTED:
		# Authoritative netplay shot: lag-compensated (§20.2 N2) — victims
		# are tested at the position this shooter's client had rendered.
		var ev: Dictionary = Net.match_host.eval_rail_hit(p, from, -cam.basis.z, p.combat.range_max)
		end = ev.end
		var victim: CharacterBody3D = ev.victim
		if victim != null:
			var killed: bool = victim.apply_damage(
				p.combat.damage_body, p.get_multiplayer_authority()
			)
			result = "kill" if killed else "body"
	else:
		# Offline (dummies, hit zones, practice duels) and PREDICTED
		# muzzle-flash raycasts: the shooter's local view — mask: world +
		# targets (layer 2).
		var space := p.get_world_3d().direct_space_state
		var params := PhysicsRayQueryParameters3D.create(
			from, to, p.collision_mask | 2, [p.get_rid()]
		)
		var hit := space.intersect_ray(params)
		if not hit.is_empty():
			end = hit.position
			var collider: Object = hit.collider
			if collider.has_meta("hit_zone"):
				var zone: String = collider.get_meta("hit_zone")
				var damage: int = p.combat.damage_head if zone == "head" else p.combat.damage_body
				var target := (collider as Node).get_parent()
				if target is TargetDummy:
					result = "kill" if target.take_hit(damage) else zone
			elif (
				collider is Node
				and (collider as Node).is_in_group("player")
				and not collider.ghost_controlled
			):
				if p.role == p.NetRole.PREDICTED:
					result = "body"  # visual only; the server decides
				else:
					# Offline practice duel: this LOCAL sim IS authoritative.
					var victim_killed: bool = collider.apply_damage(
						p.combat.damage_body, p.get_multiplayer_authority()
					)
					result = "kill" if victim_killed else "body"
	var side_sign := 1.0 if side == "R" else -1.0
	var vm: MeshInstance3D = p.vm_right if side == "R" else p.vm_left
	var muzzle: Vector3 = vm.global_transform * Vector3(0, 0, -0.35)
	if not Net.headless:
		vm.position += Vector3(0.0, 0.02, 0.16)
		PlayerFx.spawn_beam(p.get_parent(), muzzle, end)
		PlayerFx.spawn_canister(p, side_sign, cam)
		PlayerFx.play_rail_sound(p.get_parent(), muzzle)
	if Net.match_host != null:
		Net.match_host.on_shot(p, side, muzzle, end, result)
	if not Net.active:
		p.shot_fired.emit(side, result)  # offline hitmarker; netplay uses ev_shot


## First-person weapon identity: rail = chunky block held level, sword = a
## long thin blade rolled inward and tilted up. Pose is stored as meta so
## the recovery lerp returns to the weapon's stance, not to zero.
static func apply_loadout_visuals(p: CharacterBody3D) -> void:
	for i in 2:
		var vm: MeshInstance3D = p.vm_left if i == 0 else p.vm_right
		var mat := vm.material_override as StandardMaterial3D
		var is_sword: bool = p.arm_types[i] == "sword"
		mat.albedo_color = p.SWORD_VM_COLOR if is_sword else p.RAIL_VM_COLOR
		vm.mesh = p.sword_vm_mesh if is_sword else p.rail_vm_mesh
		var rest: Vector3 = vm.get_meta("rest_rot")
		var pose := rest
		if is_sword:
			pose = rest + Vector3(0.12, 0.0, 0.35 if i == 0 else -0.35)
		vm.rotation = pose
		vm.set_meta("pose_rot", pose)
	if p.bot_controlled and p.is_node_ready():
		# Bot loadout is set post-_ready (PracticeSpawner), after the puppet
		# materials were duplicated — safe to tint per arm type here.
		for i in 2:
			var pmat := (
				(p.puppet_arm_l if i == 0 else p.puppet_arm_r).material_override
				as StandardMaterial3D
			)
			pmat.albedo_color = p.SWORD_VM_COLOR if p.arm_types[i] == "sword" else p.RAIL_VM_COLOR


static func update_viewmodels(p: CharacterBody3D, delta: float) -> void:
	for i in 2:
		var vm: MeshInstance3D = p.vm_left if i == 0 else p.vm_right
		var mat := vm.material_override as StandardMaterial3D
		if p.arm_types[i] == "rail":
			var arm: RailArm = p.arm_left if i == 0 else p.arm_right
			if arm.state == RailArm.ArmState.COOLDOWN:
				# Cooldown readout (Lily's spec): faint yellow, brightest
				# right after the shot, fading to nothing at ready.
				var frac: float = arm.cooldown / p.combat.cooldown
				mat.emission = p.VM_COOLDOWN_COLOR
				mat.emission_energy_multiplier = frac * 1.2
			else:
				mat.emission = p.VM_EMISSION_WARM
				mat.emission_energy_multiplier = arm.progress() * 3.0
		else:
			# only the lunging blade flares — blue, matching the world trail;
			# a cooling blade fades yellow like the rail; the rest idle warm
			# (emission reset matters: rail shares the material per side)
			var flaring: bool = p.sword_active > 0.0 and p.sword_side == ("L" if i == 0 else "R")
			var cd_frac: float = p.sword_cd[i] / p.combat.sword_lunge_cooldown
			if flaring:
				mat.emission = p.SWORD_FLARE_COLOR
				mat.emission_energy_multiplier = 2.5
			elif cd_frac > 0.0:
				mat.emission = p.VM_COOLDOWN_COLOR
				mat.emission_energy_multiplier = cd_frac * 1.2
			else:
				mat.emission = p.VM_EMISSION_WARM
				mat.emission_energy_multiplier = 0.3
		vm.position = vm.position.lerp(vm.get_meta("rest_pos"), 1.0 - exp(-12.0 * delta))
		vm.rotation = vm.rotation.lerp(vm.get_meta("pose_rot"), 1.0 - exp(-10.0 * delta))
