# hud.tscn

## Function

The diagnostic HUD layout for Step 1. Instanced by the active map alongside
the player.

## Interface

- Root: `HUD` (CanvasLayer) with `hud.gd`.
- Children (names are the contract with `hud.gd`): `FuelBar` (ProgressBar,
  bottom-center, 440×24), `FuelLabel` (numeric readout centered on the bar),
  `SpeedLabel` (above the bar, 28px), `StateLabel` (top-left, 20px),
  `Crosshair` (4×4 ColorRect, screen center), `ChargeL`/`ChargeR` (vertical
  ProgressBars flanking the crosshair, fill bottom-to-top, max_value 1),
  `HitLabel` (below crosshair, hidden by default), `LockLabel` ("LOCKED",
  below that, hidden by default), `ControlsHint` (empty bottom-left Control,
  154×136 — `hud.gd` populates the key grid at runtime), `ScoreLabel`
  (top-right, orange, hidden offline), `LoadoutLabel` (bottom-right),
  `CountdownLabel` (center, 80px orange, hidden by default),
  `TimerLabel` (top-center, 30px, hidden by default — hud.gd
  drives it), `DeathFlash` (full-rect red ColorRect at alpha 0, MUST keep
  `mouse_filter = 2` and stays above gameplay readouts), `MapBack` (dark backdrop ColorRect under the map) + `MapPrism`
  (Control with `minimap.gd`, top-right, hidden offline — draws the
  rotating prism + player dots itself).

## Implementation

Anchor-based layout (bottom-center / top-left), so it survives window
resizes. Identity styling: all three ProgressBars share grey-translucent
background + orange (#FF8C1A) fill StyleBoxFlats; crosshair and LOCKED
label are the same orange. `FuelLabel` is declared after `FuelBar` and shares its rect —
declaration order keeps it drawn on top. All text is placeholder; `hud.gd`
overwrites it every frame.

## Assertions

- Renaming/moving any child breaks `hud.gd`'s `@onready` paths — update both
  together.
- Keep this scene player-agnostic: no references into `player.tscn`, the
  script discovers the player by group.
- Every non-Label Control (ColorRect, ProgressBars) must keep
  `mouse_filter = 2` (IGNORE). The captured cursor sits at screen center —
  a default-filter Control there (the Crosshair!) consumes
  InputEventMouseMotion before the player's `_unhandled_input` sees it,
  killing mouse look entirely. This bug shipped once; don't re-ship it.
