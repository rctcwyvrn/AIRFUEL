class_name AirfuelPlayer
extends CharacterBody3D

## Roadmap Steps 1 + 2: movement, plus dual railgun arms vs stationary targets.
## Netplay is server-authoritative (§20.2 N1): one body class plays four roles
## (see NetRole) — the same _simulate() tick runs everywhere, and client
## prediction replays it against server snapshots.
##
## This file is the player's identity and orchestration: state, roles, the
## tick, prediction, respawn, and the HUD-facing surface. The mechanics live
## in sibling static-helper classes over this body (the PlayerState pattern —
## all state stays HERE): PlayerMovement (§4/§5 movement),
## PlayerCombat (§7/§8 arms + weapon visuals), PlayerRecorder (TAS tapes),
## plus the existing PlayerState (codec) and PlayerFx (one-shot cosmetics).

enum MoveState { GROUNDED, AIRBORNE, WALLRUN }

## Who simulates this body, and from what input:
## LOCAL     — authoritative + local human input (offline solo, LAN host's own
##             body, TAS ghosts via ghost_controlled).
## DRIVEN    — authoritative + net cmds (a remote client's body on the server).
## PREDICTED — the client's own body: simulates immediately from local input,
##             sends cmds to the server, reconciles against snapshots.
## REPLICA   — render-only puppet of another player on a client; never
##             simulated here, fed by snapshots.
enum NetRole { LOCAL, DRIVEN, PREDICTED, REPLICA }

signal shot_fired(side: String, result: String)
signal damaged(amount: int, from_id: int)
signal died
signal respawned

@export var ghost_controlled := false
@export var bot_controlled := false
@export var config: MovementConfig
@export var combat: CombatConfig
@export var mouse_sensitivity := 0.0022

# Set by Net before add_child; scene default LOCAL keeps offline untouched.
var role := NetRole.LOCAL

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var arm_left: RailArm = $ArmLeft
@onready var arm_right: RailArm = $ArmRight
@onready var vm_left: MeshInstance3D = $Head/Camera3D/ViewmodelL
@onready var vm_right: MeshInstance3D = $Head/Camera3D/ViewmodelR
@onready var puppet_arm_l: MeshInstance3D = $PuppetArmL
@onready var puppet_arm_r: MeshInstance3D = $PuppetArmR

var state := MoveState.AIRBORNE
var fuel := 0.0

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

var base_fov := 100.0
var spawn_transform: Transform3D

var move_locked := false
var pending_arms: Array[RailArm] = []
var shot_gap_timer := 0.0

# True while re-simulating buffered ticks during prediction reconciliation:
# gameplay math runs, one-shot effects (beams, canisters, hitmarker signals,
# viewmodel kicks) are suppressed so replays don't double them.
var replaying := false

var hp := 2
var _net_target_pos := Vector3.ZERO

# PREDICTED-role machinery: cmd/state history for reconciliation replays.
# The cmd/state wire formats live in PlayerState (player_state.gd).
var net_tick := 0

# Newest server tick this client has seen (PREDICTED: from snapshots) or the
# shooter's cmds reported (DRIVEN: via PlayerState.apply_cmd) — the rewind
# target for this player's shots (§20.2 N2). 0 = never seen / no rewind.
var seen_server_tick := 0
var _cmd_history: Dictionary = {}  # tick -> PackedFloat32Array cmd
var _state_history: Dictionary = {}  # tick -> capture_state()
var _pending_snapshot: Array = []  # [ack_tick, state]; applied at tick start

# Per-tick command state: filled from Input for humans, written directly by
# a controller (TAS ghost, bots) when ghost_controlled/bot_controlled.
var cmd_move := Vector2.ZERO
var cmd_down_dash := false
var cmd_jump := false
var cmd_dash := false
var cmd_fire_l := false
var cmd_fire_r := false
var cmd_swap := false
var cmd_respawn := false

var recording := false
var tape_lines: PackedStringArray = []

var run_time := 0.0
var run_finished := false
var countdown := 0.0

