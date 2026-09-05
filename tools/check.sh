#!/bin/sh
# Headless smoke test: boots the project, runs N frames, reports script errors.
# Fails only on errors; warnings are printed but tolerated.
# Usage: tools/check.sh [frames]
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
FRAMES=${1:-300}
cd "$(dirname "$0")/.." || exit 1
RAW=$("$GODOT" --headless --quit-after "$FRAMES" 2>&1 \
  | grep -v 'Case mismatch\|at: open_internal\|^$\|Godot Engine v')
ERRS=$(printf '%s\n' "$RAW" | grep -A1 'SCRIPT ERROR\|^ERROR' )
WARNS=$(printf '%s\n' "$RAW" | grep 'WARNING')
[ -n "$WARNS" ] && printf 'warnings:\n%s\n\n' "$WARNS"
if [ -n "$ERRS" ]; then
  printf 'errors:\n%s\n--- FAIL ---\n' "$ERRS"
  exit 1
fi
echo "--- OK ($FRAMES frames, no errors) ---"
