class_name World

const WORLD_WIDTH := 32
const WORLD_HEIGHT := 32
const TILE_SIZE := 2.0

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
}

var width: int = WORLD_WIDTH
var height: int = WORLD_HEIGHT
var seed_val: int
var tiles: Array = []          # tiles[z][x] = Dictionary
var cut_trees: Dictionary = {} # "x,z" → countdown float
var natural_fires: Dictionary = {} # "x,z" → { end_time }
var campfire_events: Array = []
var cows: Array = []
var predators: Array = []
var day: int = 1
var flora_slow_timer: float = 0.0

var _home_occupants: Dictionary = {}

func _init(p_seed: int = -1) -> void:
	if p_seed < 0:
		seed_val = randi() % 9999
	else:
		seed_val = p_seed
	_generate()
	_generate_glaciers()
	_generate_rivers()
	_generate_caves()

# ── RNG ───────────────────────────────────────────────────────────────────

func _rng(x: int, z: int, offset: float = 0.0) -> float:
	return fmod(abs(sin(x * 127.1 + z * 311.7 + offset * 74.5) * 43758.5453), 1.0)

func _noise(x: int, z: int) -> float:
	var s := seed_val * 0.137
	return (
		sin(x * 0.18 + s)        * cos(z * 0.14 + s * 1.71) * 0.45 +
		sin(x * 0.35 + s * 2.13) * cos(z * 0.29 + s * 0.63) * 0.30 +
		sin(x * 0.72 + s * 0.54) * cos(z * 0.61 + s * 1.23) * 0.15 +
		cos(x * 0.11 + z * 0.16 + s * 1.87)                  * 0.25
	) / 1.15

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
				var arid := (
					sin(x * 0.09 + s)       * cos(z * 0.07 + s * 1.6) * 0.50 +
					sin(x * 0.17 + s * 1.9) * cos(z * 0.13 + s * 0.5) * 0.30 +
					cos(x * 0.05 + z * 0.08 + s * 1.2)                 * 0.20
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
				"tree_cut": false,
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
		_:                 return 0.1

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

func _generate_rivers() -> void:
	const RIVER_CHANCE := 0.08
	const MAX_LEN := 24
	var terminal := [TileType.WATER, TileType.DEEP_WATER, TileType.BEACH]
	var blocked  := [TileType.GLACIER, TileType.MOUNTAIN]
	var dirs := [[-1,0],[1,0],[0,-1],[0,1]]

	for z in range(height):
		for x in range(width):
			var t: int = int(tiles[z][x]["type"])
			if t != TileType.MOUNTAIN and t != TileType.STONE: continue
			if _rng(x, z, 400) >= RIVER_CHANCE: continue

			var cx := x
			var cz := z
			for _step in range(MAX_LEN):
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

# ── Queries ─────────────────────────────────────────────────────────────────

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
	return t != TileType.WATER and t != TileType.DEEP_WATER and \
		   t != TileType.MOUNTAIN and t != TileType.GLACIER

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
	return true

func traversal_cost(x: float, z: float, knowledge: Dictionary) -> float:
	var tile := get_tile_f(x, z)
	if tile.is_empty(): return 1.0
	if tile.get("river", false) and not knowledge.has("rope_bridge"): return 1.8
	if tile["type"] == TileType.DESERT: return 1.5
	return 1.0

func get_season() -> String:
	var day_of_year := (day - 1) % 365
	if day_of_year < 91:  return "winter"
	if day_of_year < 181: return "spring"
	if day_of_year < 271: return "summer"
	return "autumn"

# ── Updates ─────────────────────────────────────────────────────────────────

func update_resources(delta: float, season: String) -> void:
	var mult := _season_mult(season)
	for z in range(height):
		for x in range(width):
			var tile: Dictionary = tiles[z][x]
			match tile["type"]:
				TileType.GRASS:    tile["resource"] = minf(1.0, tile["resource"] + 0.0020 * delta * mult)
				TileType.WOODLAND: tile["resource"] = minf(1.0, tile["resource"] + 0.0016 * delta * mult)
				TileType.FOREST:   tile["resource"] = minf(1.0, tile["resource"] + 0.0012 * delta * mult)
			if tile["herbs"] >= 0.0:
				tile["herbs"] = minf(1.0, tile["herbs"] + 0.0006 * delta * mult)
			if tile["mushrooms"] >= 0.0:
				tile["mushrooms"] = minf(1.0, tile["mushrooms"] + 0.0008 * delta * mult)

func _season_mult(season: String) -> float:
	match season:
		"spring": return 1.5
		"summer": return 2.0
		"autumn": return 1.0
		"winter": return 0.35
	return 1.0

func update_depletion(delta: float) -> void:
	for z in range(height):
		for x in range(width):
			var tile: Dictionary = tiles[z][x]
			if tile["depletion_level"] > 0.0:
				tile["depletion_level"] = maxf(0.0, tile["depletion_level"] - 0.002 * delta)

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
			tile["tree_cut"] = false

func cut_tree(x: int, z: int) -> bool:
	var tile := get_tile(x, z)
	if tile.is_empty(): return false
	if tile["type"] != TileType.FOREST and tile["type"] != TileType.WOODLAND: return false
	var key := "%d,%d" % [tile["x"], tile["z"]]
	if cut_trees.has(key): return false
	tile["tree_cut"] = true
	cut_trees[key] = 90.0 + randf() * 60.0
	return true

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

func get_spawn_points(count: int) -> Array:
	var candidates: Array = []
	for z in range(height):
		for x in range(width):
			if tiles[z][x]["type"] == TileType.GRASS:
				candidates.append({"x": x + 0.5, "z": z + 0.5})
	candidates.shuffle()
	return candidates.slice(0, count)

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
	var food_tiles := 0
	for z in range(height):
		for x in range(width):
			var t: int = int(tiles[z][x]["type"])
			if t == TileType.GRASS or t == TileType.WOODLAND or t == TileType.FOREST:
				food_tiles += 1
	return maxi(40, int(25 + food_tiles * 0.18))

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
