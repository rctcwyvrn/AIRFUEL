# hud.tscn

## Function

The diagnostic HUD layout for Step 1. Instanced by the active map alongside
the player.

## Interface

- Root: `HUD` (CanvasLayer) with `hud.gd`.
- Children (names are the contract with `hud.gd`): `FuelBar` (ProgressBar,
  bottom-center, 440×24), `FuelLabel` (numeric readout centered on the bar),
  `SpeedLabel` (above the bar, 28px), `StateLabel` (top-left, 20px).

## Implementation

Anchor-based layout (bottom-center / top-left), so it survives window
resizes. `FuelLabel` is declared after `FuelBar` and shares its rect —
declaration order keeps it drawn on top. All text is placeholder; `hud.gd`
overwrites it every frame.

## Assertions

- Renaming/moving any child breaks `hud.gd`'s `@onready` paths — update both
  together.
- Keep this scene player-agnostic: no references into `player.tscn`, the
  script discovers the player by group.