const LOADOUTS: Array = [["rail", "rail"], ["rail", "sword"], ["sword", "sword"]]
const RAIL_VM_COLOR := Color(0.45, 0.47, 0.5)
const SWORD_VM_COLOR := Color(0.82, 0.84, 0.88)
const SWORD_FLARE_COLOR := Color(0.2, 0.5, 1.0)
const VM_EMISSION_WARM := Color(1.0, 0.55, 0.15)
const VM_COOLDOWN_COLOR := Color(1.0, 0.9, 0.3)
var loadout_index := 0
var arm_types: Array = ["rail", "rail"]
var sword_cd: Array = [0.0, 0.0]
var sword_active := 0.0
var sword_side := "L"
var _net_prog := Vector2.ZERO
var rail_vm_mesh: BoxMesh
var sword_vm_mesh: BoxMesh
var _trails: PlayerTrails


func _ready() -> void:
	fuel = config.fuel_max
	hp = combat.hp_max
	spawn_transform = global_transform
	_net_target_pos = global_position
	arm_left.charge_complete.connect(func() -> void: pending_arms.append(arm_left))
	arm_right.charge_complete.connect(func() -> void: pending_arms.append(arm_right))
	# Per-body viewmodel materials: scene sub_resources are shared across
	# instances, so with two simulating bodies (practice bot, TAS ghost)
	# charge glow / lunge flare / tints cross-bleed without this.
	vm_left.material_override = vm_left.material_override.duplicate()
	vm_right.material_override = vm_right.material_override.duplicate()
	vm_left.set_meta("rest_pos", vm_left.position)
	vm_right.set_meta("rest_pos", vm_right.position)
	vm_left.set_meta("rest_rot", vm_left.rotation)
	vm_right.set_meta("rest_rot", vm_right.rotation)
	rail_vm_mesh = BoxMesh.new()
	rail_vm_mesh.size = Vector3(0.12, 0.12, 0.5)
	sword_vm_mesh = BoxMesh.new()
	sword_vm_mesh.size = Vector3(0.05, 0.2, 1.05)
	PlayerCombat.apply_loadout_visuals(self)
	_trails = PlayerTrails.new()
	add_child(_trails)
	base_fov = camera.fov
	if ghost_controlled:
		# TAS/bot body: real physics, no human input, translucent orange.
		# Layer 0: nothing collides INTO the ghost; mask 1 = world ONLY.
		# The mask must exclude the player layer (4): a replay that can bump
		# a nearby player desyncs nondeterministically (shipped once as
		# "sometimes the ghost gets stuck").
		collision_layer = 0
		collision_mask = 1
		camera.current = false
		set_process_unhandled_input(false)
		vm_left.visible = false
		vm_right.visible = false
		var bm := $BodyMesh as MeshInstance3D
		bm.visible = true
		var gmat := (bm.material_override as StandardMaterial3D).duplicate()
		gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gmat.albedo_color = Color(1.0, 0.55, 0.1, 0.4)
		gmat.emission = Color(1.0, 0.55, 0.1, 1.0)
		bm.material_override = gmat
		var ghost_head := $Head/HeadMesh as MeshInstance3D
		ghost_head.visible = true
		ghost_head.material_override = gmat
	elif bot_controlled:
		# Practice opponent (Appendix A): a full combat participant — normal
		# collision, damageable, warned about by the HUD — but no camera
		# claim and no Input reads; a BotController child writes the cmd_*
		# fields. Rendered like a net puppet, charge tell included.
		camera.current = false
		set_process_unhandled_input(false)
		vm_left.visible = false
		vm_right.visible = false
		$BodyMesh.visible = true
		$Head/HeadMesh.visible = true
		for arm: MeshInstance3D in [puppet_arm_l, puppet_arm_r]:
			arm.material_override = arm.material_override.duplicate()
			arm.visible = true
	elif role == NetRole.REPLICA:
		# Render-only puppet: state-synced from snapshots, never simulated here
		camera.current = false
		set_physics_process(false)
		vm_left.visible = false
		vm_right.visible = false
		$BodyMesh.visible = true
		$Head/HeadMesh.visible = true
		# Shoulder weapon blocks: the remote player's loadout + charge tell.
		# Materials duplicated so multiple puppets tint independently.
		for arm: MeshInstance3D in [puppet_arm_l, puppet_arm_r]:
			arm.material_override = arm.material_override.duplicate()
			arm.visible = true
	elif role == NetRole.DRIVEN:
		# Server-side body of a remote client: full simulation from net cmds.
		# Rendered like a puppet on a LAN host's screen; headless elsewhere.
		camera.current = false
		set_process_unhandled_input(false)
		vm_left.visible = false
		vm_right.visible = false
		$BodyMesh.visible = true
		$Head/HeadMesh.visible = true
		for arm: MeshInstance3D in [puppet_arm_l, puppet_arm_r]:
			arm.material_override = arm.material_override.duplicate()
			arm.visible = true
	else:
		# LOCAL or PREDICTED: this machine's own first-person body.
		# Explicit claim: auto-current fails when a remote puppet's camera
		# entered the viewport first (client-side join order)
		camera.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if role == NetRole.REPLICA or role == NetRole.DRIVEN:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x, -PI / 2 + 0.05, PI / 2 - 0.05)
	elif event.is_action_pressed("ui_cancel"):
		var captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED)


