# player.tscn

## Function

The playable character scene for Step 1. Instanced once by the active map.

## Interface

- Root: `Player` (CharacterBody3D) — script `player.gd`, group `"player"`,
  `config` wired to `default_tuning.tres`, `combat` to
  `default_combat.tres`.
- Node paths the script depends on: `CollisionShape3D`, `Head` (y = 0.65),
  `Head/Camera3D` (fov 100), `ArmLeft` and `ArmRight` (plain Nodes with
  `rail_arm.gd`, both sharing `default_combat.tres`),
  `Head/Camera3D/ViewmodelL` and `ViewmodelR` (graybox arm blocks).
- Maps position/rotate the instance root; forward is `-Z` (rotate 180° yaw to
  face `+Z`).

## Implementation

Capsule 0.45 r × 1.8 h centered on the origin, so the body origin is at
capsule center (~waist), not the feet — spawn transforms need y ≥ ~1. Head
sits at +0.65 (eye height ~1.55). `ShadowMesh` is a matching capsule with
`cast_shadow = 3` (shadows-only): the player stays invisible first-person but
casts a shadow for platforming depth. Viewmodels are 0.12×0.12×0.5 boxes at
(±0.35, −0.28, −0.55) under the camera, yawed ~4° inward, `cast_shadow` off,
each with its OWN emissive material (orange emission, energy 0 at rest) —
`player.gd` drives emission with charge progress and kicks position on fire.

## Assertions

- Root stays in group `"player"` — the HUD finds the player through it.
- `config` must be assigned; `player.gd` dereferences it in `_ready` with no
  null guard.
- Keep the `Head`/`Head/Camera3D`/`ArmLeft`/`ArmRight` names and hierarchy —
  `player.gd` uses `@onready var` node paths, and yaw-on-body /
  pitch-on-head / roll-on-camera is the rotation contract.
- Both arms must reference the same `CombatConfig` resource as the player,
  or freeze timing and fire timing diverge.
- `mat_vm_l`/`mat_vm_r` must stay separate sub_resources — a shared material
  would make both arms glow when one charges.
- `ShadowMesh` keeps `cast_shadow = 3`; making it visible would clip the
  first-person camera.
