#!/usr/bin/env bash
# Renders the "starting again" art mockup shots. Same usage as shots.sh.
set -eu
GODOT="${GODOT:-godot}"
OUT="$(realpath -m "${1:-shots/mockup}")"
ONLY="${2:-}"
mkdir -p "$OUT"
cd "$(dirname "$0")/../.."
RUN=()
if [ -z "${DISPLAY:-}" ]; then RUN=(xvfb-run -a -s "-screen 0 1280x720x24"); fi
shot() {
  local name=$1; shift
  [ -n "$ONLY" ] && [ "$ONLY" != "$name" ] && return 0
  "${RUN[@]}" "$GODOT" --audio-driver Dummy --path . --resolution 1280x720 \
    res://tools/capture/Mockup.tscn -- --out="$OUT/$name.png" "$@" 2>&1 | grep '^\[Capture\]' || true
}
shot m1_world        --seed=7 --hour=10   --cam=-60,120,150 --look=0,0,-10 --fov=50
shot m2_camp         --seed=7 --hour=10.5 --cam=14,11,16 --look=0,0.5,0 --tilt=1
shot m3_camp_dusk    --seed=7 --hour=18.9 --cam=-12,7,13 --look=0,1,0 --tilt=1
shot m4_ground       --seed=7 --hour=16   --cam=8,1.8,9 --look=-2,1.2,-2
shot m5_valley       --seed=7 --hour=8    --cam=40,30,-45 --look=0,2,0 --fov=45 --tilt=0.6
# Option B: the same shots with the cartoon turned down.
shot n1_world        --style=naturalist --seed=7 --hour=10   --cam=-60,120,150 --look=0,0,-10 --fov=50
shot n2_camp         --style=naturalist --seed=7 --hour=10.5 --cam=14,11,16 --look=0,0.5,0 --tilt=0.6
shot n3_camp_dusk    --style=naturalist --seed=7 --hour=18.9 --cam=-12,7,13 --look=0,1,0 --tilt=0.6
shot n4_ground       --style=naturalist --seed=7 --hour=16   --cam=8,1.8,9 --look=-2,1.2,-2
shot n5_valley       --style=naturalist --seed=7 --hour=8    --cam=40,30,-45 --look=0,2,0 --fov=45 --tilt=0.4
