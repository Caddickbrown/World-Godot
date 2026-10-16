class_name World

const WORLD_WIDTH := 128
const WORLD_HEIGHT := 128

# The generator's noise frequencies were authored against a 32x32 world.
# Coordinates are scaled by this so the macro landmass shape is preserved at
# any world size; a detail octave adds the finer variation the extra
# resolution can now carry.
const NOISE_REFERENCE_SIZE := 32.0
const TILE_SIZE := 2.0
## World-space height per elevation unit. Everything that stands on the ground
## (people, animals, props, the walker) uses surface_y() so it sits on the tile.
const HEIGHT_SCALE := 0.3

enum TileType {
	DEEP_WATER,
	WATER,
	BEACH,
	GRASS,
	WOODLAND,
	FOREST,
	DESERT,
	STONE,
	MOUNTAIN,
	GLACIER,
	LAVA, # appended at the end so existing integer values do not shift
}

var width: int = WORLD_WIDTH
var height: int = WORLD_HEIGHT
var seed_val: int
var tiles: Array = []          # tiles[z][x] = Dictionary
var cut_trees: Dictionary = {} # "x,z" → seconds until the stump sprouts
const STUMP_SECONDS := 120.0     # about a day as a stump
const SAPLING_GROWTH := 0.05
var natural_fires: Dictionary = {} # "x,z" → { end_time }
var campfire_events: Array = []
var cows: Array = []
var predators: Array = []
var day: int = 1
var flora_slow_timer: float = 0.0

# Tiles whose appearance changed since the renderer last looked. The terrain is
# chunk-meshed, so a changed tile has to name itself rather than the renderer
# rescanning 16k tiles to find out what moved.
var dirty_tiles: Array = []   # Array of Vector2i
## Tiles whose trees changed (grew a size, felled, burnt, planted) but whose
## ground didn't: only the flora redraws them, not the terrain mesh.
var flora_dirty: Dictionary = {}  # Vector2i -> true

# "x,z" → { x, z, melt } for every GLACIER tile. melt is 0 (full ice) to 1 (fully melted).
var glacier_data: Dictionary = {}

# Generalised ground-nesting sites (chickens, ducks, etc. — any species id).
# "x,z" → { species, x, z, clutch, max_clutch, clutch_timer, spawn_ready }
var nesting_sites: Dictionary = {}

# CAD-177: how many times traders have traversed each tile — "x,z" → float count.
# Written directly by movement/trade code, decayed daily via decay_trade_traffic().
var trade_traffic: Dictionary = {}
var _traffic_last_decay_day: int = 0

var _home_occupants: Dictionary = {}

# Continuous per-tile updates (regrowth, depletion recovery) are linear
# accumulators, so instead of touching all 16k tiles every frame we walk one
# stripe of rows per call and advance it by STRIPE_COUNT * delta. Aggregate
# behaviour is identical; the per-frame cost drops by the same factor.
const STRIPE_COUNT := 8
var _resource_stripe: int = 0
var _depletion_stripe: int = 0

# Carrying capacity needs a full scan, but the food-tile count only moves when
# terrain changes. Recompute at most once per in-game day.
var _capacity_cache: int = -1
## Upper bound on people, whatever the land could feed. The game is watched
## person by person, and past this the crowd stops being readable (the concept
## piece defaulted to 100, settable 40-300).
var max_population: int = 150
var _capacity_cache_day: int = -1

# Coordinate scale into the generator's reference space (1.0 at 32x32).
var _noise_scale: float = 1.0
# Area relative to the reference world; per-tile spawn probabilities that
# should produce a constant *count* rather than a constant density divide by it.
var _area_scale: float = 1.0

func _init(p_seed: int = -1) -> void:
	if p_seed < 0:
		seed_val = randi() % 9999
	else:
		seed_val = p_seed
	_noise_scale = NOISE_REFERENCE_SIZE / float(maxi(width, height))
	_area_scale = float(width * height) / (NOISE_REFERENCE_SIZE * NOISE_REFERENCE_SIZE)
	_generate()           # includes water-connectivity repair as its final pass
	_generate_glaciers()
	_generate_lava()
	_generate_rivers()
	_generate_caves()
	_init_glacier_melt()  # melt-state bookkeeping, after tile types are final
	_build_layers()

# ── Layers ─────────────────────────────────────────────────────────────────
## Values that whole-grid passes sweep live in packed arrays, one per field,
## indexed z * width + x, not in the tile Dictionaries: a Dictionary lookup
## is most of what such a pass costs. Read and write them through the
## accessors below. A whole-grid pass over layers can go to native code
## (native/world_kernels: ~360x a Dictionary pass) in one call.
## The type is kept in both: Dictionaries for everything that reads it,
## layer_type for the passes. Change a type only through set_type.
var layer_type := PackedByteArray()
var layer_resource := PackedFloat32Array()   # food to gather, 0..1
var layer_herbs := PackedFloat32Array()      # -1 none ever, else 0..1
var layer_mushrooms := PackedFloat32Array()  # -1 none ever, else 0..1
const LAYER_KEYS := ["resource", "herbs", "mushrooms"]
## The native kernels, when the library is built (native/build.sh); null
## runs the same passes in GDScript.
static var kernels: Object = null
static var _kernels_checked := false

