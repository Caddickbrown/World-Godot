#!/usr/bin/env bash
# Renders the standard review shots (docs/ART_DIRECTION.md "Review shots").
# Usage: GODOT=/path/to/godot-4.7.2 tools/capture/shots.sh [out_dir] [only_this_shot]
# Needs a GPU or a software Vulkan driver (Mesa lavapipe: apt install mesa-vulkan-drivers).
# Without a display it wraps itself in xvfb-run.
set -eu
GODOT="${GODOT:-godot}"
OUT="$(realpath -m "${1:-shots}")"
ONLY="${2:-}"
mkdir -p "$OUT"
cd "$(dirname "$0")/../.."
RUN=()
if [ -z "${DISPLAY:-}" ]; then RUN=(xvfb-run -a -s "-screen 0 1280x720x24"); fi

shot() {
  local name=$1; shift
  [ -n "$ONLY" ] && [ "$ONLY" != "$name" ] && return 0
  "${RUN[@]}" "$GODOT" --audio-driver Dummy --path . --resolution 1280x720 \
    res://tools/capture/Capture.tscn -- --out="$OUT/$name.png" "$@" 2>&1 | grep '^\[Capture\]' || true
}

shot 1_new_world      --seed=7 --hour=9
shot 2_world_far      --seed=7 --hour=11 --distance=300 --tilt=70 --no-hud
shot 3_follow         --seed=7 --sim=120 --hour=10 --follow --distance=22 --tilt=40
shot 4_walk           --seed=7 --sim=120 --hour=10 --walk
shot 5_listen         --seed=7 --sim=120 --hour=16 --walk --listen --cam-distance=4.5
shot 6_walk_dusk      --seed=7 --sim=120 --hour=19.6 --walk --no-hud
shot 8_storm          --seed=7 --sim=120 --hour=15 --distance=60 --tilt=45 --weather=storm --no-hud
shot 7_settled        --seed=7 --sim=1500 --hour=12 --follow --distance=40 --tilt=50
# The HUD and screens, in both looks (a world ~7 days on).
for st in storybook fieldnotes; do
  shot "8_hud_$st"    --seed=7 --sim=900 --hour=10 --follow --distance=30 --tilt=45 --style=$st
  shot "9_lives_$st"  --seed=7 --sim=900 --hour=10 --follow --style=$st --screen=lives
  shot "10_ideas_$st" --seed=7 --sim=900 --hour=10 --style=$st --screen=ideas
  shot "11_album_$st" --seed=7 --sim=900 --hour=10 --style=$st --screen=album
done
