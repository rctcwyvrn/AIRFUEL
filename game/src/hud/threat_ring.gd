class_name ThreatRing
extends Control

## Directional threat ring around the screen center (DESIGN.md 15.2):
## enemy rail charges draw as wedges that tighten, brighten, and thicken as
## the charge builds (warn on EVERY charge — no filtering), and incoming
## damage draws as short-lived arcs toward the attacker. Angles are
## yaw-relative bearings (0 = ahead, +PI/2 = right), filled by hud.gd.

const RING_RADIUS := 110.0
const DAMAGE_RADIUS := 92.0
const CHARGE_COLOR := Color(1.0, 0.55, 0.1)
const CHARGE_FULL_COLOR := Color(1.0, 0.15, 0.1)
const DAMAGE_COLOR := Color(1.0, 0.12, 0.08)
const ARC_POINTS := 16
const DAMAGE_ARC_TTL := 1.2

var charge_threats: Array = []  # {angle: float, progress: float}, per frame
var damage_arcs: Array = []  # {angle: float, ttl: float}, event-driven


func _process(delta: float) -> void:
	for arc: Dictionary in damage_arcs:
		arc.ttl -= delta
	damage_arcs = damage_arcs.filter(func(a: Dictionary) -> bool: return a.ttl > 0.0)
	queue_redraw()


func add_damage_arc(angle: float) -> void:
	damage_arcs.append({angle = angle, ttl = DAMAGE_ARC_TTL})


func _draw() -> void:
	var center := size * 0.5
	for t: Dictionary in charge_threats:
		var progress: float = t.progress
		# Escalation: the wedge narrows onto the true bearing, reddens, and
		# thickens as the charge completes — urgency without reading a number.
		var half_width := lerpf(0.5, 0.16, progress)
		var color := CHARGE_COLOR.lerp(CHARGE_FULL_COLOR, progress)
		color.a = lerpf(0.35, 1.0, progress)
		_draw_bearing_arc(
			center, RING_RADIUS, t.angle, half_width, color, lerpf(3.0, 9.0, progress)
		)
	for a: Dictionary in damage_arcs:
		var color := DAMAGE_COLOR
		color.a = clampf(a.ttl / DAMAGE_ARC_TTL, 0.0, 1.0)
		_draw_bearing_arc(center, DAMAGE_RADIUS, a.angle, 0.5, color, 6.0)


func _draw_bearing_arc(
	center: Vector2,
	radius: float,
	bearing: float,
	half_width: float,
	color: Color,
	thickness: float
) -> void:
	# Bearing 0 = ahead = screen-up; draw_arc's 0 is +x, so shift by -PI/2.
	draw_arc(
		center,
		radius,
		bearing - PI / 2.0 - half_width,
		bearing - PI / 2.0 + half_width,
		ARC_POINTS,
		color,
		thickness,
		true
	)
