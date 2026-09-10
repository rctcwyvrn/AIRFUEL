# bgm_player.gd

## Function

Combat background music playback (DESIGN.md §16; Lily, 2026-09-10: "bgm
for combat" — arena only, menu and parkour stay silent). Attached to the
arena's `Bgm` AudioStreamPlayer node so music starts when the combat map
loads and stops naturally on any scene change back to the menu.

## Interface

- `class_name BgmPlayer extends AudioStreamPlayer` — attach to an
  AudioStreamPlayer node whose `stream` and `volume_db` the scene sets
  (graybox_corridor.tscn: `res://sounds/bgm.wav` at −10 dB).
- No exports, no methods, no signals — the node is otherwise a plain
  AudioStreamPlayer.

## Implementation

- `_ready()` calls `play()` unless `DisplayServer.get_name()` is
  `"headless"`. Playback is script-driven instead of the scene's
  `autoplay` flag because the headless dedicated server also loads the
  arena: a stream still playing at forced quit leaks its
  `AudioStreamPlaybackWAV` (ObjectDB warning at exit), which would break
  the "verify runs are silent" convention.
- Looping lives in the wav's import settings (`bgm.wav.import`,
  `edit/loop_mode=1` forward), not in code.

## Assertions

- The headless guard must survive edits — the dedicated server never
  plays audio, and the arena smoke run
  (`godot4 --headless --path game res://maps/graybox_corridor.tscn
  --quit-after 300`) must stay silent.
- No gameplay effect: this node is pure audio; removing it must not
  change any tick's outcome.