## Generation writes Dictionaries; this moves the layered fields out of them
## (and erases the keys, so a forgotten tile["herbs"] fails loudly).
func _build_layers() -> void:
	var n := width * height
	layer_type.resize(n)
	layer_resource.resize(n)
	layer_herbs.resize(n)
	layer_mushrooms.resize(n)
	for z in height:
		for x in width:
			var tile: Dictionary = tiles[z][x]
			var i := z * width + x
			layer_type[i] = int(tile["type"])
			layer_resource[i] = float(tile["resource"])
			layer_herbs[i] = float(tile["herbs"])
			layer_mushrooms[i] = float(tile["mushrooms"])
			for k in LAYER_KEYS:
				tile.erase(k)
	if not _kernels_checked:
		_kernels_checked = true
		if ClassDB.class_exists("Kernels"):
			kernels = ClassDB.instantiate("Kernels")

func _i(tile: Dictionary) -> int:
	return int(tile["z"]) * width + int(tile["x"])

func food_of(tile: Dictionary) -> float:
	return layer_resource[_i(tile)] if not tile.is_empty() else 0.0

func set_food(tile: Dictionary, v: float) -> void:
	layer_resource[_i(tile)] = v

func herbs_of(tile: Dictionary) -> float:
	return layer_herbs[_i(tile)] if not tile.is_empty() else -1.0

func set_herbs(tile: Dictionary, v: float) -> void:
	layer_herbs[_i(tile)] = v

func mushrooms_of(tile: Dictionary) -> float:
	return layer_mushrooms[_i(tile)] if not tile.is_empty() else -1.0

func set_type(tile: Dictionary, t: int) -> void:
	tile["type"] = t
	layer_type[_i(tile)] = t

## A tile's value by name, layered or not (ideas name them in data).
func tile_value(tile: Dictionary, key: String, default: float = -1.0) -> float:
	if tile.is_empty():
		return default
	match key:
		"resource": return food_of(tile)
		"herbs": return herbs_of(tile)
		"mushrooms": return mushrooms_of(tile)
	return float(tile.get(key, default))

# ── RNG ───────────────────────────────────────────────────────────────────

func _rng(x: int, z: int, offset: float = 0.0) -> float:
	return fmod(abs(sin(x * 127.1 + z * 311.7 + offset * 74.5) * 43758.5453), 1.0)

func _noise(x: int, z: int) -> float:
	return noise_at(float(x), float(z))

## The world's shape field at any tile-space point (fractional coordinates are
## valid: it is a sum of sines). Below -0.22 is sea. The world is an island:
## the field falls away near the map edge so land never meets the border.
## The terrain renderer samples this same function, so look and sim agree.
func noise_at(x: float, z: float) -> float:
	var u := absf(x / float(width) * 2.0 - 1.0)
	var v := absf(z / float(height) * 2.0 - 1.0)
	return _raw_noise(x, z) - smoothstep(ISLAND_EDGE_START, 1.0, maxf(u, v)) * ISLAND_EDGE_DROP

## Fraction of the half-width where the island starts falling to the sea.
const ISLAND_EDGE_START := 0.72
const ISLAND_EDGE_DROP := 0.9

func _raw_noise(x: float, z: float) -> float:
	var s := seed_val * 0.137
	# Scale into the reference space so landmasses keep their shape at any size.
	var fx := x * _noise_scale
	var fz := z * _noise_scale
	var base := (
		sin(fx * 0.18 + s)        * cos(fz * 0.14 + s * 1.71) * 0.45 +
		sin(fx * 0.35 + s * 2.13) * cos(fz * 0.29 + s * 0.63) * 0.30 +
		sin(fx * 0.72 + s * 0.54) * cos(fz * 0.61 + s * 1.23) * 0.15 +
		cos(fx * 0.11 + fz * 0.16 + s * 1.87)                  * 0.25
	) / 1.15
	# Detail octave at native resolution — too fine to see at 32x32, adds
	# coastline and ridge variation once the world is larger.
	if _noise_scale < 1.0:
		var detail := (
			sin(x * 0.31 + s * 3.1) * cos(z * 0.27 + s * 2.2) * 0.6 +
			sin(x * 0.63 + s * 1.4) * cos(z * 0.55 + s * 3.7) * 0.4
		)
		base += detail * 0.055 * (1.0 - _noise_scale)
	return base

# ── Generation ─────────────────────────────────────────────────────────────

