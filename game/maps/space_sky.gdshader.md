# space_sky.gdshader

## Function

Procedural spacescape sky for the graybox corridor (2026-09-10): the
corridor's translucent walls need something worth seeing through, and the
repo convention is asset-free hand-written files — so the entire sky
(stars, nebulae, sun) is shader math, no textures.

## Interface

- `shader_type sky`; no uniforms — everything is baked into the code, so
  the only consumer contract is "assign me to a Sky's ShaderMaterial"
  (done in `graybox_corridor.tscn`, sub_resource `sky_mat`).
- Reads `LIGHT0_*` built-ins: the sun disc/halo auto-aligns with the
  scene's first DirectionalLight and vanishes if the light is removed.

## Implementation

- Deep-space base gradient, slightly lighter toward the horizon so up/down
  still reads at speed.
- Two nebula layers from a 4-octave value-noise fbm (`hash13`/`vnoise`):
  broad cold purple + a sparser warm band in the brand orange.
- Two `star_layer` fields (dense-faint, sparse-bright): the view sphere is
  cut into cubic cells, a hash decides which cells hold a star, another
  hash places it inside the cell; per-star brightness variation avoids a
  flat-looking field. Stars are static — no time-based twinkle, nothing
  here reads TIME (deliberate: zero distraction during duels).
- Sun: `pow(dot, 1400)` disc + `pow(dot, 60)` halo tinted by
  `LIGHT0_COLOR`, so shadows on the track visibly belong to a sky object.

## Assertions

- Contributes almost no ambient light — the corridor's Environment must
  keep its explicit ambient (`ambient_light_source = 2`); removing that
  makes the interior unreadably dark (see graybox_corridor.tscn.md).
- Stays uniform-free and TIME-free: static output, safe for the sky
  radiance cubemap, and nothing to desync visually between clients.
- Godot's shader language has no implicit int→float: keep float literals
  (`vec3(1.0, 0.0, 0.0)`) if editing.
