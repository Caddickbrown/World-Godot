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

// World.TileType values the kernels read.
const GRASS: u8 = 3;
const WOODLAND: u8 = 4;
const FOREST: u8 = 5;

// Forest spread events (EcologySystem applies them): kind, tile, other tile.
const SEED: i32 = 0; // grass at `tile` seeded from the wood at `other`
const REVERT: i32 = 1; // lone woodland at `tile` fades to grass
const SUCCEED: i32 = 2; // woodland at `tile` beside forest turns to forest

/// A roll in [0, 1) from (seed, tile, k): the same numbers as World.roll in
/// GDScript, so the native and GDScript passes give the same world.
#[inline]
fn roll(seed: u32, i: u32, k: u32) -> f64 {
    let mut x = seed.wrapping_mul(73856093) ^ i.wrapping_mul(19349663) ^ k.wrapping_mul(83492791);
    x ^= x >> 16;
    x = x.wrapping_mul(0x7feb352d);
    x ^= x >> 15;
    x = x.wrapping_mul(0x2c1b3c6d);
    x ^= x >> 16;
    x as f64 / 4294967296.0
}

#[godot_api]
impl Kernels {
    /// Woods spreading, fading and maturing, from tile types alone (the
    /// rest of each rule is checked by EcologySystem on the few hits).
    /// Returns [kind, tile, other, ...]; see SEED, REVERT, SUCCEED.
    #[func]
    fn forest_spread(
        types: PackedByteArray,
        width: i64,
        seed: i64,
        p_spread: f64,
        p_revert: f64,
        p_succeed: f64,
    ) -> PackedInt32Array {
        let t = types.as_slice();
        let w = width as usize;
        let h = t.len() / w;
        let s = seed as u32;
        let mut out: Vec<i32> = Vec::new();
        for z in 0..h {
            for x in 0..w {
                let i = z * w + x;
                let ty = t[i];
                if ty != FOREST && ty != WOODLAND {
                    continue;
                }
                let p = if ty == FOREST { p_spread } else { p_spread * 0.5 };
                let mut forest_near = false;
                let mut woods_near = false;
                for (k, (dx, dz)) in [(-1i64, 0i64), (1, 0), (0, -1), (0, 1)].iter().enumerate() {
                    let nx = x as i64 + dx;
                    let nz = z as i64 + dz;
                    if nx < 0 || nz < 0 || nx >= w as i64 || nz >= h as i64 {
                        continue;
                    }
                    let j = nz as usize * w + nx as usize;
                    let nt = t[j];
                    if nt == GRASS && roll(s, i as u32, k as u32) < p {
                        out.extend_from_slice(&[SEED, j as i32, i as i32]);
                    }
                    forest_near |= nt == FOREST;
                    woods_near |= nt == FOREST || nt == WOODLAND;
                }
                if ty == WOODLAND {
                    if !woods_near {
                        if roll(s, i as u32, 4) < p_revert {
                            out.extend_from_slice(&[REVERT, i as i32, i as i32]);
                        }
                    } else if forest_near && roll(s, i as u32, 5) < p_succeed {
                        out.extend_from_slice(&[SUCCEED, i as i32, i as i32]);
                    }
                }
            }
        }
        PackedInt32Array::from(out.as_slice())
    }