func _physics_process(delta: float) -> void:
	if role == NetRole.PREDICTED:
		# Prediction: reconcile any queued server snapshot first (inside the
		# physics frame, so replay's move_and_slide uses the physics delta),
		# then simulate this tick immediately from local input and ship the
		# cmd to the server.
		_maybe_reconcile()
		_gather_input()
		net_tick += 1
		var cmd := PlayerState.encode_cmd(self)
		_cmd_history[net_tick] = cmd
		Net.send_cmd(cmd)
		_simulate(delta)
		_state_history[net_tick] = capture_state()
		_camera_feel(delta)
		PlayerCombat.update_viewmodels(self, delta)
		return
	if role == NetRole.LOCAL:
		_gather_input()
	_simulate(delta)  # DRIVEN: cmds were written by MatchHost before this tick
	if role == NetRole.DRIVEN:
		return
	_camera_feel(delta)
	PlayerCombat.update_viewmodels(self, delta)
	PlayerRecorder.record_tick(self)


## One full gameplay tick from the current cmd_* fields: timers, arms, sword,
## movement, collision, respawn checks, then the arm charge cycles. This is
## the re-runnable unit client prediction replays — everything the outcome of
## a tick depends on lives in here (and in capture_state()); everything
## visual-only (camera feel, viewmodels, recording, net sends) stays out.
func _simulate(delta: float) -> void:
	if countdown > 0.0:
		# 3-2-1 after any reset: frozen in place (look around freely); the
		# run clock, tape recording, and ghost playback all wait for GO
		countdown -= delta
		velocity = Vector3.ZERO
		return
	if not run_finished:
		run_time += delta
	shot_gap_timer = maxf(0.0, shot_gap_timer - delta)
	dash_cooldown_timer = maxf(0.0, dash_cooldown_timer - delta)
	double_jump_timer = maxf(0.0, double_jump_timer - delta)
	wall_rearm_timer = maxf(0.0, wall_rearm_timer - delta)
	wall_coyote_timer = maxf(0.0, wall_coyote_timer - delta)
	ground_coyote_timer = maxf(0.0, ground_coyote_timer - delta)
	jump_buffer_timer = maxf(0.0, jump_buffer_timer - delta)
	sword_cd[0] = maxf(0.0, sword_cd[0] - delta)
	sword_cd[1] = maxf(0.0, sword_cd[1] - delta)
	if sword_active > 0.0:
		sword_active -= delta
		PlayerCombat.sword_hit_check(self)
	if cmd_jump:
		jump_buffer_timer = config.jump_buffer_time

	move_locked = arm_left.is_locking() or arm_right.is_locking()
	PlayerCombat.handle_arms(self)

	var wish := Vector3.ZERO if move_locked else PlayerMovement.wish_dir(self)

	match state:
		MoveState.GROUNDED:
			PlayerMovement.ground_move(self, wish, delta)
		MoveState.AIRBORNE:
			PlayerMovement.air_move(self, wish, delta)
		MoveState.WALLRUN:
			PlayerMovement.wallrun_move(self, delta)

	PlayerMovement.handle_dashes(self)

	var speed := velocity.length()
	if speed > config.terminal_velocity:
		# Soft ceiling: overspeed (sword lunge) decays fast instead of clamping
		velocity *= (
			move_toward(speed, config.terminal_velocity, config.overspeed_decay * delta) / speed
		)
	if move_locked:
		# Charging bleeds you down to a slower, more readable trajectory
		velocity = velocity.limit_length(combat.charge_speed_cap)
	velocity.y = maxf(velocity.y, -config.terminal_fall_speed)

	var pre_slide_velocity := velocity
	move_and_slide()
	if state != MoveState.WALLRUN:
		PlayerMovement.apply_glide(self, pre_slide_velocity)
	PlayerMovement.update_state(self)

	var manual_respawn := cmd_respawn and not Net.active
	if manual_respawn or global_position.y < config.kill_y:
		_respawn()

	# Arms advance at tick end (they were self-processing child nodes, which
	# ran after the parent) so a completed charge fires next tick, not this one
	arm_left.step(delta)
	arm_right.step(delta)


