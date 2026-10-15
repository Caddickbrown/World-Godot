class_name EcologySystem
extends RefCounted

# "x,z" → float — accumulated seconds any agent has stood on this GRASS tile.
var _overgrazing: Dictionary = {}

var _forest_timer: float = 0.0
var _graze_timer: float = 0.0

const FOREST_SPREAD_INTERVAL   := 10.0
const GRAZE_CHECK_INTERVAL     := 5.0
const DAY_LENGTH               := 120.0   # seconds per in-game day (matches TimeSystem)

# Forest spread / revert daily probabilities.
const SPREAD_CHANCE_PER_DAY    := 0.04   # per edge; grown woodland seeds at half this
const REVERT_CHANCE_PER_DAY    := 0.002
const SUCCESSION_CHANCE_PER_DAY := 0.01   # grown woodland next to forest becomes forest

# Overgrazing thresholds.
const OVERGRAZE_AGENT_THRESH   := 3       # agents on tile at once
const OVERGRAZE_TIME_THRESH    := 300.0   # seconds before degradation
const OVERGRAZE_DECAY          := 10.0    # sec/sec decay when tile is empty
const OVERGRAZE_RECOVER_TIME   := 3600.0  # seconds before DESERT recovers to GRASS

# Soil regeneration rates.
const SOIL_REGEN_FOREST        := 0.001   # per second
const SOIL_REGEN_BURNOUT       := 0.005   # per second for post-fire GRASS

# Herb spawn chance when WOODLAND is created.
const HERB_SPAWN_CHANCE        := 0.30

# ── Public helpers ────────────────────────────────────────────────────────────

func get_soil_quality(tile: Dictionary) -> float:
	return float(tile.get("soil_quality", 1.0))

func get_moisture(tile: Dictionary) -> float:
	return float(tile.get("moisture", 0.4))

# ── Main tick ─────────────────────────────────────────────────────────────────

# Continuous full-world passes are striped across frames: each call handles one
# row in STRIPE_COUNT and advances by STRIPE_COUNT * delta. These are linear
# accumulators and rare-event checks, so the aggregate result is unchanged.
const STRIPE_COUNT := 8
var _soil_stripe: int = 0
var _desert_stripe: int = 0

func tick(delta: float, world: World, agents: Array, day: int, history_log: HistoryLog) -> void:
	_forest_timer += delta
	if _forest_timer >= FOREST_SPREAD_INTERVAL:
		_forest_timer -= FOREST_SPREAD_INTERVAL
		_do_forest_spread(world, day, history_log)

	_graze_timer += delta
	if _graze_timer >= GRAZE_CHECK_INTERVAL:
		_graze_timer -= GRAZE_CHECK_INTERVAL
		_do_overgraze_check(agents, world, day, history_log)

	_tick_soil(delta, world)
	_tick_overgraze_decay(delta, world, day, history_log)

# ── Forest spread ─────────────────────────────────────────────────────────────

var return_pos := Vector2(-1, -1)   # where the burnt woods first came back (for the story)
var _told_return := false

