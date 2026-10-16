# Native kernels

`world_kernels` is a small Rust library (godot-rust, GDExtension) for the
whole-grid passes. It is optional: every kernel has a GDScript twin, and
`World.kernels` is null when the library isn't built, so the game, the tests
and any export run without it.

Build: `native/build.sh` (needs [rustup](https://rustup.rs)). `tests/run_ci.sh`
builds it when cargo is present; `NO_NATIVE=1` tests the GDScript path.

## What goes here, and what doesn't

Measured with `tools/bench_kernels.gd` (128x128 tiles, one full regrowth pass):

| | one pass | one tile read |
|---|---|---|
| Dictionary tiles, GDScript | 15-23 ms | 375 ns |
| Packed layers, GDScript | 3.3-3.8 ms | 156 ns |
| Packed layers, Rust (one call, copies included) | 0.04-0.06 ms | 532 ns per call |

- **A pass over every tile is the job:** one call, thousands of cells, 300x+.
- **A single read is not:** crossing into Rust costs more than a Dictionary
  lookup. Per-person, per-tile logic stays in GDScript and reads the layers
  directly (2.4x faster than Dictionaries).
- **The data must be in layers first.** Rust can't speed up a loop over
  Dictionaries; moving a field into `World.layer_*` is step one, and it alone
  is worth 4-6x.

## What's native now

| Kernel | Class | GDScript twin | Before | After |
|---|---|---|---|---|
| Food, herb, mushroom regrowth | `Kernels.regrow` | `World.regrow_gd` | 2.3 ms/frame | 0.09 ms/frame |
| Forest spread (seed, fade, succeed) | `Kernels.forest_spread` | `EcologySystem.forest_spread_gd` | 27 ms every 10 game s | 0.1 ms |
| Depletion recovering | `Kernels.fade` | `World.fade_layer` | 5.7 ms a cycle + 10 ms slow tick | ~0 |
| Terrain chunk (height, normal, colour) | `TerrainMesher` | `TerrainRenderer._chunk_arrays_gd` | 16 ms a chunk | 0.9 ms |
| Flora chunk (MultiMesh buffers) | `FloraBuilder` | `EnvironmentRenderer._draw_tile` | 3.1 ms a chunk | 0.5 ms |

Whole frame (150 people, 20x, `tools/profile.gd`): 36.6 ms -> 26.0 ms. Boot:
4.8 s -> 2.8 s. Along the way three whole-map sweeps were deleted rather
than ported: a soil value and tree ages nothing read, and a scan for the few
overgrazed deserts (now a set). Growth visits only growing woods
(`World.growing`).

Random rolls in native passes come from `World.roll` (a hash of seed, tile and
k, the same in both languages), so a pass gives the same world either way and
the parity tests compare exactly. Trees use it too: their places moved once
when this came in.

**Not native, on purpose:** people, animals and conflict (per-person decisions
read a tile or two at a time; a call into Rust costs more than the read), and
the renderers' engine work.

## Adding a kernel

1. Move the fields the pass touches into layers (`World._build_layers`, accessors,
   no reads off the tile: `tests/suites/60_layers.gd` scans for them).
2. Write the GDScript version over the layers (the fallback, and the reference).
3. Write the Rust one in `src/lib.rs`, dispatch on `World.kernels`.
4. Add a parity check to `60_layers.gd`.

## Shipping

The `.gdextension` is written by `build.sh` for the platform it ran on. A
release needs the library built for each target (Windows, macOS, Linux);
a web export would need a wasm build of it and is simplest left on the
GDScript path.
