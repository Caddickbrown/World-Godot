#!/usr/bin/env bash
# Exports the game for each platform named (default: all three) into dist/:
#   World-<version>-linux-x86_64.tar.gz, -windows-x86_64.zip, -macos-universal.zip
# The native kernels each platform ships are whatever native/package.sh left
# in native/bin/<platform>/ (CI builds each on its own OS); a platform with
# none runs the GDScript passes. Exporting needs the export templates
# (tools/export/fetch_templates.py); a Linux build is smoke-run here.
# Usage: GODOT=/path/to/godot-4.7.2 VERSION=v0.1.0 tools/export/export.sh [linux] [windows] [macos]
set -euo pipefail
GODOT="${GODOT:-godot}"
VERSION="${VERSION:-dev}"
cd "$(dirname "$0")/../.."
PLATFORMS=("$@")
[ ${#PLATFORMS[@]} -eq 0 ] && PLATFORMS=(linux windows macos)

# Register every packaged library (and only those: a .gdextension naming a
# missing library is an error at every start).
GDX=native/world_kernels.gdextension
LIBS=""
add() { [ -f "$2" ] && LIBS+="$1.debug$3 = \"res://$2\"
$1.release$3 = \"res://$2\"
"; return 0; }
add linux native/bin/linux/libworld_kernels.so ".x86_64"
add windows native/bin/windows/world_kernels.dll ".x86_64"
add macos native/bin/macos/libworld_kernels.dylib ""
if [ -n "$LIBS" ]; then
  printf '[configuration]\nentry_symbol = "gdext_rust_init"\ncompatibility_minimum = 4.4\nreloadable = false\n\n[libraries]\n%s' "$LIBS" > "$GDX"
else
  rm -f "$GDX"
fi
echo "native kernels packaged:"; printf '%s' "$LIBS" | grep release || echo "  none"

"$GODOT" --headless --editor --quit --path . >/dev/null 2>&1 || true   # import (writes .godot/)
mkdir -p dist
for p in "${PLATFORMS[@]}"; do
  rm -rf "build/$p" && mkdir -p "build/$p"
  case "$p" in
    linux)
      "$GODOT" --headless --path . --export-release "Linux" build/linux/World.x86_64
      cp tools/export/README-linux.txt build/linux/README.txt
      NAME="World-$VERSION-linux-x86_64"
      tar -C build -czf "dist/$NAME.tar.gz" --transform "s|^linux|$NAME|" linux   # keeps +x
      if [ "$(uname -s)" = Linux ]; then
        tools/export/smoke.sh build/linux/World.x86_64 "$([ -f native/bin/linux/libworld_kernels.so ] && echo yes || echo no)"
      fi
      ;;
    windows)
      "$GODOT" --headless --path . --export-release "Windows" build/windows/World.exe
      cp tools/export/README-windows.txt build/windows/README.txt
      NAME="World-$VERSION-windows-x86_64"
      rm -f "dist/$NAME.zip"
      (cd build && mv windows "$NAME" && zip -qr "../dist/$NAME.zip" "$NAME" && mv "$NAME" windows)
      ;;
    macos)
      # Godot writes the zip itself (the .app, ad-hoc signed, kernels in Frameworks).
      "$GODOT" --headless --path . --export-release "macOS" build/macos/World.zip
      NAME="World-$VERSION-macos-universal"
      cp build/macos/World.zip "dist/$NAME.zip"
      cp tools/export/README-macos.txt build/macos/README.txt
      (cd build/macos && zip -q "../../dist/$NAME.zip" README.txt)
      ;;
    *) echo "unknown platform $p"; exit 1 ;;
  esac
  test -n "$(ls dist/World-"$VERSION"-"$p"-* 2>/dev/null)"
done
ls -la dist/
