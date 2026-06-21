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
const SPREAD_CHANCE_PER_DAY    := 0.02
const REVERT_CHANCE_PER_DAY    := 0.002

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

func tick(delta: float, world: World, agents: Array, day: int, history_log: HistoryLog) -> void:
	_forest_timer += delta
	if _forest_timer >= FOREST_SPREAD_INTERVAL:
		_forest_timer -= FOREST_SPREAD_INTERVAL
		_do_forest_spread(world)

	_graze_timer += delta
	if _graze_timer >= GRAZE_CHECK_INTERVAL:
		_graze_timer -= GRAZE_CHECK_INTERVAL
		_do_overgraze_check(agents, world, day, history_log)

	_tick_soil(delta, world)
	_tick_overgraze_decay(delta, world, day, history_log)

# ── Forest spread ─────────────────────────────────────────────────────────────

func _do_forest_spread(world: World) -> void:
	# Convert seconds-elapsed to a per-tick probability.
	# P(event in interval) = 1 - (1-daily_chance)^(interval/day_length)
	# For small daily chances: approx = daily_chance * (interval / day_length)
	var spread_prob: float = SPREAD_CHANCE_PER_DAY * (FOREST_SPREAD_INTERVAL / DAY_LENGTH)
	var revert_prob: float = REVERT_CHANCE_PER_DAY * (FOREST_SPREAD_INTERVAL / DAY_LENGTH)

	var dirs: Array = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]

	for z in range(World.WORLD_HEIGHT):
		for x in range(World.WORLD_WIDTH):
			var tile: Dictionary = world.get_tile(x, z)
			if tile.is_empty():
				continue
			var tile_type: int = int(tile.get("type", -1))

			# --- FOREST spreads into adjacent GRASS → WOODLAND ---
			if tile_type == World.TileType.FOREST:
				for d in dirs:
					var nx: int = x + d.x
					var nz: int = z + d.y
					if nx < 0 or nx >= World.WORLD_WIDTH or nz < 0 or nz >= World.WORLD_HEIGHT:
						continue
					var ntile: Dictionary = world.get_tile(nx, nz)
					if ntile.is_empty():
						continue
					if int(ntile.get("type", -1)) == World.TileType.GRASS:
						if randf() < spread_prob:
							ntile["type"] = World.TileType.WOODLAND
							if randf() < HERB_SPAWN_CHANCE:
								ntile["herbs"] = 1.0

			# --- Isolated WOODLAND reverts to GRASS ---
			elif tile_type == World.TileType.WOODLAND:
				var has_forest_neighbour: bool = false
				for d in dirs:
					var nx: int = x + d.x
					var nz: int = z + d.y
					if nx < 0 or nx >= World.WORLD_WIDTH or nz < 0 or nz >= World.WORLD_HEIGHT:
						continue
					var ntile: Dictionary = world.get_tile(nx, nz)
					if not ntile.is_empty() and int(ntile.get("type", -1)) == World.TileType.FOREST:
						has_forest_neighbour = true
						break
				if not has_forest_neighbour:
					if randf() < revert_prob:
						tile["type"] = World.TileType.GRASS

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
	for z in range(World.WORLD_HEIGHT):
		for x in range(World.WORLD_WIDTH):
			var tile: Dictionary = world.get_tile(x, z)
			if tile.is_empty():
				continue
			if int(tile.get("type", -1)) != World.TileType.DESERT:
				continue
			if not bool(tile.get("overgrazed", false)):
				continue
			var ot: float = float(tile.get("overgraze_time", 0.0)) + delta
			tile["overgraze_time"] = ot
			if ot >= OVERGRAZE_RECOVER_TIME:
				tile["type"] = World.TileType.GRASS
				tile.erase("overgrazed")
				tile.erase("overgraze_time")
				history_log.add(
					"ecology",
					"An overgrazed desert at (%d, %d) has recovered to grassland" % [x, z],
					day
				)

# ── Soil quality ──────────────────────────────────────────────────────────────

func _tick_soil(delta: float, world: World) -> void:
	for z in range(World.WORLD_HEIGHT):
		for x in range(World.WORLD_WIDTH):
			var tile: Dictionary = world.get_tile(x, z)
			if tile.is_empty():
				continue
			var tile_type: int = int(tile.get("type", -1))

			if tile_type == World.TileType.FOREST:
				# Slow regeneration toward 1.0.
				var sq: float = float(tile.get("soil_quality", 1.0))
				tile["soil_quality"] = minf(1.0, sq + SOIL_REGEN_FOREST * delta)

			elif tile_type == World.TileType.GRASS:
				# Post-fire tiles have elevated soil_quality; continue improving.
				var sq: float = float(tile.get("soil_quality", 1.0))
				if sq < 1.0:
					tile["soil_quality"] = minf(1.0, sq + SOIL_REGEN_BURNOUT * delta)
