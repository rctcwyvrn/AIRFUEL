class_name PlayerRecorder
extends Object

## TAS tape recording (F5, solo-only), split out of player.gd. Same pattern
## as PlayerState: stateless static functions over the player body (typed
## CharacterBody3D); the `recording` flag and `tape_lines` buffer live on
## the player. Tape format is versioned ("# airfuel-tas v1") — change the
## line schema, bump the header, keep the ghost's loader backward-aware.
## The line's button bitmask shares its bit order with
## PlayerState.encode_cmd (jump|dash|fireL|fireR|swap|respawn).


## One tape line per physics tick: absolute look + this tick's cmds.
## Called from the LOCAL path of _physics_process; countdown ticks are
## skipped so a tape starts at GO, exactly like ghost playback does.
static func record_tick(p: CharacterBody3D) -> void:
	if not p.recording or p.countdown > 0.0:
		return
	var flags := (
		int(p.cmd_jump)
		| int(p.cmd_dash) << 1
		| int(p.cmd_fire_l) << 2
		| int(p.cmd_fire_r) << 3
		| int(p.cmd_swap) << 4
		| int(p.cmd_respawn) << 5
	)
	p.tape_lines.append(
		(
			"%.5f %.5f %.3f %.3f %.1f %d"
			% [
				p.rotation.y,
				p.head.rotation.x,
				p.cmd_move.x,
				p.cmd_move.y,
				1.0 if p.cmd_down_dash else 0.0,
				flags
			]
		)
	)


## Restart the tape buffer from a fresh header. Called on record start and
## on every respawn while recording — a recording is always one clean
## spawn-to-finish attempt, never a spliced teleport.
static func restart_tape(p: CharacterBody3D) -> void:
	p.tape_lines.clear()
	p.tape_lines.append(
		(
			"# airfuel-tas v1 map=%s tick_hz=%d loadout=%d"
			% [
				p.get_tree().current_scene.scene_file_path,
				Engine.physics_ticks_per_second,
				p.loadout_index
			]
		)
	)


## F5: record this run's inputs, one line per physics tick, for TAS ghost
## playback. Starting a recording respawns the player first so the tape
## begins from the exact spawn state; stopping writes user://tas/ and
## prints the path.
static func toggle(p: CharacterBody3D) -> void:
	if not p.recording:
		p._respawn()
		restart_tape(p)
		p.recording = true
		return
	p.recording = false
	DirAccess.make_dir_recursive_absolute("user://tas")
	var fname := "user://tas/run_%s.tas" % Time.get_datetime_string_from_system().replace(":", "-")
	var f := FileAccess.open(fname, FileAccess.WRITE)
	if f == null:
		push_error("Airfuel: could not write %s" % fname)
		return
	f.store_string("\n".join(p.tape_lines))
	f.close()
	print(
		(
			"Airfuel: TAS tape saved: %s (%d ticks) — real path: %s"
			% [fname, p.tape_lines.size() - 1, ProjectSettings.globalize_path(fname)]
		)
	)
