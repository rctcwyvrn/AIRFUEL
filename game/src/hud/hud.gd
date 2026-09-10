extends CanvasLayer

@onready var fuel_bar: ProgressBar = $FuelBar
@onready var fuel_label: Label = $FuelLabel
@onready var speed_label: Label = $SpeedLabel
@onready var state_label: Label = $StateLabel
@onready var charge_l: ProgressBar = $ChargeL
@onready var charge_r: ProgressBar = $ChargeR
@onready var hit_label: Label = $HitLabel
@onready var lock_label: Label = $LockLabel
@onready var controls_hint: Control = $ControlsHint
@onready var score_label: Label = $ScoreLabel
@onready var loadout_label: Label = $LoadoutLabel
@onready var death_flash: ColorRect = $DeathFlash
@onready var hit_flash: ColorRect = $HitFlash
@onready var threat_ring: ThreatRing = $ThreatRing
@onready var hp_pips: Control = $HpPips
@onready var sword_warn_label: Label = $SwordWarnLabel
@onready var kill_banner: Label = $KillBanner
@onready var kill_feed: VBoxContainer = $KillFeed
@onready var map_prism: Control = $MapPrism
@onready var map_back: ColorRect = $MapBack
@onready var timer_label: Label = $TimerLabel
@onready var countdown_label: Label = $CountdownLabel

const KEY_DIM := Color(0.5, 0.5, 0.55, 0.25)
const KEY_LIT := Color(1.0, 0.75, 0.3, 0.9)
const KEY_LAYOUT: Array = [
	["move_forward", "W", 34, 0, 30],
	["move_left", "A", 0, 34, 30],
	["move_back", "S", 34, 34, 30],
	["move_right", "D", 68, 34, 30],
	["down_dash", "Q", 110, 34, 30],
	["dash", "SHIFT", 0, 68, 64],
	["jump", "SPACE", 68, 68, 72],
	["fire_left", "LMB", 0, 102, 47],
	["fire_right", "RMB", 51, 102, 47],
	["respawn", "T", 110, 102, 30],
]

const PIP_LIT := Color(1.0, 0.55, 0.1, 0.95)
const PIP_LOW := Color(1.0, 0.15, 0.1, 0.95)
const PIP_DIM := Color(0.5, 0.5, 0.55, 0.3)
const FEED_TTL := 4.0
const BANNER_TIME := 1.8

var player: AirfuelPlayer
var hit_timer := 0.0
var flash_alpha := 0.0
var hit_flash_alpha := 0.0
var go_timer := 0.0
var banner_timer := 0.0
var key_rects: Dictionary = {}
var pip_rects: Array[ColorRect] = []
var feed_items: Array = []  # {label: Label, ttl: float}


