#!/usr/bin/env bash
# Deterministic pre-pass for the sidecar-check skill.
# Reports pairing status of every Godot file in game/; semantic verification
# of sidecar *content* is the skill's job, not this script's.
set -euo pipefail
cd "$(dirname "$0")/../../.."

status=0

# Godot files: scripts, scenes, resources, shaders, project config.
mapfile -t godot_files < <(
  {
    find game -name '*.gd' -o -name '*.tscn' -o -name '*.tres' -o -name '*.gdshader'
    echo game/project.godot
  } | sort
)

echo "== Missing sidecars =="
for f in "${godot_files[@]}"; do
  if [[ ! -f "$f.md" ]]; then
    echo "MISSING  $f.md"
    status=1
  fi
done

echo
echo "== Sidecars older than their Godot file (possible drift) =="
for f in "${godot_files[@]}"; do
  if [[ -f "$f.md" && "$f" -nt "$f.md" ]]; then
    echo "STALE?   $f.md  (godot file modified more recently)"
    status=1
  fi
done

echo
echo "== Orphaned sidecars (paired file gone) =="
while IFS= read -r md; do
  base="${md%.md}"
  if [[ ! -f "$base" ]]; then
    echo "ORPHAN   $md"
    status=1
  fi
done < <(find game -name '*.gd.md' -o -name '*.tscn.md' -o -name '*.tres.md' -o -name '*.gdshader.md' -o -name 'project.godot.md' | sort)

echo
echo "== All pairs =="
for f in "${godot_files[@]}"; do
  [[ -f "$f.md" ]] && echo "PAIRED   $f  <->  $f.md"
done

exit $status
