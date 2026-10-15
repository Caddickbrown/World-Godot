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

# --editor --quit also writes .godot/global_script_class_cache.cfg, without
# which no class_name resolves on a fresh clone.
run "Importing project" 600 --editor --quit
run "Booting Main.tscn for 600 frames" 300 --quit-after 600
# Tools are loaded by nothing the game runs, so a parse error there only shows
# when someone renders shots (and a scene whose script failed never quits).
for f in tools/*.gd tools/capture/*.gd; do
  run "Parsing $f" 60 --check-only --script "$f"
done
run "Running tests" "${TEST_TIMEOUT:-600}" res://tests/Runner.tscn
if [ -z "${SKIP_SOAK:-}" ]; then
  run "Simulation soak (tools/smoke.gd)" "${SOAK_TIMEOUT:-900}" --script res://tools/smoke.gd
fi

cat "$OUT"

# The headless dummy renderer prints these for meshes/Label3D; never seen with a real renderer.
FILTERED="$(grep -v -E 'Parameter "m" is null|mesh_get_surface_count|Parameter "material" is null|material_get_instance_shader_parameters' "$OUT")"
if echo "$FILTERED" | grep -E -q '^(SCRIPT ERROR|ERROR:|FAIL:)|Parse Error'; then
  echo "!! errors found in output:"
  echo "$FILTERED" | grep -E '^(SCRIPT ERROR|ERROR:|FAIL:)|Parse Error'
  STATUS=1
fi
[ "$STATUS" -eq 0 ] && echo "== CI OK" || echo "== CI FAILED"
exit $STATUS