func _generate() -> void:
	tiles = []
	for z in range(height):
		var row: Array = []
		for x in range(width):
			var n := _noise(x, z)
			var t: int
			if   n < -0.22: t = TileType.WATER
			elif n < -0.08: t = TileType.BEACH
			elif n <  0.18: t = TileType.GRASS
			elif n <  0.30: t = TileType.WOODLAND
			elif n <  0.52: t = TileType.FOREST
			elif n <  0.72: t = TileType.STONE
			else:           t = TileType.MOUNTAIN

			if t == TileType.GRASS or t == TileType.WOODLAND or t == TileType.FOREST:
				var s := seed_val * 0.491
				var ax := float(x) * _noise_scale
				var az := float(z) * _noise_scale
				var arid := (
					sin(ax * 0.09 + s)       * cos(az * 0.07 + s * 1.6) * 0.50 +
					sin(ax * 0.17 + s * 1.9) * cos(az * 0.13 + s * 0.5) * 0.30 +
					cos(ax * 0.05 + az * 0.08 + s * 1.2)                 * 0.20
				) / 1.0 + 0.5
				if arid > 0.91:
					t = TileType.DESERT

			var base_elev := _base_elevation(t)
			var elev := base_elev + (sin(x * 3.7 + z * 2.3 + seed_val) * 0.5 + 0.5) * 0.06

			var gatherable := t == TileType.GRASS or t == TileType.WOODLAND or t == TileType.FOREST
			var is_forest := t == TileType.FOREST
			var init_tree_age := 0.0
			var tree_stage := ""
			if is_forest:
				init_tree_age = (sin(x * 71.3 + z * 53.7) * 0.5 + 0.5) * 250.0
				tree_stage = _tree_stage_from_age(init_tree_age)

			var tile := {
				"type": t, "x": x, "z": z,
				"elevation": elev,
				"resource": 1.0,
				"depletion_level": 0.0 if gatherable else -1.0,
				"tree_age": init_tree_age if is_forest else -1.0,
				"tree_stage": tree_stage,
				"tree_cut": false,             # felled: a stump until a sapling comes up
				"growth": 1.0 if t == TileType.FOREST or t == TileType.WOODLAND else -1.0,  # 0 seedling .. 1 grown
				"burnt": 0.0,                  # seconds left as charred snags after a fire
				"planted": false,              # someone put this wood here
				"river": false,
				"cave": false,
				"is_shelter": false,
				"herbs": -1.0,
				"mushrooms": -1.0,
				"flint": 0,
			}
			row.append(tile)
		tiles.append(row)

	# Second pass: deep water
	for z in range(height):
		for x in range(width):
			if tiles[z][x]["type"] != TileType.WATER:
				continue
			var all_water := true
			for delta_pair in [[-1,0],[1,0],[0,-1],[0,1]]:
				var nx: int = x + delta_pair[0]
				var nz: int = z + delta_pair[1]
				if nx < 0 or nx >= width or nz < 0 or nz >= height:
					continue
				var nt: int = int(tiles[nz][nx]["type"])
				if nt != TileType.WATER and nt != TileType.DEEP_WATER:
					all_water = false
					break
			if all_water:
				tiles[z][x]["type"] = TileType.DEEP_WATER

	# Third pass: resource fields
	for z in range(height):
		for x in range(width):
			var tile: Dictionary = tiles[z][x]
			if tile["type"] == TileType.WOODLAND:
				if _rng(x, z, 301) < 0.30:
					tile["herbs"] = 1.0
			if tile["type"] == TileType.FOREST:
				if _rng(x, z, 301) < 0.45: tile["herbs"] = 1.0
				if _rng(x, z, 303) < 0.30: tile["mushrooms"] = 1.0
			if tile["type"] == TileType.GRASS and _has_adj_type(x, z, TileType.WATER):
				if _rng(x, z, 302) < 0.35: tile["herbs"] = 1.0
			if tile["type"] == TileType.STONE:
				if _rng(x, z, 306) < 0.25: tile["flint"] = 1

	# Fourth pass: fix water connectivity — remove isolated puddles, smooth coastlines.
	# Must run before glaciers/lava/rivers touch STONE/MOUNTAIN tiles.
	_fix_water_connectivity()

func _base_elevation(t: int) -> float:
	match t:
		TileType.WATER:    return 0.04
		TileType.BEACH:    return 0.06
		TileType.GRASS:    return 0.12
		TileType.WOODLAND: return 0.17
		TileType.FOREST:   return 0.22
		TileType.DESERT:   return 0.12
		TileType.STONE:    return 0.32
		TileType.MOUNTAIN: return 1.5
		TileType.GLACIER:  return 0.60
		TileType.LAVA:     return 0.08
		_:                 return 0.1