func _do_forest_spread(world: World, day: int = 0, history_log: HistoryLog = null) -> void:
	# Convert seconds-elapsed to a per-tick probability.
	# P(event in interval) = 1 - (1-daily_chance)^(interval/day_length)
	# For small daily chances: approx = daily_chance * (interval / day_length)
	var spread_prob: float = SPREAD_CHANCE_PER_DAY * (FOREST_SPREAD_INTERVAL / DAY_LENGTH)
	var revert_prob: float = REVERT_CHANCE_PER_DAY * (FOREST_SPREAD_INTERVAL / DAY_LENGTH)
	var succession_prob: float = SUCCESSION_CHANCE_PER_DAY * (FOREST_SPREAD_INTERVAL / DAY_LENGTH)

	var dirs: Array = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]

	for z in range(World.WORLD_HEIGHT):
		for x in range(World.WORLD_WIDTH):
			var tile: Dictionary = world.get_tile(x, z)
			if tile.is_empty():
				continue
			var tile_type: int = int(tile.get("type", -1))

			# --- FOREST, and grown WOODLAND (at half the rate), seed the GRASS
			# next to them: it becomes WOODLAND, starting as seedlings ---
			var seeds_out: bool = tile_type == World.TileType.FOREST or (tile_type == World.TileType.WOODLAND \
				and float(tile.get("growth", 1.0)) >= 0.8 and not bool(tile.get("tree_cut", false)))
			if seeds_out:
				var p_seed: float = spread_prob if tile_type == World.TileType.FOREST else spread_prob * 0.5
				for d in dirs:
					var nx: int = x + d.x
					var nz: int = z + d.y
					if nx < 0 or nx >= World.WORLD_WIDTH or nz < 0 or nz >= World.WORLD_HEIGHT:
						continue
					var ntile: Dictionary = world.get_tile(nx, nz)
					if ntile.is_empty():
						continue
					if int(ntile.get("type", -1)) == World.TileType.GRASS and float(ntile.get("burnt", 0.0)) <= 0.0:
						if randf() < p_seed:
							# Seeded from the wood next door: it starts as seedlings.
							ntile["type"] = World.TileType.WOODLAND
							ntile["growth"] = 0.0
							ntile["tree_cut"] = false
							world.mark_tile_dirty(nx, nz)
							world.mark_flora_dirty(nx, nz)
							if bool(ntile.get("burnt_once", false)) and not _told_return and history_log:
								_told_return = true
								return_pos = Vector2(nx + 0.5, nz + 0.5)
								history_log.add("ecology", "Seedlings are coming up where the woods burned.", day)
							if randf() < HERB_SPAWN_CHANCE:
								ntile["herbs"] = 1.0

			# --- A lone WOODLAND tile (no woods at all beside it) fades back to
			# GRASS; WOODLAND beside FOREST slowly turns to forest ---
			if tile_type == World.TileType.WOODLAND:
				var has_forest_neighbour: bool = false
				var has_woods_neighbour: bool = false
				for d in dirs:
					var nx: int = x + d.x
					var nz: int = z + d.y
					if nx < 0 or nx >= World.WORLD_WIDTH or nz < 0 or nz >= World.WORLD_HEIGHT:
						continue
					var ntile: Dictionary = world.get_tile(nx, nz)
					if ntile.is_empty():
						continue
					var nt := int(ntile.get("type", -1))
					if nt == World.TileType.FOREST:
						has_forest_neighbour = true
					if nt == World.TileType.FOREST or nt == World.TileType.WOODLAND:
						has_woods_neighbour = true
				if not has_woods_neighbour:
					# Planted groves are tended; only wild ones fade back to grass.
					if randf() < revert_prob and not bool(tile.get("planted", false)):
						tile["type"] = World.TileType.GRASS
						tile["growth"] = -1.0
						world.mark_tile_dirty(x, z)
						world.mark_flora_dirty(x, z)
				elif has_forest_neighbour and float(tile.get("growth", 1.0)) >= 0.95 and not bool(tile.get("tree_cut", false)) \
						and randf() < succession_prob:
					# Grown woodland beside forest: pines come up through it.
					tile["type"] = World.TileType.FOREST
					tile["growth"] = 0.5
					tile["tree_age"] = 0.0
					world.mark_tile_dirty(x, z)
					world.mark_flora_dirty(x, z)

# ── Overgrazing ───────────────────────────────────────────────────────────────

