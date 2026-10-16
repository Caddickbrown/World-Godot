//! Hot whole-grid loops for World-Godot, over packed arrays (one value per
//! tile, row-major). GDScript keeps a fallback for each, so the game runs
//! without this library.
use godot::prelude::*;

struct WorldKernels;

#[gdextension]
unsafe impl ExtensionLibrary for WorldKernels {}

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct Kernels {
    base: Base<RefCounted>,
}

// World.TileType values the regrowth reads.
const GRASS: u8 = 3;
const WOODLAND: u8 = 4;
const FOREST: u8 = 5;

#[godot_api]
impl Kernels {
    /// One value, for measuring what a call across the boundary costs.
    #[func]
    fn read_at(values: PackedFloat32Array, i: i64) -> f32 {
        values.as_slice()[i as usize]
    }

    /// World.update_resources over one stripe of rows (d already carries the
    /// season). Returns the three arrays, changed.
    #[func]
    fn regrow(
        resource: PackedFloat32Array,
        herbs: PackedFloat32Array,
        mushrooms: PackedFloat32Array,
        types: PackedByteArray,
        width: i64,
        start_row: i64,
        stride: i64,
        d: f32,
    ) -> VarArray {
        let (mut res, mut hb, mut mu) = (resource, herbs, mushrooms);
        {
            let r = res.as_mut_slice();
            let h = hb.as_mut_slice();
            let m = mu.as_mut_slice();
            let t = types.as_slice();
            let w = width as usize;
            let rows = t.len() / w;
            let mut z = start_row as usize;
            while z < rows {
                for i in z * w..(z + 1) * w {
                    let g = match t[i] {
                        GRASS => 0.0020,
                        WOODLAND => 0.0016,
                        FOREST => 0.0012,
                        _ => 0.0,
                    };
                    if g > 0.0 {
                        r[i] = (r[i] + g * d).min(1.0);
                    }
                    if h[i] >= 0.0 {
                        h[i] = (h[i] + 0.0006 * d).min(1.0);
                    }
                    if m[i] >= 0.0 {
                        m[i] = (m[i] + 0.0008 * d).min(1.0);
                    }
                }
                z += stride as usize;
            }
        }
        varray![&res, &hb, &mu]
    }
}