    /// Every positive value in the given rows falls by `amount`, not below
    /// zero (depletion recovering). Negative means "not this kind of tile".
    #[func]
    fn fade(values: PackedFloat32Array, width: i64, start_row: i64, stride: i64, amount: f32) -> PackedFloat32Array {
        let mut v = values;
        {
            let a = v.as_mut_slice();
            let w = width as usize;
            let rows = a.len() / w;
            let mut z = start_row as usize;
            while z < rows {
                for e in &mut a[z * w..(z + 1) * w] {
                    if *e > 0.0 {
                        *e = (*e - amount).max(0.0);
                    }
                }
                z += stride as usize;
            }
        }
        v
    }

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

// ── Terrain ──────────────────────────────────────────────────────────────────

/// Builds terrain chunks: TerrainRenderer's GDScript twin (_chunk_arrays_gd)
/// in Rust. The heightfield and palette are set once (set_field,
/// set_palette); each chunk then needs only its window of tile state.
#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct TerrainMesher {
    base: Base<RefCounted>,
    heights: Vec<f32>,
    biome: Vec<f32>,
    n: usize,
    step: f64,
    size_m: f64,
    tile_size: f64,
    palette: Vec<Rgba>,
    naturalist: bool,
    camps: Vec<(f64, f64)>,
}

#[godot_api]
impl TerrainMesher {
    #[func]
    fn set_field(&mut self, heights: PackedFloat32Array, biome: PackedFloat32Array, n: i64, step: f64, size_m: f64, tile_size: f64) {
        self.heights = heights.as_slice().to_vec();
        self.biome = biome.as_slice().to_vec();
        self.n = n as usize;
        self.step = step;
        self.size_m = size_m;
        self.tile_size = tile_size;
    }

    /// Colours in TerrainRenderer.palette() order; camps in world metres.
    #[func]
    fn set_palette(&mut self, palette: PackedColorArray, naturalist: bool, camps: PackedVector2Array) {
        self.palette = palette.as_slice().iter().map(|c| [c.r, c.g, c.b, c.a]).collect();
        self.naturalist = naturalist;
        self.camps = camps.as_slice().iter().map(|v| (v.x as f64, v.y as f64)).collect();
    }

    /// One chunk's vertices from (x0, z0), steps + 1 a side. Tile state comes
    /// in a window of tiles from `win`, `win_w` wide (type 255: off the map).
    /// Returns [PackedVector3Array, PackedVector3Array, PackedColorArray].
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn chunk(
        &self,
        x0: f64,
        z0: f64,
        steps: i64,
        win: Vector2i,
        win_w: i64,
        ttype: PackedByteArray,
        flags: PackedByteArray,
        depletion: PackedFloat32Array,
        drought: PackedFloat32Array,
        blight: PackedFloat32Array,
    ) -> VarArray {
        let field = Field { hs: &self.heights, n: self.n, step: self.step };
        let tw = TileWindow {
            x0: win.x as i64,
            z0: win.y as i64,
            w: win_w,
            ttype: ttype.as_slice(),
            flags: flags.as_slice(),
            depletion: depletion.as_slice(),
            drought: drought.as_slice(),
            blight: blight.as_slice(),
        };
        let pal = &self.palette;
        let (step, n, ts) = (self.step, self.n, self.tile_size);
        let count = steps as usize + 1;
        let mut verts: Vec<Vector3> = Vec::with_capacity(count * count);
        let mut normals: Vec<Vector3> = Vec::with_capacity(count * count);
        let mut colors: Vec<Color> = Vec::with_capacity(count * count);
        for iz in 0..count {
            for ix in 0..count {
                let x = (x0 + ix as f64 * step).min(self.size_m);
                let z = (z0 + iz as f64 * step).min(self.size_m);
                let h = field.height_at(x, z);
                let nrm = field.normal_at(x, z);
                let tile = tw.at((x / ts).floor() as i64, (z / ts).floor() as i64);
                let wob = (x * 0.07 + z * 0.05).sin() * (z * 0.09 - x * 0.03).cos() * 0.5 + 0.5;
                let bx = ((x / step).round() as i64).clamp(0, n as i64 - 1) as usize;
                let bz = ((z / step).round() as i64).clamp(0, n as i64 - 1) as usize;
                let nv = self.biome[bz * n + bx] as f64;
                let mut c = ground(pal, nv, h, nrm[1] as f64, &tw, tile, wob, self.naturalist);
                c = disaster_tint(pal, c, tw.field_at(x, z, ts, 0), tw.field_at(x, z, ts, 1));
                for &(px, pz) in &self.camps {
                    let d = ((x - px).powi(2) + (z - pz).powi(2)).sqrt();
                    if d < 9.0 {
                        c = lerp(c, pal[P_TRAMPLED], ((1.0 - smoothstep(3.5, 9.0, d)) * 0.85) as f32);
                    }
                }
                verts.push(Vector3::new(x as f32, h as f32, z as f32));
                normals.push(Vector3::new(nrm[0], nrm[1], nrm[2]));
                colors.push(Color::from_rgba(c[0], c[1], c[2], c[3]));
            }
        }
        varray![
            &PackedVector3Array::from(verts.as_slice()),
            &PackedVector3Array::from(normals.as_slice()),
            &PackedColorArray::from(colors.as_slice())
        ]
    }
}