## Queues a server snapshot; applied at the next tick's start so the replay
## runs inside a physics frame (move_and_slide picks up the physics delta).
func on_server_snapshot(ack_tick: int, server_state: PackedFloat32Array) -> void:
	if role != NetRole.PREDICTED:
		return
	_pending_snapshot = [ack_tick, server_state]


func _maybe_reconcile() -> void:
	if _pending_snapshot.is_empty():
		return
	var ack: int = _pending_snapshot[0]
	var server_state: PackedFloat32Array = _pending_snapshot[1]
	_pending_snapshot = []
	var predicted: PackedFloat32Array = _state_history.get(ack, PackedFloat32Array())
	for t: int in _state_history.keys():
		if t <= ack:
			_state_history.erase(t)
			_cmd_history.erase(t)
	if PlayerState.agree(predicted, server_state):
		return
	# Misprediction: rewind to the server's truth and replay the cmds it
	# hasn't seen yet. Live view angles are preserved across the replay —
	# the mouse may have moved since the last recorded cmd.
	var live_yaw := rotation.y
	var live_pitch := head.rotation.x
	var delta := 1.0 / float(Engine.physics_ticks_per_second)
	replaying = true
	restore_state(server_state)
	for t: int in range(ack + 1, net_tick + 1):
		var c: PackedFloat32Array = _cmd_history.get(t, PackedFloat32Array())
		if not c.is_empty():
			PlayerState.apply_cmd(self, c)
		_simulate(delta)
		_state_history[t] = capture_state()
	replaying = false
	rotation.y = live_yaw
	head.rotation.x = live_pitch


## Render-state row the server sends about this body for other clients'
## replicas: [pos*3, vel*3, yaw, pitch, progL, progR, loadout, hp,
## sword_active]. The peer id deliberately travels OUTSIDE this array, as a
## real int — 32-bit floats silently corrupt 10-digit ENet peer ids (24-bit
## mantissa).
func render_state() -> PackedFloat32Array:
	var r := PackedFloat32Array()
	r.resize(13)
	var p := global_position
	r[0] = p.x
	r[1] = p.y
	r[2] = p.z
	r[3] = velocity.x
	r[4] = velocity.y
	r[5] = velocity.z
	r[6] = rotation.y
	r[7] = head.rotation.x
	r[8] = arm_progress_left()
	r[9] = arm_progress_right()
	r[10] = float(loadout_index)
	r[11] = float(hp)
	r[12] = sword_active
	return r


## Applies a render-state row to this REPLICA (position eased in _process).
func apply_replica(r: PackedFloat32Array) -> void:
	_net_target_pos = Vector3(r[0], r[1], r[2])
	velocity = Vector3(r[3], r[4], r[5])
	rotation.y = r[6]
	head.rotation.x = r[7]
	_net_prog = Vector2(r[8], r[9])
	hp = int(r[11])
	# Safe to write directly: replicas never simulate, so nothing ticks it.
	sword_active = r[12]
	if int(r[10]) != loadout_index:
		loadout_index = int(r[10])
		arm_types = LOADOUTS[loadout_index]
		for i in 2:
			var mat := (
				(puppet_arm_l if i == 0 else puppet_arm_r).material_override as StandardMaterial3D
			)
			mat.albedo_color = SWORD_VM_COLOR if arm_types[i] == "sword" else RAIL_VM_COLOR


## Client-side arrival of an authoritative damage event (via Net._ev_damage):
## syncs hp and emits the HUD-facing signals from inside the class.
func on_net_damage(attacker_id: int, hp_left: int) -> void:
	hp = hp_left
	damaged.emit(1, attacker_id)
	if hp_left <= 0:
		died.emit()


