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