// Terrain colour: LookStyle.ground and friends, in palette terms.

// Palette slots: TerrainRenderer.palette() fills them in this order.
const P_MEADOW: usize = 0;
const P_MEADOW_DRY: usize = 1;
const P_WOOD: usize = 2;
const P_FOREST: usize = 3;
const P_ROCK: usize = 4;
const P_DESERT: usize = 5;
const P_GLACIER: usize = 6;
const P_LAVA: usize = 7;
const P_BARREN: usize = 8;
const P_ASH: usize = 9;
const P_RIVER: usize = 10;
const P_FLOOD_MUD: usize = 11;
const P_SAND: usize = 12;
const P_WET_SAND: usize = 13;
const P_ROCK_DARK: usize = 14;
const P_SNOW: usize = 15;
const P_PARCHED: usize = 16; // already graded
const P_BLIGHT: usize = 17; // already graded
const P_TRAMPLED: usize = 18; // already graded

// Tile flags (TerrainRenderer._window).
const F_CUT: u8 = 1;
const F_BURNT: u8 = 2;
const F_RIVER: u8 = 4;
const F_FLOODED: u8 = 8;

const T_DESERT: u8 = 6;
const T_GLACIER: u8 = 9;
const T_LAVA: u8 = 10;
const T_NONE: u8 = 255;

type Rgba = [f32; 4];

fn lerp(a: Rgba, b: Rgba, t: f32) -> Rgba {
    [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t]
}

fn smoothstep(from: f64, to: f64, x: f64) -> f64 {
    let s = ((x - from) / (to - from)).clamp(0.0, 1.0);
    s * s * (3.0 - 2.0 * s)
}

/// LookStyle.g: the naturalist grade.
fn grade(c: Rgba, naturalist: bool) -> Rgba {
    if !naturalist {
        return c;
    }
    let grey = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
    let g = lerp(c, [grey * 1.04, grey, grey * 0.80, 1.0], 0.32);
    [g[0] * 0.86, g[1] * 0.86, g[2] * 0.86, g[3]]
}

