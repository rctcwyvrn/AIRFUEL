# player.tscn

## Function

The playable character scene for Step 1. Instanced once by the active map.

## Interface

- Root: `Player` (CharacterBody3D) — script `player.gd`, group `"player"`,
  `config` wired to `default_tuning.tres`.
- Node paths the script depends on: `CollisionShape3D`, `Head` (y = 0.65),
  `Head/Camera3D` (fov 100).
- Maps position/rotate the instance root; forward is `-Z` (rotate 180° yaw to
  face `+Z`).

## Implementation

Capsule 0.45 r × 1.8 h centered on the origin, so the body origin is at
capsule center (~waist), not the feet — spawn transforms need y ≥ ~1. Head
sits at +0.65 (eye height ~1.55). No mesh yet; the capsule is invisible, which
is fine first-person.

## Assertions

- Root stays in group `"player"` — the HUD finds the player through it.
- `config` must be assigned; `player.gd` dereferences it in `_ready` with no
  null guard.
- Keep the `Head`/`Head/Camera3D` names and hierarchy — `player.gd` uses
  `@onready var` node paths, and yaw-on-body / pitch-on-head / roll-on-camera
  is the rotation contract.