func _ready() -> void:
	Net.kill_reported.connect(_on_kill_reported)
	for k: Array in KEY_LAYOUT:
		if k[0] == "respawn" and Net.active:
			continue  # manual reset is solo-only
		var cr := ColorRect.new()
		cr.position = Vector2(k[2], k[3])
		cr.size = Vector2(k[4], 30)
		cr.color = KEY_DIM
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lb := Label.new()
		lb.text = k[1]
		lb.set_anchors_preset(Control.PRESET_FULL_RECT)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lb.add_theme_font_size_override("font_size", 12)
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cr.add_child(lb)
		controls_hint.add_child(cr)
		key_rects[k[0]] = cr


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = null
		for p: Node in get_tree().get_nodes_in_group("player"):
			if p.is_multiplayer_authority() and not p.ghost_controlled:
				player = p as AirfuelPlayer
				break
		if player == null:
			return
		player.shot_fired.connect(_on_shot_fired)
		player.damaged.connect(_on_damaged)
		player.died.connect(_on_died)
		map_prism.track = player
		_build_hp_pips(player.combat.hp_max)
	fuel_bar.max_value = player.config.fuel_max
	fuel_bar.value = player.fuel
	fuel_label.text = "AIRFUEL %d" % roundi(player.fuel)
	speed_label.text = "%d m/s" % roundi(player.horizontal_speed())
	var extra := ""
	if player.ramp_grace_timer > 0.0:
		extra = "   RAMP %.1f" % player.ramp_grace_timer
	if get_tree().get_first_node_in_group("finish") != null:
		timer_label.visible = true
		var t := player.run_time
		timer_label.text = "%d:%06.3f" % [int(t) / 60, fmod(t, 60.0)]
		timer_label.modulate = Color(0.3, 1.0, 0.4) if player.run_finished else Color(1, 1, 1)
	else:
		timer_label.visible = false
	if player.countdown > 0.0:
		countdown_label.visible = true
		countdown_label.text = str(ceili(player.countdown))
		go_timer = 0.7
	elif go_timer > 0.0:
		go_timer -= _delta
		countdown_label.text = "GO"
		countdown_label.visible = go_timer > 0.0
	else:
		countdown_label.visible = false
	var rec := "● REC   " if player.recording else ""
	state_label.text = "%sHP %d   %s%s" % [rec, player.hp, player.state_name(), extra]
	charge_l.value = player.arm_progress_left()
	charge_r.value = player.arm_progress_right()
	lock_label.visible = player.move_locked
	if hit_timer > 0.0:
		hit_timer -= _delta
		if hit_timer <= 0.0:
			hit_label.visible = false
	for action: String in key_rects:
		key_rects[action].color = KEY_LIT if Input.is_action_pressed(action) else KEY_DIM
	loadout_label.text = player.loadout_name()
	if flash_alpha > 0.0:
		flash_alpha = maxf(0.0, flash_alpha - _delta * 1.6)
		death_flash.color.a = flash_alpha
	if hit_flash_alpha > 0.0:
		hit_flash_alpha = maxf(0.0, hit_flash_alpha - _delta * 1.4)
	# At 1 hp the vignette never fully clears — a persistent "one more hit" tint
	hit_flash.color.a = maxf(hit_flash_alpha, 0.08 if player.hp == 1 else 0.0)
	for i in pip_rects.size():
		if i < player.hp:
			pip_rects[i].color = PIP_LOW if player.hp == 1 else PIP_LIT
		else:
			pip_rects[i].color = PIP_DIM
	_scan_threats()
	if banner_timer > 0.0:
		banner_timer -= _delta
		kill_banner.visible = banner_timer > 0.0
	for item: Dictionary in feed_items:
		item.ttl -= _delta
		var lb: Label = item.label
		lb.modulate.a = clampf(item.ttl, 0.0, 1.0)
		if item.ttl <= 0.0:
			lb.queue_free()
	feed_items = feed_items.filter(func(it: Dictionary) -> bool: return it.ttl > 0.0)
	score_label.visible = Net.active
	map_prism.visible = Net.active
	map_back.visible = Net.active
	if Net.active:
		var my_id := multiplayer.get_unique_id()
		var lines: PackedStringArray = []
		var ids: Array = Net.players.keys()
		ids.sort_custom(func(a: int, b: int) -> bool: return a == my_id)
		for id: int in ids:
			lines.append("%s  %d" % [_peer_tag(id, my_id), int(Net.scores.get(id, 0))])
		score_label.text = "\n".join(lines)


