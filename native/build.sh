#!/usr/bin/env bash
# Builds the native kernels (Rust, godot-rust) and registers them with Godot.
# Optional: without them the game runs the same passes in GDScript, slower.
# Needs cargo (https://rustup.rs). Usage: native/build.sh [debug]
set -eu
cd "$(dirname "$0")/world_kernels"
PROFILE=release
[ "${1:-}" = "debug" ] && PROFILE=debug
cargo build $([ "$PROFILE" = release ] && echo --release)
case "$(uname -s)" in
  Linux)  LIB="libworld_kernels.so";    KEY="linux" ;;
  Darwin) LIB="libworld_kernels.dylib"; KEY="macos" ;;
  *)      LIB="world_kernels.dll";      KEY="windows" ;;
esac
ARCH="$(uname -m)"; [ "$ARCH" = "arm64" ] && ARCH="arm64" || ARCH="x86_64"
# Written only after a successful build: a .gdextension naming a missing
# library is an error at every start, so a checkout without Rust has none.
cat > ../world_kernels.gdextension <<GDX
[configuration]
entry_symbol = "gdext_rust_init"
compatibility_minimum = 4.4
reloadable = true

[libraries]
$KEY.debug.$ARCH = "res://native/world_kernels/target/$PROFILE/$LIB"
$KEY.release.$ARCH = "res://native/world_kernels/target/$PROFILE/$LIB"
GDX
echo "built native/world_kernels/target/$PROFILE/$LIB"