# Remove isolated inland puddles (<4 connected WATER/DEEP_WATER tiles become BEACH)
# and smooth coastlines: lone BEACH deep in grassland becomes GRASS, GRASS mostly
# surrounded by water becomes BEACH. Matters far more at 128x128 than at 32x32,
# where the coarse noise field can leave single-tile puddles inland.
func _fix_water_connectivity() -> void:
	var visited: Dictionary = {}
	var bodies: Array = []

	for z in range(height):
		for x in range(width):
			var key0 := "%d,%d" % [x, z]
			var t0: int = int(tiles[z][x]["type"])
			if (t0 != TileType.WATER and t0 != TileType.DEEP_WATER) or visited.has(key0):
				continue
			# BFS this water body.
			var body: Array = []
			var queue: Array = [Vector2i(x, z)]
			var qi := 0
			while qi < queue.size():
				var c: Vector2i = queue[qi]
				qi += 1
				var key := "%d,%d" % [c.x, c.y]
				if visited.has(key): continue
				visited[key] = true
				if c.x < 0 or c.x >= width or c.y < 0 or c.y >= height: continue
				var t: int = int(tiles[c.y][c.x]["type"])
				if t != TileType.WATER and t != TileType.DEEP_WATER: continue
				body.append(c)
				queue.append(Vector2i(c.x + 1, c.y))
				queue.append(Vector2i(c.x - 1, c.y))
				queue.append(Vector2i(c.x, c.y + 1))
				queue.append(Vector2i(c.x, c.y - 1))
			bodies.append(body)

	# Remove isolated water bodies (< 4 tiles).
	for body in bodies:
		if body.size() < 4:
			for c2 in body:
				var cc: Vector2i = c2
				tiles[cc.y][cc.x]["type"] = TileType.BEACH

	# Coastal smoothing.
	var diag8 := [[-1,0],[1,0],[0,-1],[0,1],[-1,-1],[1,-1],[-1,1],[1,1]]
	for z in range(height):
		for x in range(width):
			var tile: Dictionary = tiles[z][x]
			var t: int = int(tile["type"])
			if t != TileType.BEACH and t != TileType.GRASS: continue
			var grass_count := 0
			var water_count := 0
			for d in diag8:
				var nx: int = x + d[0]
				var nz: int = z + d[1]
				if nx < 0 or nx >= width or nz < 0 or nz >= height: continue
				var nt: int = int(tiles[nz][nx]["type"])
				if nt == TileType.GRASS or nt == TileType.WOODLAND or nt == TileType.FOREST:
					grass_count += 1
				elif nt == TileType.WATER or nt == TileType.DEEP_WATER:
					water_count += 1
			if t == TileType.BEACH and grass_count >= 5:
				tile["type"] = TileType.GRASS
			elif t == TileType.GRASS and water_count >= 4:
				tile["type"] = TileType.BEACH

func _has_adj_type(x: int, z: int, t: int) -> bool:
	for d in [[-1,0],[1,0],[0,-1],[0,1]]:
		var nx: int = x + d[0]
		var nz: int = z + d[1]
		if nx < 0 or nx >= width or nz < 0 or nz >= height: continue
		if tiles[nz][nx]["type"] == t: return true
	return false

func _generate_glaciers() -> void:
	for z in range(height):
		for x in range(width):
			var tile: Dictionary = tiles[z][x]
			if tile["type"] != TileType.STONE: continue
			var near_mountain := false
			for dz in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if dx == 0 and dz == 0: continue
					var nx: int = x + dx
					var nz: int = z + dz
					if nx < 0 or nx >= width or nz < 0 or nz >= height: continue
					if tiles[nz][nx]["type"] == TileType.MOUNTAIN:
						near_mountain = true
						break
				if near_mountain: break
			if near_mountain and _rng(x, z, 500) < 0.40:
				tile["type"] = TileType.GLACIER
				tile["elevation"] = 0.60

# Small LAVA patches near MOUNTAIN tiles: ~15% of STONE tiles directly (4-dir)
# adjacent to a MOUNTAIN become LAVA. LAVA is always impassable and damaging.
func _generate_lava() -> void:
	for z in range(height):
		for x in range(width):
			var tile: Dictionary = tiles[z][x]
			if tile["type"] != TileType.STONE: continue
			var near_mountain := false
			for d in [[-1,0],[1,0],[0,-1],[0,1]]:
				var nx: int = x + d[0]
				var nz: int = z + d[1]
				if nx < 0 or nx >= width or nz < 0 or nz >= height: continue
				if tiles[nz][nx]["type"] == TileType.MOUNTAIN:
					near_mountain = true
					break
			if near_mountain and _rng(x, z, 600) < 0.15:
				tile["type"] = TileType.LAVA
				tile["elevation"] = 0.08

