# recording-harness

Records bot-vs-bot gameplay videos of Airfuel — no OBS, no window, no GPU
needed. Godot's Movie Maker mode renders every frame offline under a virtual
X display (`xvfb`), so output is deterministic and works on headless
WSL2/NixOS; `ffmpeg` converts the raw MJPEG AVI to an H.264 MP4. All
dependencies are fetched via nix (`nix-shell -p xvfb-run ffmpeg` around the
project's own `shell.nix` for `godot4`).

## Usage

```sh
recording-harness/record.sh                       # 2 min: rail+rail POV vs sword+sword
recording-harness/record.sh -d 60 -o duel.mp4     # 1 min, custom output path
recording-harness/record.sh -- --pov 2 --enemy 0  # sword+sword POV vs rail+rail
recording-harness/record.sh -d 30 -- --pov 1 --enemy 1 --countdown 3.0
```

- `-d <seconds>` video length (default 120), `-r WxH` resolution (default
  1920x1080 — applied via a transient `game/override.cfg`, since Movie
  Maker records at the project viewport size and ignores `--resolution`),
  `-o <path>` output MP4 (default
  `recording-harness/botmatch_<timestamp>.mp4`).
- After `--`: `--pov` / `--enemy` are loadout indices (0 rail+rail,
  1 rail+sword, 2 sword+sword), `--countdown` is the per-round reset
  countdown in seconds (default 1.0 — short, so the video isn't mostly
  frozen 3-2-1; the game's normal value is 3.0).
- Render speed is ~10–20% of realtime on the llvmpipe software rasterizer
  (resolution-dependent): a 2 min video takes ~12 min at 900p, ~20 min at
  1080p. Output is 60 fps.

## How it works

`record.sh` copies the three `rec_botmatch*` files into `game/` (Godot can
only load scenes under `res://`), runs the render, and **always deletes the
copies again** (trap on exit), so the game project — and its sidecar-doc
convention, which these harness files are deliberately outside of — stays
untouched.

The harness scene loads `graybox_corridor.tscn`, frees the human `Player`,
and spawns two `bot_controlled` bodies (see `game/src/bot/`) cross-wired as
each other's opponents, with an endless kill → respawn-both round loop. The
POV bot gets the camera, first-person viewmodels, and the HUD (adopted
directly, bypassing the HUD's human-only adoption); its own third-person
meshes are hidden. Round countdown is overridden on a *duplicated*
`MovementConfig` so the shared `default_tuning.tres` is never mutated.

## Maintenance notes

- The harness leans on the same seams as practice mode: `bot_controlled`,
  `BotController.opponent` (assigned directly here — bot-vs-bot is not a
  supported in-game mode), offline `apply_damage` signal emission, and
  `hud.player`. If any of those change, this harness is the second caller
  to check.
- The corridor spawn constants (`POV_SPAWN` etc. in
  `rec_botmatch_setup.gd`) mirror the map's Player placement; update them
  if the map's spawn moves.