## Server-side authoritative damage (replaces the LAN-trust take_damage rpc:
## only LOCAL/DRIVEN bodies on the simulating process ever run this).
func apply_damage(amount: int, from_id: int) -> bool:
	hp -= amount
	var killed := hp <= 0
	if Net.match_host != null:
		Net.match_host.on_damage(self, from_id)  # respawns us on a kill
	else:
		# Offline (practice duels): no server events exist, so the HUD-facing
		# signals emit directly here; PracticeSpawner respawns on death.
		damaged.emit(amount, from_id)
		if killed:
			died.emit()
	return killed


## Does this body run real simulation on this machine? (KillZones etc. act on
## simulating bodies and must ignore render-only replicas.)
func sim_active() -> bool:
	return role != NetRole.REPLICA


func _process(delta: float) -> void:
	if role == NetRole.DRIVEN or bot_controlled:
		# LAN host renders server bodies directly (and the practice bot its
		# own): real arm progress drives the shoulder-block charge tell.
		for i in 2:
			var mat := (
				(puppet_arm_l if i == 0 else puppet_arm_r).material_override as StandardMaterial3D
			)
			var prog := arm_progress_left() if i == 0 else arm_progress_right()
			mat.emission_energy_multiplier = (prog * 3.0) if arm_types[i] == "rail" else 0.4
		return
	if role != NetRole.REPLICA:
		return
	global_position = global_position.lerp(_net_target_pos, 1.0 - exp(-20.0 * delta))
	# Rail arms glow with charge (the audible-tell stand-in); swords idle warm
	for i in 2:
		var mat := (
			(puppet_arm_l if i == 0 else puppet_arm_r).material_override as StandardMaterial3D
		)
		mat.emission_energy_multiplier = (_net_prog[i] * 3.0) if arm_types[i] == "rail" else 0.4


func set_loadout(index: int) -> void:
	loadout_index = index
	arm_types = LOADOUTS[loadout_index]
	arm_left.reset()
	arm_right.reset()
	pending_arms.clear()
	sword_cd = [0.0, 0.0]
	sword_active = 0.0
	PlayerCombat.apply_loadout_visuals(self)


func loadout_name() -> String:
	return "L %s | R %s" % [arm_types[0].to_upper(), arm_types[1].to_upper()]


## All-or-nothing fuel spend — the only way anything drains fuel.
func _spend(amount: float) -> bool:
	if fuel < amount:
		return false
	fuel -= amount
	return true


func _gather_input() -> void:
	if ghost_controlled or bot_controlled:
		return  # controller wrote the cmds (process_physics_priority < 0)
	cmd_move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	cmd_down_dash = Input.is_action_just_pressed("down_dash")
	cmd_jump = Input.is_action_just_pressed("jump")
	cmd_dash = Input.is_action_just_pressed("dash")
	cmd_fire_l = Input.is_action_just_pressed("fire_left")
	cmd_fire_r = Input.is_action_just_pressed("fire_right")
	cmd_swap = Input.is_action_just_pressed("swap_loadout")
	cmd_respawn = Input.is_action_just_pressed("respawn")
	if Input.is_action_just_pressed("record") and not Net.active:
		PlayerRecorder.toggle(self)  # TAS tapes are a solo instrument
	if Net.autoduel and role == NetRole.PREDICTED:
		_autoduel_cmds()


## Headless smoke duels: cheat-aim at the opponent's REPLICA (i.e. where it
## renders on THIS screen — exactly what rewind compensates for), strafe
## side to side, and fire on a cadence offset by peer id so the two duelists
## alternate: one strafes while the other charges. At high --fake-lag this
## only lands kills if server-side rewind works.
func _autoduel_cmds() -> void:
	var opp: AirfuelPlayer = null
	for p: Node in get_tree().get_nodes_in_group("player"):
		if p != self and p is AirfuelPlayer:
			opp = p
	if opp == null:
		return
	var to_opp: Vector3 = opp.global_position + Vector3.UP * 1.7 - camera.global_position
	rotation.y = atan2(-to_opp.x, -to_opp.z)
	head.rotation.x = atan2(to_opp.y, Vector2(to_opp.x, to_opp.z).length())
	var frames := Engine.get_physics_frames()
	# Opposite fire phases (higher peer id fires 150 ticks later) so one
	# duelist is mid-strafe while the other's shot lands — the rewind test.
	var ids: Array = Net.match_names.keys()
	var phase := 150 if not ids.is_empty() and multiplayer.get_unique_id() == ids.max() else 0
	cmd_fire_l = (frames + phase) % 300 == 0
	var strafe := 1.0 if floori(frames / 96.0) % 2 == 0 else -1.0
	cmd_move = Vector2.ZERO if move_locked else Vector2(strafe, 0.0)