func _generate_rivers() -> void:
	# Source chance is per mountain/stone tile, so divide by area to keep the
	# number of rivers stable rather than scaling with the tile count.
	var river_chance: float = 0.08 / maxf(_area_scale, 1.0)
	var max_len: int = int(24 * maxf(1.0, float(maxi(width, height)) / NOISE_REFERENCE_SIZE))
	var terminal := [TileType.WATER, TileType.DEEP_WATER, TileType.BEACH]
	var blocked  := [TileType.GLACIER, TileType.MOUNTAIN]
	var dirs := [[-1,0],[1,0],[0,-1],[0,1]]

	for z in range(height):
		for x in range(width):
			var t: int = int(tiles[z][x]["type"])
			if t != TileType.MOUNTAIN and t != TileType.STONE: continue
			if _rng(x, z, 400) >= river_chance: continue

			var cx := x
			var cz := z
			for _step in range(max_len):
				var tile: Dictionary = tiles[cz][cx]
				if tile["type"] in terminal: break
				tile["river"] = true
				var cur_elev := _noise(cx, cz)
				var best_elev := cur_elev
				var best_x := -1
				var best_z := -1
				for d in dirs:
					var nx: int = cx + d[0]
					var nz: int = cz + d[1]
					if nx < 0 or nx >= width or nz < 0 or nz >= height: continue
					if tiles[nz][nx]["type"] in blocked: continue
					var ne := _noise(nx, nz)
					if ne < best_elev:
						best_elev = ne
						best_x = nx
						best_z = nz
				if best_x == -1: break
				cx = best_x
				cz = best_z

func _generate_caves() -> void:
	for z in range(height):
		for x in range(width):
			var tile: Dictionary = tiles[z][x]
			if tile["type"] != TileType.MOUNTAIN: continue
			if _rng(x, z, 450) < 0.10:
				tile["cave"] = true
				tile["is_shelter"] = true

# ── Glaciers (melt data) ─────────────────────────────────────────────────────

func _init_glacier_melt() -> void:
	glacier_data.clear()
	for z in range(height):
		for x in range(width):
			if tiles[z][x]["type"] != TileType.GLACIER: continue
			glacier_data["%d,%d" % [x, z]] = {"x": x, "z": z, "melt": 0.0}

# Glaciers retreat (melt → 1) when warm, hold/advance (melt → 0) when cold.
# glacier_data is a sparse subset of tiles (only actual GLACIER tiles), so this
# is not a full-world scan and needs no striping.
func update_glaciers(delta: float, temperature: float) -> void:
	var rate: float = (temperature / 25.0) * 0.00028
	for key in glacier_data:
		var g: Dictionary = glacier_data[key]
		g["melt"] = clampf(g["melt"] + rate * delta, 0.0, 1.0)

# ── Queries ─────────────────────────────────────────────────────────────────

# Systems that mutate a tile's appearance (type, tree_cut, river) call this so
# the renderer can rebuild just the affected chunk.
func mark_tile_dirty(x: int, z: int) -> void:
	dirty_tiles.append(Vector2i(x, z))

func mark_flora_dirty(x: int, z: int) -> void:
	flora_dirty[Vector2i(x, z)] = true

func drain_flora_dirty() -> Array:
	if flora_dirty.is_empty():
		return []
	var out := flora_dirty.keys()
	flora_dirty = {}
	return out

## Trees on a tile: FOREST and WOODLAND grow them (meadow trees are scenery).
static func has_woods(tile: Dictionary) -> bool:
	var t := int(tile.get("type", -1))
	return t == TileType.FOREST or t == TileType.WOODLAND

func drain_dirty_tiles() -> Array:
	if dirty_tiles.is_empty():
		return []
	var out := dirty_tiles
	dirty_tiles = []
	return out

func get_tile(x: int, z: int) -> Dictionary:
	var tx := int(floor(x))
	var tz := int(floor(z))
	if tx < 0 or tx >= width or tz < 0 or tz >= height:
		return {}
	return tiles[tz][tx]

func get_tile_f(x: float, z: float) -> Dictionary:
	return get_tile(int(floor(x)), int(floor(z)))

func is_walkable(x: float, z: float) -> bool:
	var tile := get_tile_f(x, z)
	if tile.is_empty(): return false
	var t: int = int(tile["type"])
	if bool(tile.get("flooded", false)):   # under a flood (DisasterSystem)
		return false
	return t != TileType.WATER and t != TileType.DEEP_WATER and \
		   t != TileType.MOUNTAIN and t != TileType.GLACIER and t != TileType.LAVA

func can_traverse(x: float, z: float, knowledge: Dictionary) -> bool:
	var tile := get_tile_f(x, z)
	if tile.is_empty(): return false
	var t: int = int(tile["type"])
	if t == TileType.WATER or t == TileType.DEEP_WATER:
		return knowledge.has("sailing")
	if t == TileType.MOUNTAIN:
		return knowledge.has("mountain_climbing")
	if t == TileType.GLACIER:
		return false
	if t == TileType.LAVA:
		return false
	return true

