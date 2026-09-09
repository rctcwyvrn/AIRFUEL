# player.tscn

## Function

The playable character scene for Steps 1–3. Instanced by the active map for
solo play, and by `Net` (network.gd, preloaded `PLAYER_SCENE`) once per peer
in LAN play.

## Interface

- Root: `Player` (CharacterBody3D, **collision layer 4 / mask 5**; the
  layer scheme is 1 = world, 2 = targets, 4 = players — the TAS ghost's
  mask must be able to exclude players, so players cannot share layer 1)
  — script `player.gd`, group `"player"`,
  `config` wired to `default_tuning.tres`, `combat` to
  `default_combat.tres`.
- Node paths the script depends on: `CollisionShape3D`, `Head` (y = 1.7),
  `Head/Camera3D` (fov 100), `ArmLeft` and `ArmRight` (plain Nodes with
  `rail_arm.gd`, both sharing `default_combat.tres`),
  `Head/Camera3D/ViewmodelL` and `ViewmodelR` (graybox arm blocks).
- Maps position/rotate the instance root; forward is `-Z` (rotate 180° yaw to
  face `+Z`).

## Implementation

Capsule **1.2 r × 4.5 h** (dummy-sized — both players are big red targets
in PvP, per Lily) centered on the origin, so the body origin is at capsule
center, not the feet — spawn transforms need y ≥ ~2.3. Head sits at +1.7
(eye near the capsule top). `BodyMesh` is a matching red emissive capsule,
hidden for the authority (your own camera is inside it) and shown on remote
puppets, along with `PuppetArmL/R` — shoulder weapon blocks whose tint
(grey rail / silver sword) and charge glow are driven from synced state;
non-authority code duplicates their materials so multiple puppets tint
independently. Viewmodel meshes are swapped in code per loadout (chunky
rail block vs long thin blade with rolled/tilted pose) — the tscn only
ships the rail default. `ShadowMesh` is a matching capsule with `cast_shadow = 3`
(shadows-only) so you still cast your own shadow first-person. Viewmodels are 0.12×0.12×0.5 boxes at
(±0.35, −0.28, −0.55) under the camera, yawed ~4° inward, `cast_shadow` off,
each with its OWN emissive material (orange emission, energy 0 at rest) —
`player.gd` drives emission with charge progress and kicks position on fire.

The speed trail is code-built (no scene node): `player.gd` creates a
top-level MeshInstance3D and redraws a world-space LINE_STRIP each frame
from a rolling position history — one long thin orange line tracing the
recent flight path, alpha-fading toward the tail, cleared on respawn.
Drawn for every body (you, remotes, the ghost).

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
- `ShadowMesh` keeps `cast_shadow = 3` and `BodyMesh` stays `visible =
  false` in-scene; only non-authority code flips BodyMesh on — visible
  locally, either would fill your camera with red capsule interior.
- Collision capsule, ShadowMesh, and BodyMesh must stay the same size —
  the visual IS the hitbox; a mismatch makes shots feel wrong.
