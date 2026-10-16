#!/usr/bin/env bash
# Runs an exported build headless for 600 frames: it must quit cleanly, log
# no errors, and (when it ships the native kernels) report them on.
# Usage: tools/export/smoke.sh path/to/World(.x86_64|.exe|.app/Contents/MacOS/World) [expect-native]
set -uo pipefail
BIN="$1"
EXPECT_NATIVE="${2:-yes}"
LOG="$(mktemp)"
if command -v timeout >/dev/null; then
  timeout 180 "$BIN" --headless --quit-after 600 --log-file "$LOG" >/dev/null 2>&1
else   # macOS has no timeout(1)
  perl -e 'alarm shift; exec @ARGV' 180 "$BIN" --headless --quit-after 600 --log-file "$LOG" >/dev/null 2>&1
fi
RC=$?
echo "--- log ($BIN, exit $RC)"; cat "$LOG"; echo "---"
[ "$RC" -eq 0 ] || { echo "exported build exited $RC"; exit 1; }
if grep -E "^(SCRIPT )?ERROR" "$LOG"; then echo "exported build logged errors"; exit 1; fi
grep -q "native kernels: " "$LOG" || { echo "the game never started its world"; exit 1; }
if [ "$EXPECT_NATIVE" = yes ] && ! grep -q "native kernels: on" "$LOG"; then
  echo "native kernels shipped but did not load"; exit 1
fi
echo "smoke ok"