func traversal_cost(x: float, z: float, knowledge: Dictionary) -> float:
	var tile := get_tile_f(x, z)
	if tile.is_empty(): return 1.0
	if tile.get("river", false) and not knowledge.has("rope_bridge"): return 1.8
	if tile["type"] == TileType.DESERT: return 1.5
	return 1.0

## The smooth ground (a Heightfield), built by Main for the look. Without one
## (tests, tools) the ground is the old per-tile step height.
var heightfield = null

## Height of the ground (world units) under a tile-space point.
func surface_y(x: float, z: float) -> float:
	if heightfield != null:
		return maxf(heightfield.height_at_tile(x, z), 0.0)
	var tile := get_tile_f(x, z)
	if tile.is_empty(): return 0.0
	return float(tile["elevation"]) * HEIGHT_SCALE

func get_season() -> String:
	return TimeSystem.season_for_day(day).to_lower()

# ── Updates ─────────────────────────────────────────────────────────────────

func update_resources(delta: float, season: String) -> void:
	var d := delta * float(STRIPE_COUNT) * _season_mult(season)
	var start := _resource_stripe
	_resource_stripe = (_resource_stripe + 1) % STRIPE_COUNT
	if kernels:
		var out: Array = kernels.regrow(layer_resource, layer_herbs, layer_mushrooms, layer_type, width, start, STRIPE_COUNT, d)
		layer_resource = out[0]
		layer_herbs = out[1]
		layer_mushrooms = out[2]
	else:
		regrow_gd(start, STRIPE_COUNT, d)

## update_resources in GDScript (what native/world_kernels regrow does).
func regrow_gd(start: int, stride: int, d: float) -> void:
	for z in range(start, height, stride):
		for i in range(z * width, (z + 1) * width):
			var g := 0.0
			match layer_type[i]:
				TileType.GRASS:    g = 0.0020
				TileType.WOODLAND: g = 0.0016
				TileType.FOREST:   g = 0.0012
			if g > 0.0:
				layer_resource[i] = minf(1.0, layer_resource[i] + g * d)
			if layer_herbs[i] >= 0.0:
				layer_herbs[i] = minf(1.0, layer_herbs[i] + 0.0006 * d)
			if layer_mushrooms[i] >= 0.0:
				layer_mushrooms[i] = minf(1.0, layer_mushrooms[i] + 0.0008 * d)

func _season_mult(season: String) -> float:
	match season:
		"spring": return 1.5
		"summer": return 2.0
		"autumn": return 1.0
		"winter": return 0.35
	return 1.0

func update_depletion(delta: float) -> void:
	var d := delta * float(STRIPE_COUNT)
	var start := _depletion_stripe
	_depletion_stripe = (_depletion_stripe + 1) % STRIPE_COUNT
	for z in range(start, height, STRIPE_COUNT):
		for x in range(width):
			var tile: Dictionary = tiles[z][x]
			if tile["depletion_level"] > 0.0:
				tile["depletion_level"] = maxf(0.0, tile["depletion_level"] - 0.002 * d)

func update_cut_trees(delta: float) -> void:
	var to_remove: Array = []
	for key in cut_trees:
		cut_trees[key] -= delta
		if cut_trees[key] <= 0.0:
			to_remove.append(key)
	for key in to_remove:
		cut_trees.erase(key)
		var parts: PackedStringArray = key.split(",")
		var tile := get_tile(int(parts[0]), int(parts[1]))
		if not tile.is_empty():
			# A stump sends up a sapling, which then has to grow (ForestSystem).
			tile["tree_cut"] = false
			tile["growth"] = SAPLING_GROWTH
			mark_tile_dirty(int(tile["x"]), int(tile["z"]))
			mark_flora_dirty(int(tile["x"]), int(tile["z"]))

func cut_tree(x: int, z: int) -> bool:
	var tile := get_tile(x, z)
	if tile.is_empty(): return false
	if tile["type"] != TileType.FOREST and tile["type"] != TileType.WOODLAND: return false
	var key := "%d,%d" % [tile["x"], tile["z"]]
	if cut_trees.has(key): return false
	tile["tree_cut"] = true
	tile["growth"] = 0.0
	cut_trees[key] = STUMP_SECONDS * (0.8 + randf() * 0.4)
	mark_tile_dirty(int(tile["x"]), int(tile["z"]))
	mark_flora_dirty(int(tile["x"]), int(tile["z"]))
	return true

## Replant a felled tile at once (forestry): the stump becomes a sapling.
func replant(x: int, z: int) -> void:
	var tile := get_tile(x, z)
	if tile.is_empty():
		return
	cut_trees.erase("%d,%d" % [x, z])
	tile["tree_cut"] = false
	tile["growth"] = SAPLING_GROWTH
	tile["planted"] = true
	mark_tile_dirty(x, z)
	mark_flora_dirty(x, z)

