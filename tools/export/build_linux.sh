#!/usr/bin/env bash
# Builds the Linux release: the native kernels, an import, the export
# (export_presets.cfg "Linux": one binary with the game packed in, and the
# kernels library beside it), then a tarball (keeps the executable bit).
# Usage: GODOT=/path/to/godot-4.7.2 tools/export/build_linux.sh [version]
# Needs the Linux export templates: tools/export/fetch_templates.py.
set -euo pipefail
GODOT="${GODOT:-godot}"
VERSION="${1:-dev}"
cd "$(dirname "$0")/../.."
OUT=build/linux
NAME="World-$VERSION-linux-x86_64"

if command -v cargo >/dev/null; then
  native/build.sh
else
  echo "no cargo: exporting without the native kernels (GDScript passes)"
fi
"$GODOT" --headless --editor --quit --path . >/dev/null 2>&1 || true   # import (writes .godot/)
rm -rf "$OUT" && mkdir -p "$OUT"
"$GODOT" --headless --path . --export-release "Linux" "$OUT/World.x86_64"
test -x "$OUT/World.x86_64"

# A smoke run of the exported build: it must boot, load its data and quit clean.
LOG="$(mktemp)"
timeout 120 "$OUT/World.x86_64" --headless --quit-after 600 >"$LOG" 2>&1 || { cat "$LOG"; exit 1; }
if grep -E "^(SCRIPT )?ERROR" "$LOG"; then echo "exported build printed errors"; exit 1; fi
if [ -f "$OUT/libworld_kernels.so" ] && ! grep -q "Initialize godot-rust" "$LOG"; then
  echo "native kernels shipped but did not load"; cat "$LOG"; exit 1
fi

mkdir -p dist
cp tools/export/README-linux.txt "$OUT/README.txt"
tar -C build -czf "dist/$NAME.tar.gz" --transform "s|^linux|$NAME|" linux
echo "dist/$NAME.tar.gz ($(du -h "dist/$NAME.tar.gz" | cut -f1))"
