# spec_runner.tscn

## Function

Launcher scene for the definition-spec runner (`spec_runner.gd`), same
pattern as `fingerprint.tscn`: run the tool headless as a plain scene
argument without touching the project's main scene.

## Interface

- Run: `godot4 --headless --path game res://tools/spec_runner.tscn`.
- Single root `SpecRunner` (Node) with `spec_runner.gd` attached.

## Implementation

Deliberately minimal — spec discovery happens in code.

## Assertions

- Stays a one-node scene; all behavior lives in `spec_runner.gd`.
- No `uid` attributes hand-written (editor adds them).