# ── Nesting sites (generalised ground-nesting fauna) ─────────────────────────
#
# Any ground-nesting species (chickens, ducks, ...) can use these tiles: a
# clutch timer accumulates eggs, and once the clutch is full the nest is
# spawn-ready. update_nests() reports spawn events; the caller (fauna system)
# is responsible for actually spawning the animal and then calling
# consume_nest_spawn() to reset the nest for its next cycle.

# Registers ground-nesting sites on the given tiles for one species.
# `tile_coords` is an Array of Vector2i (or anything with .x/.y) tile coordinates.
func init_nesting_sites(tile_coords: Array, species: String, max_clutch: int = 3) -> void:
	for tc in tile_coords:
		var tx: int = int(tc.x)
		var tz: int = int(tc.y)
		nesting_sites["%d,%d" % [tx, tz]] = {
			"species": species,
			"x": tx, "z": tz,
			"clutch": 0,
			"max_clutch": max_clutch,
			"clutch_timer": 10.0 + randf() * 20.0, # stagger initial lay times
			"spawn_ready": false,
		}

# Ticks clutch timers. Each nest lays one egg per ~20–35 game-seconds until its
# clutch is full, at which point it becomes spawn-ready and stops accumulating.
# Returns an Array of spawn events: [{ "x", "z", "species" }, ...] for newly
# spawn-ready nests this tick, for the caller to act on.
func update_nests(delta: float) -> Array:
	var events: Array = []
	for key in nesting_sites:
		var nest: Dictionary = nesting_sites[key]
		if nest["spawn_ready"]: continue
		nest["clutch_timer"] -= delta
		if nest["clutch_timer"] <= 0.0:
			nest["clutch"] += 1
			nest["clutch_timer"] = 20.0 + randf() * 15.0
			if int(nest["clutch"]) >= int(nest["max_clutch"]):
				nest["spawn_ready"] = true
				events.append({"x": nest["x"], "z": nest["z"], "species": nest["species"]})
	return events

# Call once the caller has spawned an animal from a spawn-ready nest, to reset
# it (clutch back to 0) so it can start accumulating again.
func consume_nest_spawn(x: int, z: int) -> void:
	var key := "%d,%d" % [x, z]
	if not nesting_sites.has(key): return
	var nest: Dictionary = nesting_sites[key]
	nest["clutch"] = 0
	nest["spawn_ready"] = false
	nest["clutch_timer"] = 20.0 + randf() * 15.0

# ── Domestication ─────────────────────────────────────────────────────────────

# Domestication feedback: nesting sites within `radius` tiles of a building get
# a lay-rate bonus (matches the 1.3x chicken-nest bonus from the JS prototype,
# generalised to any species). `building_positions` is an Array of Vector2 (or
# Vector2i) where .x is the tile x and .y is the tile z — building/animal data
# this file cannot reach on its own, so the caller supplies positions.
func update_domestication(delta: float, building_positions: Array, radius: float = 4.0) -> void:
	if building_positions.is_empty(): return
	for key in nesting_sites:
		var nest: Dictionary = nesting_sites[key]
		if nest["spawn_ready"]: continue
		var nx: float = float(nest["x"])
		var nz: float = float(nest["z"])
		var near := false
		for b in building_positions:
			var bx: float = float(b.x)
			var bz: float = float(b.y)
			if Vector2(bx - nx, bz - nz).length() <= radius:
				near = true
				break
		if near:
			nest["clutch_timer"] -= delta * 0.3

# ── Trade traffic ─────────────────────────────────────────────────────────────

# CAD-177: Convenience accumulator — callers may also write trade_traffic
# directly, matching the JS pattern of incrementing world._tradeTraffic in place.
func add_trade_traffic(x: int, z: int, amount: float = 1.0) -> void:
	var key := "%d,%d" % [x, z]
	trade_traffic[key] = float(trade_traffic.get(key, 0.0)) + amount

# CAD-177: Decay trade traffic counts once per in-game day. Paths fade if unused.
func decay_trade_traffic(current_day: int) -> void:
	if current_day - _traffic_last_decay_day < 1: return
	_traffic_last_decay_day = current_day
	var to_remove: Array = []
	for key in trade_traffic:
		trade_traffic[key] = float(trade_traffic[key]) * 0.98
		if float(trade_traffic[key]) < 0.5:
			to_remove.append(key)
	for key in to_remove:
		trade_traffic.erase(key)

func flora_slow_tick(delta: float, season: String) -> void:
	var growth_mult := _flora_growth_mult(season)
	for z in range(height):
		for x in range(width):
			var tile: Dictionary = tiles[z][x]
			if tile["depletion_level"] > 0.0:
				tile["depletion_level"] = maxf(0.0, tile["depletion_level"] - 0.02 * growth_mult * (delta / 10.0))
			if tile["type"] == TileType.FOREST and tile["tree_age"] >= 0.0 and not tile["tree_cut"]:
				tile["tree_age"] += delta / 120.0
				tile["tree_stage"] = _tree_stage_from_age(tile["tree_age"])