#[allow(clippy::too_many_arguments)]
fn ground(p: &[Rgba], nv: f64, h: f64, nrm_y: f64, tw: &TileWindow, tile: Option<usize>, wob: f64, nat: bool) -> Rgba {
    let mut c = p[P_MEADOW];
    c = lerp(c, p[P_MEADOW_DRY], (wob * 0.45) as f32);
    c = lerp(c, p[P_WOOD], smoothstep(0.14, 0.22, nv) as f32);
    c = lerp(c, p[P_FOREST], smoothstep(0.27, 0.35, nv) as f32);
    c = lerp(c, p[P_ROCK], smoothstep(0.50, 0.58, nv) as f32);
    if let Some(i) = tile {
        match tw.ttype[i] {
            T_DESERT => c = lerp(c, p[P_DESERT], 0.85),
            T_GLACIER => c = p[P_GLACIER],
            T_LAVA => c = p[P_LAVA],
            _ => {}
        }
        let d = tw.depletion[i];
        if d > 0.0 {
            c = lerp(c, p[P_BARREN], d.clamp(0.0, 1.0) * 0.7);
        }
        let f = tw.flags[i];
        if f & F_CUT != 0 {
            c = lerp(c, p[P_BARREN], 0.35);
        }
        if f & F_BURNT != 0 {
            c = lerp(c, p[P_ASH], 0.75);
        }
        if f & F_RIVER != 0 {
            c = lerp(c, p[P_RIVER], 0.75);
        }
        if f & F_FLOODED != 0 {
            c = lerp(c, p[P_FLOOD_MUD], 0.6);
        }
    }
    if h > -2.5 {
        c = lerp(c, p[P_SAND], ((1.0 - smoothstep(0.45, 1.1, h)) * if h > 0.0 { 0.85 } else { 0.4 }) as f32);
    }
    if h <= 0.0 {
        c = lerp(c, p[P_WET_SAND], (-h / 2.0).clamp(0.0, 1.0) as f32);
    }
    let slope = 1.0 - nrm_y;
    c = lerp(c, p[P_ROCK_DARK], smoothstep(0.25, 0.55, slope) as f32);
    c = lerp(c, p[P_SNOW], (smoothstep(13.0, 17.0, h) * (1.0 - smoothstep(0.35, 0.6, slope))) as f32);
    grade(c, nat)
}

fn disaster_tint(p: &[Rgba], c: Rgba, drought: f64, blight: f64) -> Rgba {
    if drought <= 0.0 && blight <= 0.0 {
        return c;
    }
    let green = ((c[1] - c[0].max(c[2])) * 6.0).clamp(0.0, 1.0);
    let c = lerp(c, p[P_PARCHED], drought as f32 * 0.8 * green);
    lerp(c, p[P_BLIGHT], blight as f32 * 0.65 * green)
}

/// Heightfield.height_at / normal_at over its samples.
struct Field<'a> {
    hs: &'a [f32],
    n: usize,
    step: f64,
}

impl Field<'_> {
    fn height_at(&self, x: f64, z: f64) -> f64 {
        let top = self.n as f64 - 1.001;
        let fx = (x / self.step).clamp(0.0, top);
        let fz = (z / self.step).clamp(0.0, top);
        let ix = fx as usize;
        let iz = fz as usize;
        let ax = fx - ix as f64;
        let az = fz - iz as f64;
        let i = iz * self.n + ix;
        let h = self.hs;
        let a = h[i] as f64 + (h[i + 1] as f64 - h[i] as f64) * ax;
        let b = h[i + self.n] as f64 + (h[i + self.n + 1] as f64 - h[i + self.n] as f64) * ax;
        a + (b - a) * az
    }

    fn normal_at(&self, x: f64, z: f64) -> [f32; 3] {
        let e = self.step;
        let v = [
            (self.height_at(x - e, z) - self.height_at(x + e, z)) as f32,
            (2.0 * e) as f32,
            (self.height_at(x, z - e) - self.height_at(x, z + e)) as f32,
        ];
        let l = (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).sqrt();
        [v[0] / l, v[1] / l, v[2] / l]
    }
}

/// The tiles round one chunk.
struct TileWindow<'a> {
    x0: i64,
    z0: i64,
    w: i64,
    ttype: &'a [u8],
    flags: &'a [u8],
    depletion: &'a [f32],
    drought: &'a [f32],
    blight: &'a [f32],
}