## Every enemy puppet is scanned each frame: rail charges feed the threat
## ring (warn on EVERY charge, DESIGN.md 15.2 — no filtering), and the
## nearest sword-carrier inside sword_warning_range drives the 8.2 proximity
## warning. Offline there are no puppets, so both stay silent for free.
func _scan_threats() -> void:
	var threats: Array = []
	var nearest_sword: AirfuelPlayer = null
	var nearest_dist := INF
	for p: Node in get_tree().get_nodes_in_group("player"):
		var enemy := p as AirfuelPlayer
		if (
			enemy == null
			or enemy == player
			or enemy.ghost_controlled
			or enemy.is_multiplayer_authority()
		):
			continue
		var bearing := _bearing_to(enemy.global_position)
		for i in 2:
			if enemy.arm_types[i] == "rail":
				var prog := enemy.display_arm_progress(i)
				if prog > 0.0:
					threats.append({angle = bearing, progress = prog})
		if "sword" in enemy.arm_types:
			var dist := player.global_position.distance_to(enemy.global_position)
			if dist <= player.combat.sword_warning_range and dist < nearest_dist:
				nearest_sword = enemy
				nearest_dist = dist
	threat_ring.charge_threats = threats
	if nearest_sword == null:
		sword_warn_label.visible = false
		return
	var ang := _bearing_to(nearest_sword.global_position)
	var side := "AHEAD"
	if absf(ang) > 3.0 * PI / 4.0:
		side = "BEHIND"
	elif absf(ang) > PI / 4.0:
		side = "RIGHT" if ang > 0.0 else "LEFT"
	sword_warn_label.text = "🗡WARNING️🗡 — %s" % side
	sword_warn_label.visible = true
	sword_warn_label.modulate.a = 0.6 + 0.4 * sin(Time.get_ticks_msec() / 90.0)


## Yaw-relative bearing to a world position: 0 = ahead, +PI/2 = right.
func _bearing_to(world_pos: Vector3) -> float:
	var local := player.global_transform.basis.inverse() * (world_pos - player.global_position)
	return atan2(local.x, -local.z)


func _on_damaged(_amount: int, from_id: int) -> void:
	hit_flash_alpha = 0.45
	var attacker: Node = Net.players.get(from_id)
	if attacker != null and is_instance_valid(attacker):
		threat_ring.add_damage_arc(_bearing_to((attacker as Node3D).global_position))


func _on_kill_reported(killer_id: int, victim_id: int) -> void:
	var my_id := multiplayer.get_unique_id()
	var lb := Label.new()
	lb.text = "%s  ▸  %s" % [_peer_tag(killer_id, my_id), _peer_tag(victim_id, my_id)]
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lb.add_theme_font_size_override("font_size", 15)
	kill_feed.add_child(lb)
	feed_items.append({label = lb, ttl = FEED_TTL})
	if killer_id == my_id:
		kill_banner.text = "YOU KILLED %s" % _peer_tag(victim_id, my_id)
		banner_timer = BANNER_TIME
	elif victim_id == my_id:
		kill_banner.text = "KILLED BY %s" % _peer_tag(killer_id, my_id)
		banner_timer = BANNER_TIME
	kill_banner.visible = banner_timer > 0.0


func _peer_tag(id: int, my_id: int) -> String:
	# Lobby matches know usernames; LAN falls back to peer-number tags.
	return "YOU" if id == my_id else Net.display_name(id)


func _build_hp_pips(hp_max: int) -> void:
	for pip: ColorRect in pip_rects:
		pip.queue_free()
	pip_rects.clear()
	var gap := 6.0
	var w := (hp_pips.size.x - gap * (hp_max - 1)) / hp_max
	for i in hp_max:
		var pip := ColorRect.new()
		pip.position = Vector2(i * (w + gap), 0.0)
		pip.size = Vector2(w, hp_pips.size.y)
		pip.color = PIP_LIT
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hp_pips.add_child(pip)
		pip_rects.append(pip)


func _on_died() -> void:
	flash_alpha = 0.7
	death_flash.color.a = flash_alpha


func _on_shot_fired(_side: String, result: String) -> void:
	match result:
		"kill":
			hit_label.text = "KILL"
			hit_label.modulate = Color(1.0, 0.25, 0.2)
		"head":
			hit_label.text = "HEADSHOT"
			hit_label.modulate = Color(1.0, 0.6, 0.15)
		"body":
			hit_label.text = "HIT"
			hit_label.modulate = Color(1, 1, 1)
		_:
			hit_label.text = ""
	hit_label.visible = hit_label.text != ""
	hit_timer = 0.45
