#!/usr/bin/env bash
# Headless validation: import, boot the game, run the test suite, then the long
# simulation soak (tools/smoke.gd).
# Usage: GODOT=/path/to/godot-4.7.2 tests/run_ci.sh        (SKIP_SOAK=1 for the quick part only)
# Fails on any script/parse error, failed check, or unexpected engine ERROR.
set -u
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT
STATUS=0

run() {  # run <label> <timeout-seconds> <godot args...>
  local label=$1 limit=$2; shift 2
  echo "== $label"
  timeout "$limit" "$GODOT" --headless --path . "$@" >> "$OUT" 2>&1
  local rc=$?
  if [ "$rc" -ne 0 ]; then echo "!! $label exited $rc"; STATUS=1; fi
}

# The native kernels are optional (the game falls back to GDScript); build
# them when Rust is here so the parity test checks both. NO_NATIVE=1 skips.
if [ -z "${NO_NATIVE:-}" ] && command -v cargo >/dev/null; then
  echo "== Building native kernels"
  native/build.sh >> "$OUT" 2>&1 || { echo "!! native build failed"; STATUS=1; }
elif [ -n "${NO_NATIVE:-}" ]; then
  rm -f native/world_kernels.gdextension
  sed -i "/world_kernels/d" .godot/extension_list.cfg 2>/dev/null || true
fi

# --editor --quit also writes .godot/global_script_class_cache.cfg, without
# which no class_name resolves on a fresh clone.
run "Importing project" 600 --editor --quit
run "Booting Main.tscn for 600 frames" 300 --quit-after 600
# Tools are loaded by nothing the game runs, so a parse error there only shows
# when someone renders shots (and a scene whose script failed never quits, so
# a parse error in the test runner itself would otherwise just time out).
for f in tools/*.gd tools/capture/*.gd tests/*.gd; do
  run "Parsing $f" 60 --check-only --script "$f"
done
run "Running tests" "${TEST_TIMEOUT:-600}" res://tests/Runner.tscn
if [ -z "${SKIP_SOAK:-}" ]; then
  run "Simulation soak (tools/smoke.gd)" "${SOAK_TIMEOUT:-900}" --script res://tools/smoke.gd
fi

cat "$OUT"

# Known engine noise, not project errors:
# - the headless dummy renderer prints these for meshes/Label3D (never with a real renderer);
# - a fresh import of the third-party FBX models logs the source textures their
#   authors embedded paths to (.psd and _COL_2k.png files that were never shipped).
#   The meshes import fine; nothing in the game loads those textures.
NOISE='Parameter "m" is null|mesh_get_surface_count|Parameter "material" is null|material_get_instance_shader_parameters'
NOISE="$NOISE|Resource file not found: res:// \(expected type: Texture2D\)"
NOISE="$NOISE|Can't open file from path 'res://.*\.(psd|png|jpg|tga)'"
FILTERED="$(grep -v -E "$NOISE" "$OUT")"
ERRORS="$(grep -E '^(SCRIPT ERROR|ERROR:|FAIL:)|Parse Error' <<< "$FILTERED" || true)"
if [ -n "$ERRORS" ]; then
  echo "!! errors found in output:"
  echo "$ERRORS"
  STATUS=1
fi
[ "$STATUS" -eq 0 ] && echo "== CI OK" || echo "== CI FAILED"
exit $STATUS