func _do_overgraze_check(agents: Array, world: World, day: int, history_log: HistoryLog) -> void:
	# Count live agents on each GRASS tile (within 0.5 tile of centre).
	var counts: Dictionary = {}  # "x,z" → int

	for agent in agents:
		var a: Agent = agent as Agent
		if a == null or a.is_dead:
			continue
		var tx: int = int(a.pos.x)
		var tz: int = int(a.pos.y)
		var tile: Dictionary = world.get_tile(tx, tz)
		if tile.is_empty() or int(tile.get("type", -1)) != World.TileType.GRASS:
			continue
		# Check agent is within 0.5 tiles of the tile centre.
		var cx: float = float(tx) + 0.5
		var cz: float = float(tz) + 0.5
		if abs(a.pos.x - cx) <= 0.5 and abs(a.pos.y - cz) <= 0.5:
			var key: String = "%d,%d" % [tx, tz]
			counts[key] = int(counts.get(key, 0)) + 1

	# Accumulate overgrazing time and degrade if threshold exceeded.
	for key in counts:
		var agent_count: int = int(counts[key])
		if agent_count > OVERGRAZE_AGENT_THRESH:
			_overgrazing[key] = float(_overgrazing.get(key, 0.0)) + GRAZE_CHECK_INTERVAL
			if float(_overgrazing.get(key, 0.0)) >= OVERGRAZE_TIME_THRESH:
				var parts: PackedStringArray = key.split(",")
				var tx: int = int(parts[0])
				var tz: int = int(parts[1])
				var tile: Dictionary = world.get_tile(tx, tz)
				if not tile.is_empty() and int(tile.get("type", -1)) == World.TileType.GRASS:
					tile["type"] = World.TileType.DESERT
					world.mark_tile_dirty(tx, tz)
					tile["overgrazed"] = true
					tile["overgraze_time"] = 0.0
					_overgrazing.erase(key)
					history_log.add(
						"ecology",
						"Overgrazing has turned a grassland at (%s) to desert" % key,
						day
					)

func _tick_overgraze_decay(delta: float, world: World, day: int, history_log: HistoryLog) -> void:
	# Decay overgrazing counter for empty tiles.
	var keys_og: Array = _overgrazing.keys()
	for key in keys_og:
		var parts: PackedStringArray = key.split(",")
		var tx: int = int(parts[0])
		var tz: int = int(parts[1])
		var tile: Dictionary = world.get_tile(tx, tz)
		if tile.is_empty():
			_overgrazing.erase(key)
			continue
		# Tile is no longer GRASS (already degraded or changed).
		if int(tile.get("type", -1)) != World.TileType.GRASS:
			_overgrazing.erase(key)
			continue
		var current: float = float(_overgrazing.get(key, 0.0))
		current = maxf(0.0, current - OVERGRAZE_DECAY * delta)
		if current <= 0.0:
			_overgrazing.erase(key)
		else:
			_overgrazing[key] = current

	# Recovery of overgrazed DESERT tiles.
	var dd := delta * float(STRIPE_COUNT)
	var dstart := _desert_stripe
	_desert_stripe = (_desert_stripe + 1) % STRIPE_COUNT
	for z in range(dstart, world.height, STRIPE_COUNT):
		for x in range(world.width):
			var tile: Dictionary = world.tiles[z][x]
			if int(tile.get("type", -1)) != World.TileType.DESERT:
				continue
			if not bool(tile.get("overgrazed", false)):
				continue
			var ot: float = float(tile.get("overgraze_time", 0.0)) + dd
			tile["overgraze_time"] = ot
			if ot >= OVERGRAZE_RECOVER_TIME:
				tile["type"] = World.TileType.GRASS
				tile.erase("overgrazed")
				tile.erase("overgraze_time")
				world.mark_tile_dirty(x, z)
				history_log.add(
					"ecology",
					"An overgrazed desert at (%d, %d) has recovered to grassland" % [x, z],
					day
				)

# ── Soil quality ──────────────────────────────────────────────────────────────

func _tick_soil(delta: float, world: World) -> void:
	var d := delta * float(STRIPE_COUNT)
	var start := _soil_stripe
	_soil_stripe = (_soil_stripe + 1) % STRIPE_COUNT
	for z in range(start, world.height, STRIPE_COUNT):
		for x in range(world.width):
			var tile: Dictionary = world.tiles[z][x]
			var tile_type: int = int(tile.get("type", -1))

			if tile_type == World.TileType.FOREST:
				# Slow regeneration toward 1.0.
				var sq: float = float(tile.get("soil_quality", 1.0))
				tile["soil_quality"] = minf(1.0, sq + SOIL_REGEN_FOREST * d)

			elif tile_type == World.TileType.GRASS:
				# Post-fire tiles have elevated soil_quality; continue improving.
				var sq: float = float(tile.get("soil_quality", 1.0))
				if sq < 1.0:
					tile["soil_quality"] = minf(1.0, sq + SOIL_REGEN_BURNOUT * d)
