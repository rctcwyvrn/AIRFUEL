#!/usr/bin/env bash
# Bot-vs-bot gameplay recorder (see README.md). Runs Godot's Movie Maker mode
# under xvfb (no OBS, no window), converts to H.264 MP4 with ffmpeg. All
# dependencies come from nix: the project shell.nix provides godot4, and an ad
# hoc `nix-shell -p` provides xvfb-run + ffmpeg.
#
# Usage (from anywhere):
#   recording-harness/record.sh [-d seconds] [-r WxH] [-o out.mp4] [-- <bot args>]
#   bot args (passed to the harness scene): --pov 0|1|2  --enemy 0|1|2
#                                           --countdown <sec>
#   loadout indices: 0 rail+rail, 1 rail+sword, 2 sword+sword
# Defaults: 120s, 1920x1080, rail+rail POV vs sword+sword.
#
# Resolution: Movie Maker records at the project VIEWPORT size (it ignores
# --resolution), so a transient game/override.cfg overrides the viewport for
# the run; the exit trap removes it.
#
# The harness scripts must live in game/ to be loadable (res://), so this
# script copies them in as game/rec_botmatch* for the run and ALWAYS removes
# them (plus generated .uid files) afterwards — the repo stays clean even on
# failure. Render speed is ~15-20% of realtime on llvmpipe: a 2 min video
# takes ~12 min.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS="$ROOT/recording-harness"

DUR=120
OUT=""
RES="1920x1080"
while getopts "d:o:r:" opt; do
	case "$opt" in
	d) DUR="$OPTARG" ;;
	o) OUT="$OPTARG" ;;
	r) RES="$OPTARG" ;;
	*) exit 2 ;;
	esac
done
shift $((OPTIND - 1))
BOT_ARGS=("$@") # anything after -- reaches OS.get_cmdline_user_args()

[ -n "$OUT" ] || OUT="$HARNESS/botmatch_$(date +%Y%m%d_%H%M%S).mp4"
QUIT_AFTER=$(((DUR + 2) * 60)) # frames @60fps, +2s margin for scene load

WORK="$(mktemp -d)"
AVI="$WORK/botmatch.avi"
LOG="$WORK/render.log"

RES_W="${RES%x*}"
RES_H="${RES#*x}"

cleanup() {
	rm -f "$ROOT"/game/rec_botmatch.gd "$ROOT"/game/rec_botmatch_setup.gd \
		"$ROOT"/game/rec_botmatch.tscn "$ROOT"/game/rec_botmatch*.uid \
		"$ROOT"/game/override.cfg
	rm -rf "$WORK"
}
trap cleanup EXIT

cp "$HARNESS/rec_botmatch.gd" "$HARNESS/rec_botmatch_setup.gd" \
	"$HARNESS/rec_botmatch.tscn" "$ROOT/game/"
cat >"$ROOT/game/override.cfg" <<EOF
[display]
window/size/viewport_width=$RES_W
window/size/viewport_height=$RES_H
EOF

echo "Rendering ${DUR}s at ${RES}@60fps (~$((DUR * 6)) s of llvmpipe time)..."
GODOT_CMD="xvfb-run -a -s '-screen 0 ${RES}x24' godot4 --path game \
res://rec_botmatch.tscn --rendering-driver opengl3 \
--write-movie $AVI --fixed-fps 60 --quit-after $QUIT_AFTER"
if [ ${#BOT_ARGS[@]} -gt 0 ]; then
	GODOT_CMD="$GODOT_CMD -- ${BOT_ARGS[*]}"
fi
(cd "$ROOT" && nix-shell -p xvfb-run --run "nix-shell --run \"$GODOT_CMD\"") \
	>"$LOG" 2>&1 || {
	echo "Render failed — log tail:" >&2
	tail -20 "$LOG" >&2
	exit 1
}
grep -E "BOTMATCH: recording|frames at" "$LOG" || true

echo "Encoding MP4..."
# Movie Maker writes uncompressed PCM audio into the AVI (game sounds, BGM);
# encode it as AAC rather than stripping it.
nix-shell -p ffmpeg --run \
	"ffmpeg -y -loglevel error -i '$AVI' -c:v libx264 -crf 20 -preset medium \
-pix_fmt yuv420p -c:a aac -b:a 192k '$OUT'"
echo "Done: $OUT"