impl TileWindow<'_> {
    /// Window index of a tile, None off the map (or outside the window).
    fn at(&self, tx: i64, tz: i64) -> Option<usize> {
        let (wx, wz) = (tx - self.x0, tz - self.z0);
        if wx < 0 || wz < 0 || wx >= self.w || wz * self.w + wx >= self.ttype.len() as i64 {
            return None;
        }
        let i = (wz * self.w + wx) as usize;
        if self.ttype[i] == T_NONE {
            None
        } else {
            Some(i)
        }
    }

    fn val(&self, tx: i64, tz: i64, which: u8) -> f64 {
        match self.at(tx, tz) {
            None => 0.0,
            Some(i) => (if which == 0 { self.drought[i] } else { self.blight[i] }) as f64,
        }
    }

    /// TerrainRenderer._field_at: a tile amount read smoothly between centres.
    fn field_at(&self, x: f64, z: f64, tile_size: f64, which: u8) -> f64 {
        let tx = x / tile_size - 0.5;
        let tz = z / tile_size - 0.5;
        let x0 = tx.floor();
        let z0 = tz.floor();
        let fx = tx - x0;
        let fz = tz - z0;
        let (x0, z0) = (x0 as i64, z0 as i64);
        let a = self.val(x0, z0, which);
        let b = self.val(x0 + 1, z0, which);
        let c = self.val(x0, z0 + 1, which);
        let d = self.val(x0 + 1, z0 + 1, which);
        if a == 0.0 && b == 0.0 && c == 0.0 && d == 0.0 {
            return 0.0;
        }
        let top = a + (b - a) * fx;
        let bot = c + (d - c) * fx;
        top + (bot - top) * fz
    }
}

// ── Flora ────────────────────────────────────────────────────────────────────

/// Builds a flora chunk's MultiMesh buffers: EnvironmentRenderer's GDScript
/// _draw_tile in Rust. Trees stand where World.roll puts them (the same
/// numbers as EnvironmentRenderer._slots), so both draw one wood.
#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct FloraBuilder {
    base: Base<RefCounted>,
    heights: Vec<f32>,
    n: usize,
    step: f64,
    tile_size: f64,
    seed: u32,
    width: u32,
    palette: Vec<Rgba>,
    naturalist: bool,
}

// FloraBuilder palette slots (EnvironmentRenderer.palette()).
const FP_TRUNK: usize = 0;
const FP_CHAR: usize = 1;
const FP_BLIGHT: usize = 2;
const FP_PINE_A: usize = 3;
const FP_PINE_B: usize = 4;
const FP_BROAD_A: usize = 5;
const FP_BROAD_B: usize = 6;
const FP_EARLY_AUTUMN: usize = 7;

// Parts, in EnvironmentRenderer.TREE_PARTS order.
const PINE_LO: usize = 0;
const PINE_HI: usize = 1;
const TRUNK: usize = 2;
const CROWN: usize = 3;
const CROWN_SMALL: usize = 4;
const STUMP: usize = 5;
const SNAG: usize = 6;

// Flora tile flags (EnvironmentRenderer._rebuild_chunk).
const FF_PLANTED: u8 = 1;
const FF_BURNT: u8 = 2;
const FF_CUT: u8 = 4;
const FF_WOODS: u8 = 8;

#[derive(PartialEq)]
enum Kind {
    None,
    Pine,
    Broad,
    Meadow,
    Snag,
}

fn lightened(c: Rgba, a: f32) -> Rgba {
    [c[0] + (1.0 - c[0]) * a, c[1] + (1.0 - c[1]) * a, c[2] + (1.0 - c[2]) * a, c[3]]
}

fn darkened(c: Rgba, a: f32) -> Rgba {
    [c[0] * (1.0 - a), c[1] * (1.0 - a), c[2] * (1.0 - a), c[3]]
}

/// One instance into a MultiMesh buffer (TRANSFORM_3D with colours): a yaw
/// about Y, scaled per axis (Basis.scaled), at `at`; 16 floats.
fn push(buf: &mut Vec<f32>, yaw: f64, s: [f64; 3], at: [f64; 3], c: Rgba) {
    let (sn, cs) = (yaw.sin(), yaw.cos());
    let rows = [[cs * s[0], 0.0, sn * s[0]], [0.0, s[1], 0.0], [-sn * s[2], 0.0, cs * s[2]]];
    for r in 0..3 {
        buf.extend_from_slice(&[rows[r][0] as f32, rows[r][1] as f32, rows[r][2] as f32, at[r] as f32]);
    }
    buf.extend_from_slice(&c);
}