func _flora_growth_mult(season: String) -> float:
	match season:
		"spring": return 1.8
		"summer": return 1.2
		"autumn": return 0.6
		"winter": return 0.1
	return 1.0

static func _tree_stage_from_age(age: float) -> String:
	if age < 5.0:   return "seedling"
	if age < 30.0:  return "sapling"
	if age < 200.0: return "mature"
	return "old"

static func is_depleted(tile: Dictionary) -> bool:
	return tile.get("depletion_level", 0.0) > 0.7

# ── Spawn points ─────────────────────────────────────────────────────────────

# Agents spawn as a single band, not scattered across the whole map. On a large
# world a uniform scatter puts founders a hundred tiles apart, so they never meet
# and no society ever forms. Pick the most food-rich grass region and seed there.
func get_spawn_points(count: int) -> Array:
	var grass: Array = []
	for z in range(height):
		for x in range(width):
			if tiles[z][x]["type"] == TileType.GRASS:
				grass.append(Vector2i(x, z))
	if grass.is_empty():
		return get_land_spawn_points(count)

	var origin := _pick_spawn_origin(grass)

	# Collect grass tiles nearest the chosen origin, widening until we have enough.
	var scored: Array = []
	for g in grass:
		var gx: Vector2i = g
		var d := Vector2(gx.x - origin.x, gx.y - origin.y).length()
		scored.append({"x": gx.x, "z": gx.y, "d": d})
	scored.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]))

	# Take from a pool a few times the requested size so the band has some spread
	# rather than being a solid block.
	var pool_size: int = mini(scored.size(), maxi(count * 4, count))
	var pool: Array = scored.slice(0, pool_size)
	pool.shuffle()

	var out: Array = []
	for i in range(mini(count, pool.size())):
		out.append({"x": float(pool[i]["x"]) + 0.5, "z": float(pool[i]["z"]) + 0.5})
	return out

# Scores candidate grass tiles by how much food/forest sits within a short radius
# and returns the best, so founders start somewhere survivable.
func _pick_spawn_origin(grass: Array) -> Vector2i:
	var best := grass[0] as Vector2i
	var best_score := -1.0
	# Sample rather than scoring every grass tile — this runs at world init.
	var step: int = maxi(1, grass.size() / 400)
	var i := 0
	while i < grass.size():
		var g := grass[i] as Vector2i
		var score := 0.0
		for dz in range(-4, 5):
			for dx in range(-4, 5):
				var t := get_tile(g.x + dx, g.y + dz)
				if t.is_empty():
					score -= 0.5   # penalise map edges
					continue
				match int(t["type"]):
					TileType.GRASS:    score += 1.0
					TileType.WOODLAND: score += 1.4
					TileType.FOREST:   score += 1.2
					TileType.WATER:    score += 0.8
					TileType.MOUNTAIN: score -= 0.6
					TileType.DEEP_WATER: score -= 1.0
		if score > best_score:
			best_score = score
			best = g
		i += step
	return best

func get_land_spawn_points(count: int) -> Array:
	var candidates: Array = []
	for z in range(height):
		for x in range(width):
			var t: int = int(tiles[z][x]["type"])
			if t == TileType.GRASS or t == TileType.WOODLAND or t == TileType.FOREST:
				candidates.append({"x": x + 0.5, "z": z + 0.5})
	candidates.shuffle()
	return candidates.slice(0, count)

func get_carrying_capacity() -> int:
	# Called every frame from several places; the underlying food-tile count
	# only shifts when terrain does, so one full scan per in-game day is plenty.
	if _capacity_cache_day == day and _capacity_cache >= 0:
		return _capacity_cache
	var food_tiles := 0
	for z in range(height):
		for x in range(width):
			var t: int = int(tiles[z][x]["type"])
			if t == TileType.GRASS or t == TileType.WOODLAND or t == TileType.FOREST:
				food_tiles += 1
	_capacity_cache = clampi(int(25 + food_tiles * 0.18), 40, max_population)
	_capacity_cache_day = day
	return _capacity_cache

func find_nearest(cx: float, cz: float, types: Array, radius: float = 10.0) -> Dictionary:
	var best := {}
	var best_dist := INF
	var r := int(ceil(radius))
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var dist := sqrt(dx * dx + dz * dz)
			if dist > radius: continue
			var tile := get_tile(int(cx) + dx, int(cz) + dz)
			if tile.is_empty() or not (tile["type"] in types): continue
			if dist < best_dist:
				best_dist = dist
				best = tile
	return best

func get_tiles_of_type(types: Array) -> Array:
	var out: Array = []
	for z in range(height):
		for x in range(width):
			if tiles[z][x]["type"] in types:
				out.append(tiles[z][x])
	return out
