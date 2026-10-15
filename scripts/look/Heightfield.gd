class_name Heightfield
extends RefCounted
## The ground's real shape: a smooth 1 m heightfield made from the world's own
## noise (World.noise_at), so hills, valleys and coasts follow the same field
## the simulation's tiles were cut from. Corrected so it never disagrees with
## the tiles: water tiles sit under the sea, land tiles above it, rivers in a
## shallow groove. Everything that stands on the ground asks height_at().

const STEP := 1.0                 # metres between samples
const SEA_LEVEL := 0.0
const COAST := -0.22              # World._generate's water threshold
const LAND_SCALE := 7.0           # metres of rise per unit of noise above the coast
const MOUNTAIN_SCALE := 70.0      # extra rise on high ground (quadratic)
const SEA_SCALE := 18.0           # metres of depth per unit of noise below the coast
const LAND_MIN := 0.25            # land tiles are at least this far above the sea
const WATER_MAX := -0.6           # water tiles are at least this far below it
const RIVER_DEPTH := 0.45

var world: World                  # only while building
var n: int                        # samples per side
var size_m: float
var heights := PackedFloat32Array()
var biome := PackedFloat32Array()  # the noise value at each sample (for colour)

func build(p_world: World) -> Heightfield:
	world = p_world
	size_m = world.width * World.TILE_SIZE
	n = int(size_m / STEP) + 1
	heights.resize(n * n)
	biome.resize(n * n)
	var fix := PackedFloat32Array()
	fix.resize(n * n)
	for iz in n:
		for ix in n:
			var tx := ix * STEP / World.TILE_SIZE
			var tz := iz * STEP / World.TILE_SIZE
			var nv := world.noise_at(tx, tz)
			var h := _height_from_noise(nv, tx, tz)
			biome[iz * n + ix] = nv
			heights[iz * n + ix] = h
			fix[iz * n + ix] = _correction(h, tx, tz)
	# Soften the corrections so banks slope instead of stepping.
	for iz in range(1, n - 1):
		for ix in range(1, n - 1):
			var i := iz * n + ix
			var c := fix[i]
			if c == 0.0:
				var acc := 0.0
				for d in [-1, 1, -n, n]:
					acc += fix[i + d]
				c = acc * 0.15
			heights[i] += c
	# World holds us; holding it back would be a cycle that never frees.
	world = null
	return self

func _height_from_noise(nv: float, tx: float, tz: float) -> float:
	if nv < COAST:
		return (nv - COAST) * SEA_SCALE
	var above := nv - COAST
	var h := above * LAND_SCALE + pow(maxf(0.0, nv - 0.45), 2.0) * MOUNTAIN_SCALE
	# A little roughness so meadows aren't billiard tables.
	h += sin(tx * 1.7 + tz * 0.9) * cos(tz * 1.3 - tx * 0.4) * 0.18 * clampf(above * 4.0, 0.0, 1.0)
	return h

## How far a sample must move to agree with its tile.
func _correction(h: float, tx: float, tz: float) -> float:
	var tile := world.get_tile_f(tx, tz)
	if tile.is_empty():
		return 0.0
	var t := int(tile["type"])
	var water := t == World.TileType.WATER or t == World.TileType.DEEP_WATER
	if water:
		return minf(0.0, WATER_MAX - h)
	var c := maxf(0.0, LAND_MIN - h)
	if bool(tile.get("river", false)):
		c -= RIVER_DEPTH
	return c

## Ground height (metres) at a world-space point (bilinear).
func height_at(x: float, z: float) -> float:
	var fx := clampf(x / STEP, 0.0, n - 1.001)
	var fz := clampf(z / STEP, 0.0, n - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var ax := fx - ix
	var az := fz - iz
	var i := iz * n + ix
	return lerpf(lerpf(heights[i], heights[i + 1], ax), lerpf(heights[i + n], heights[i + n + 1], ax), az)

## Ground height under a tile-space point (what Agent.pos uses).
func height_at_tile(tx: float, tz: float) -> float:
	return height_at(tx * World.TILE_SIZE, tz * World.TILE_SIZE)

func normal_at(x: float, z: float) -> Vector3:
	var e := STEP
	return Vector3(height_at(x - e, z) - height_at(x + e, z), 2.0 * e,
		height_at(x, z - e) - height_at(x, z + e)).normalized()

func biome_at(x: float, z: float) -> float:
	var ix := clampi(int(round(x / STEP)), 0, n - 1)
	var iz := clampi(int(round(z / STEP)), 0, n - 1)
	return biome[iz * n + ix]
