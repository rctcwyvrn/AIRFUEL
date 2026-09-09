# threat_ring.gd

## Function

The directional half of the Step 3 duel feedback (DESIGN.md §15.2): a
draw-only Control that renders threat bearings as arcs around the screen
center. Enemy rail charges are wedges that escalate with charge progress
(the defender's visual half of the §8.1 "loud charge" tell — one wedge per
charging arm, so a dual-rail stagger reads as two phases); incoming hits are
short-lived arcs toward the attacker.

## Interface

- `class_name ThreatRing extends Control`; script of `hud.tscn`'s
  `ThreatRing` node (full-rect, `mouse_filter = 2`).
- `charge_threats: Array` of `{angle: float, progress: float}` — overwritten
  every frame by `hud.gd._scan_threats`; never mutated here.
- `add_damage_arc(angle: float)` — event-driven, called from
  `hud.gd._on_damaged`; arcs self-expire after `DAMAGE_ARC_TTL` (1.2 s).
- Angles are yaw-relative bearings: 0 = ahead (drawn screen-up),
  +PI/2 = right. `hud.gd._bearing_to` is the producer.

## Implementation

`_process` decays damage-arc TTLs and calls `queue_redraw` every frame
(charge wedges change every frame anyway while anyone is charging). `_draw`
maps a bearing to `draw_arc` space by shifting −PI/2 (draw_arc's 0 is +x =
screen-right). Escalation is threefold so it reads peripherally: the wedge
*narrows* onto the true bearing (0.5 → 0.16 rad half-width), *reddens*
(orange → red), and *thickens/brightens* with progress. Damage arcs sit on
a smaller radius than charge wedges so the two never visually merge. All
radii/colors are cosmetic HUD constants, not gameplay tunables — same
category as the camera-feel literals.

## Assertions

- Draw-only: this node must never read game state itself — `hud.gd` owns
  the scan and feeds it (one-way HUD→player dependency stays intact).
- Escalation must be monotonic in `progress` — the wedge may never look
  *less* urgent as a charge nears completion.
- `mouse_filter` stays IGNORE (full-rect Control over the captured cursor —
  the mouse-look-eating hazard in hud.tscn.md).
