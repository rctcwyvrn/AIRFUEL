class_name BgmPlayer
extends AudioStreamPlayer

## Combat background music (per Lily: BGM is for combat maps only — the
## menu and parkour stay silent). Attached to the arena's Bgm node.
## Playback starts from _ready instead of the autoplay flag so the
## headless dedicated server — which also loads the arena scene — never
## plays it: a stream still playing at forced quit leaks its
## AudioStreamPlaybackWAV and trips the "silent smoke run" verify.


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	play()
