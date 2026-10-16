#!/usr/bin/env bash
# Builds the native kernels for release on the OS it runs on, into
# native/bin/<platform>/, where the export (tools/export/export.sh) finds them:
#   linux:   libworld_kernels.so    (glibc 2.28+, via cargo-zigbuild if present)
#   windows: world_kernels.dll      (MSVC)
#   macos:   libworld_kernels.dylib (universal: arm64 + x86_64)
set -euo pipefail
cd "$(dirname "$0")/world_kernels"
case "$(uname -s)" in
  Linux)
    mkdir -p ../bin/linux
    if command -v cargo-zigbuild >/dev/null; then
      # Godot's own Linux build needs glibc 2.28; so does this, built that way.
      cargo zigbuild --release --target x86_64-unknown-linux-gnu.2.28
      cp target/x86_64-unknown-linux-gnu/release/libworld_kernels.so ../bin/linux/
    else
      echo "no cargo-zigbuild: building against this machine's glibc"
      cargo build --release
      cp target/release/libworld_kernels.so ../bin/linux/
    fi
    ;;
  Darwin)
    mkdir -p ../bin/macos
    rustup target add aarch64-apple-darwin x86_64-apple-darwin
    cargo build --release --target aarch64-apple-darwin
    cargo build --release --target x86_64-apple-darwin
    lipo -create -output ../bin/macos/libworld_kernels.dylib \
      target/aarch64-apple-darwin/release/libworld_kernels.dylib \
      target/x86_64-apple-darwin/release/libworld_kernels.dylib
    ;;
  MINGW*|MSYS*|CYGWIN*)
    mkdir -p ../bin/windows
    cargo build --release --target x86_64-pc-windows-msvc
    cp target/x86_64-pc-windows-msvc/release/world_kernels.dll ../bin/windows/
    ;;
  *) echo "unknown OS $(uname -s)"; exit 1 ;;
esac
ls -la ../bin/*/
