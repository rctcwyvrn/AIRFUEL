# fingerprint.tscn

## Function

Launcher scene for the trajectory-fingerprint harness (`fingerprint.gd`):
lets the tool run headless as a plain scene argument without touching the
project's main scene.

## Interface

- Run: `godot4 --headless --path game res://tools/fingerprint.tscn`.
- Single root `FingerprintHarness` (Node) with `fingerprint.gd` attached;
  the harness instances `parkour_track.tscn` under itself at runtime.

## Implementation

Deliberately minimal — the track is loaded from code, not instanced here,
so the scene never needs regenerating when the track does.

## Assertions

- Stays a one-node scene; all behavior lives in `fingerprint.gd`.
- No `uid` attributes hand-written (editor adds them).