#[godot_api]
impl FloraBuilder {
    #[func]
    fn set_field(&mut self, heights: PackedFloat32Array, n: i64, step: f64, tile_size: f64, seed: i64, width: i64) {
        self.heights = heights.as_slice().to_vec();
        self.n = n as usize;
        self.step = step;
        self.tile_size = tile_size;
        self.seed = seed as u32;
        self.width = width as u32;
    }

    #[func]
    fn set_palette(&mut self, palette: PackedColorArray, naturalist: bool) {
        self.palette = palette.as_slice().iter().map(|c| [c.r, c.g, c.b, c.a]).collect();
        self.naturalist = naturalist;
    }

    /// The tiles from (tx0, tz0), w x h of them: one buffer per part (16
    /// floats an instance), then [trees, stumps, snags] per tile.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn chunk(
        &self,
        tx0: i64,
        tz0: i64,
        w: i64,
        h: i64,
        ttype: PackedByteArray,
        flags: PackedByteArray,
        growth: PackedFloat32Array,
        blight: PackedFloat32Array,
        clearings: PackedVector3Array,
        visual_steps: i64,
    ) -> VarArray {
        let field = Field { hs: &self.heights, n: self.n, step: self.step };
        let (tt, fl, gr, bl) = (ttype.as_slice(), flags.as_slice(), growth.as_slice(), blight.as_slice());
        let clear: Vec<(f32, f32, f32)> = clearings.as_slice().iter().map(|v| (v.x, v.y, v.z)).collect();
        let p = &self.palette;
        let nat = self.naturalist;
        let ts = self.tile_size;
        let vs = visual_steps as f64;
        let mut bufs: Vec<Vec<f32>> = vec![Vec::new(); 7];
        let mut counts: Vec<i32> = vec![0; (w * h * 3) as usize];
        for wz in 0..h {
            for wx in 0..w {
                let wi = (wz * w + wx) as usize;
                let (x, z) = (tx0 + wx, tz0 + wz);
                let ti = (z as u32).wrapping_mul(self.width).wrapping_add(x as u32);
                let t = tt[wi];
                let f = fl[wi];
                let (planted, burnt, cut) = (f & FF_PLANTED != 0, f & FF_BURNT != 0, f & FF_CUT != 0);
                let g = if f & FF_WOODS != 0 && gr[wi] >= 0.0 {
                    ((gr[wi] as f64).clamp(0.0, 1.0) * vs).floor() / vs
                } else {
                    1.0
                };
                let rl = |k: u32| roll(self.seed, ti, k);
                let slots = if (t == FOREST || planted || burnt) && rl(0) < 0.5 { 2 } else { 1 };
                for k in 0..slots {
                    let r = 1 + k * 7;
                    let px = (x as f64 + 0.1 + 0.8 * rl(r)) * ts;
                    let pz = (z as f64 + 0.1 + 0.8 * rl(r + 1)) * ts;
                    let rolled = rl(r + 2);
                    let yaw = rl(r + 3) * std::f64::consts::TAU;
                    let size = rl(r + 4);
                    let tint_r = rl(r + 5);
                    let odd = rl(r + 6);
                    let hh = field.height_at(px, pz);
                    let ny = field.normal_at(px, pz)[1] as f64;
                    let clump = (px * 0.11 + pz * 0.07).sin() * (pz * 0.13 - px * 0.05).cos() * 0.5 + 0.5;
                    let mut kind = Kind::None;
                    if hh >= 0.6 && ny >= 0.7 {
                        if t == FOREST && rolled < 0.42 + clump * 0.35 {
                            kind = Kind::Pine;
                        } else if t == WOODLAND && (rolled < 0.16 + clump * 0.24 || (planted && rolled < 0.7)) {
                            kind = Kind::Broad;
                        } else if t == GRASS && rolled < 0.09 * clump {
                            kind = Kind::Meadow;
                        } else if burnt && rolled < 0.55 {
                            kind = Kind::Snag;
                        }
                    }
                    if kind == Kind::None {
                        continue;
                    }
                    let (mut s, mut tint) = if kind == Kind::Pine {
                        let s = (0.8 + (1.35 - 0.8) * size) * if nat { 1.25 } else { 1.0 };
                        (s, lerp(p[FP_PINE_A], p[FP_PINE_B], tint_r as f32))
                    } else {
                        let s = 0.7 + (1.1 - 0.7) * size;
                        let tint = if odd < 0.025 && !nat {
                            p[FP_EARLY_AUTUMN]
                        } else {
                            lerp(p[FP_BROAD_A], p[FP_BROAD_B], (tint_r * 0.6) as f32)
                        };
                        (s, tint)
                    };
                    if clear.iter().any(|&(cx, cz, cr)| {
                        let (dx, dz) = (px as f32 - cx, pz as f32 - cz);
                        (dx * dx + dz * dz).sqrt() < cr
                    }) {
                        continue;
                    }
                    let base = [px, hh, pz];
                    let up = |dy: f64| [base[0], base[1] + dy, base[2]];
                    if kind == Kind::Snag {
                        let ss = s * 0.9;
                        push(&mut bufs[SNAG], yaw, [ss * 0.8, ss * 2.4, ss * 0.8], up(1.1 * ss), grade(p[FP_CHAR], nat));
                        counts[wi * 3 + 2] += 1;
                        continue;
                    }
                    if cut && kind != Kind::Meadow {
                        push(&mut bufs[STUMP], yaw, [s, s, s], up(0.15 * s), grade(lightened(p[FP_TRUNK], 0.15), nat));
                        counts[wi * 3 + 1] += 1;
                        continue;
                    }
                    if burnt {
                        continue;
                    }
                    let fs = 0.16 + (1.0 - 0.16) * if kind != Kind::Meadow { g } else { 1.0 };
                    s *= fs;
                    if fs < 0.5 {
                        tint = lightened(tint, 0.12);
                    }
                    let b = bl[wi];
                    if b > 0.0 {
                        tint = lerp(tint, p[FP_BLIGHT], b * 0.8);
                    }
                    let trunk = grade(p[FP_TRUNK], nat);
                    if kind == Kind::Pine {
                        push(&mut bufs[PINE_LO], yaw, [s, s, s], up(1.6 * s), grade(tint, nat));
                        if fs > 0.35 {
                            push(&mut bufs[PINE_HI], yaw, [s, s, s], up(3.0 * s), grade(lightened(tint, 0.08), nat));
                        }
                        push(&mut bufs[TRUNK], yaw, [s, s, s], up(0.5 * s), trunk);
                    } else {
                        push(&mut bufs[TRUNK], yaw, [s, s * 1.4, s], up(0.7 * s), trunk);
                        push(&mut bufs[CROWN], yaw, [s, s * 0.9, s], up(2.4 * s), grade(tint, nat));
                        if fs > 0.35 {
                            let at = [base[0] + 0.6 * s, base[1] + 2.0 * s, base[2] + 0.3 * s];
                            push(&mut bufs[CROWN_SMALL], yaw, [s, s * 0.8, s], at, grade(darkened(tint, 0.08), nat));
                        }
                    }
                    counts[wi * 3] += 1;
                }
            }
        }
        let mut out = VarArray::new();
        for b in &bufs {
            out.push(&PackedFloat32Array::from(b.as_slice()).to_variant());
        }
        out.push(&PackedInt32Array::from(counts.as_slice()).to_variant());
        out
    }
}