func _camera_feel(delta: float) -> void:
	var target_roll := 0.0
	if state == MoveState.WALLRUN:
		var side := signf((-wall_normal).dot(global_transform.basis.x))
		target_roll = side * deg_to_rad(config.wallrun_camera_roll_deg)
	camera.rotation.z = lerpf(
		camera.rotation.z, target_roll, 1.0 - exp(-config.wallrun_camera_roll_speed * delta)
	)

	var hs := Vector3(velocity.x, 0.0, velocity.z).length()
	var target_fov := base_fov + clampf(hs - config.base_run_speed, 0.0, 25.0) * 0.6
	if state == MoveState.WALLRUN:
		target_fov += config.wallrun_fov_bonus
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-6.0 * delta))


## Crossing a FinishZone: freeze the run clock; a live recording stops and
## saves here too, so a finished run yields a complete tape of itself.
func finish_run() -> void:
	if run_finished:
		return
	run_finished = true
	if recording:
		PlayerRecorder.toggle(self)


func _respawn() -> void:
	global_transform = spawn_transform
	velocity = Vector3.ZERO
	fuel = config.fuel_max
	hp = combat.hp_max
	run_time = 0.0
	run_finished = false
	countdown = config.reset_countdown
	_trails.clear()
	# Deterministic reset: recordings and replays must start from identical
	# state, so no timer or arm state survives a respawn
	dash_cooldown_timer = 0.0
	double_jump_timer = 0.0
	wall_coyote_timer = 0.0
	ground_coyote_timer = 0.0
	jump_buffer_timer = 0.0
	wall_rearm_timer = 0.0
	ramp_grace_timer = 0.0
	sword_cd = [0.0, 0.0]
	sword_active = 0.0
	arm_left.reset()
	arm_right.reset()
	pending_arms.clear()
	if recording:
		# any reset (T, fall, F5) restarts the tape: a recording is always
		# one clean spawn-to-finish attempt, never a spliced teleport
		PlayerRecorder.restart_tape(self)
	respawned.emit()
	state = MoveState.AIRBORNE
	ramp_grace_timer = 0.0
	wallrun_time = 0.0
	wall_speed = 0.0
	head.rotation.x = 0.0


## State codec lives in PlayerState (player_state.gd) — fixed-layout
## PackedFloat32Array of everything _simulate()'s outcome depends on.
func capture_state() -> PackedFloat32Array:
	return PlayerState.capture(self)


func restore_state(s: PackedFloat32Array) -> void:
	PlayerState.restore(self, s)


func horizontal_speed() -> float:
	return Vector3(velocity.x, 0.0, velocity.z).length()


func arm_progress_left() -> float:
	if arm_types[0] == "sword":
		return 1.0 - clampf(sword_cd[0] / combat.sword_lunge_cooldown, 0.0, 1.0)
	return arm_left.progress()


func arm_progress_right() -> float:
	if arm_types[1] == "sword":
		return 1.0 - clampf(sword_cd[1] / combat.sword_lunge_cooldown, 0.0, 1.0)
	return arm_right.progress()


## Arm progress for HUD display regardless of role: replicas answer from the
## snapshot-fed values, simulated bodies (incl. DRIVEN on a LAN host's
## screen) from the real arm state. The HUD's charge-warning source.
func display_arm_progress(index: int) -> float:
	if role == NetRole.REPLICA:
		return _net_prog.x if index == 0 else _net_prog.y
	return arm_progress_left() if index == 0 else arm_progress_right()


func state_name() -> String:
	match state:
		MoveState.GROUNDED:
			return "GROUNDED"
		MoveState.WALLRUN:
			return "WALLRUN"
		_:
			return "AIRBORNE"
