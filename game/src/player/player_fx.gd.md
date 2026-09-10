# player_fx.gd

## Function

Stateless one-shot combat cosmetics (DESIGN.md §17 feedback beats), split
out of `player.gd`: the rail beam, the sword-lunge trail segment, and the
ejected canister. Pure visuals — nothing here may ever affect simulation.
Prediction replays skip these calls entirely (the `replaying` guard in
`player.gd`; the sword trail is driven from render-side `_process`), and
the headless server never makes them.

## Interface

- `class_name PlayerFx extends Object` — all-static, never instanced.
- `const CANISTER` — preload of `res://src/weapons/canister.tscn` (moved
  here from `player.gd`).
- `static spawn_beam(parent: Node, from: Vector3, to: Vector3) -> void` —
  fading emissive beam from muzzle to impact, added as a child of
  `parent` but positioned in world space. Callers: the shooter's own
  `_fire_rail` (parented next to the shooter), and `Net` when mirroring
  an opponent's shot fx on clients' REPLICA views.
- `static spawn_sword_trail(parent: Node, from: Vector3, to: Vector3) ->
  void` — one segment of the blue sword-lunge ribbon; caller is
  `PlayerTrails._update_sword_trail` (player_trails.gd), which drops
  segments along the lunge path.
- `static spawn_canister(shooter: CharacterBody3D, side_sign: float,
  cam: Transform3D) -> void` — spent canister ejected sideways from the
  firing arm (§8.1 bolt action); `side_sign` is +1 for the right arm,
  -1 for the left; `cam` is the shooter's camera transform at fire time.

## Implementation

- **`spawn_beam`**: a thin emissive BoxMesh (0.05×0.05×length) at the
  from/to midpoint, oriented with `look_at` (RIGHT up-vector fallback for
  near-vertical shots — `look_at` would error with a parallel up),
  unshaded, shadow casting off; alpha + emission tweened to 0 over 0.2 s,
  then freed by the tween callback. Beams shorter than 0.05 m are skipped
  (degenerate mesh / zero-length `look_at`).
- **`spawn_sword_trail`**: same skeleton as `spawn_beam` (unshaded emissive
  box, look_at with vertical fallback, alpha+emission tween → free, same
  0.05 m degenerate guard) but fatter (0.45×0.45), strong blue, brighter
  (emission energy 6), slower fade (0.45 s), and 0.3 m longer than the
  from→to span so consecutive segments overlap into a gapless ribbon.
- **`spawn_canister`**: instances `CANISTER` under the shooter's parent,
  spawns beside the camera on the firing side, inherits the shooter's
  velocity plus a sideways/up/back kick, and gets a random tumble. The
  canister scene owns its own lifetime.

## Assertions

- Pure visuals: nothing in this file may read or write simulation state,
  deal damage, or be required for a tick's outcome — `_simulate()` must
  behave identically whether or not these ever ran.
- Beam meshes always free themselves (tween callback) — a leaked beam per
  shot would accumulate fast.
- `spawn_beam` keeps its degenerate-length guard: a zero-length beam
  means a broken mesh and a `look_at` error.
