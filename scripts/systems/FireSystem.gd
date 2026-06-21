class_name FireSystem
extends RefCounted

# "x,z" → { "end_time": float, "ignition_time": float }
var _fires: Dictionary = {}
var _spread_timer: float = 0.0

# Set when a lightning strike ignites a fire; cleared at the start of the next tick.
var lightning_fire_pos: Vector2 = Vector2(-1.0, -1.0)

const SPREAD_INTERVAL    := 2.0
const SPREAD_CHANCE      := 0.02   # per adjacent flammable tile per interval
const LIGHTNING_CHANCE   := 0.001  # per second during storms (0.1 %)
const FIRE_BURNOUT_TYPE  := World.TileType.GRASS
const SOIL_QUALITY_BOOST := 0.1

# Tile types that can catch fire or spread fire.
const FLAMMABLE_TYPES: Array = [
	World.TileType.FOREST,
	World.TileType.WOODLAND,
	World.TileType.GRASS,
]

# ── Public API ────────────────────────────────────────────────────────────────

func start_fire(x: int, z: int, duration: float, game_time: float, world: World) -> void:
	var key: String = "%d,%d" % [x, z]
	if _fires.has(key):
		return
	var end_t: float = game_time + duration
	_fires[key] = { "end_time": end_t, "ignition_time": game_time }
	world.natural_fires[key] = { "end_time": end_t }

func is_on_fire(x: int, z: int) -> bool:
	return _fires.has("%d,%d" % [x, z])

func get_fire_count() -> int:
	return _fires.size()

func clear() -> void:
	_fires.clear()

# ── Main tick ─────────────────────────────────────────────────────────────────

func tick(
	delta: float,
	world: World,
	game_time: float,
	is_storm: bool,
	day: int,
	history_log: HistoryLog
) -> void:
	# Clear last frame's lightning marker.
	lightning_fire_pos = Vector2(-1.0, -1.0)

	# Lightning strikes during storms.
	if is_storm:
		if randf() < LIGHTNING_CHANCE * delta:
			_lightning_strike(world, game_time, day, history_log)

	# Fire spread (throttled to every SPREAD_INTERVAL seconds).
	_spread_timer += delta
	if _spread_timer >= SPREAD_INTERVAL:
		_spread_timer -= SPREAD_INTERVAL
		_do_spread(world, game_time)

	# Burnout check — iterate over a snapshot so we can mutate _fires safely.
	var keys: Array = _fires.keys()
	for key in keys:
		var entry: Dictionary = _fires[key]
		var end_time: float = float(entry.get("end_time", 0.0))
		if game_time >= end_time:
			_extinguish(key, world, game_time, day, history_log)

# ── Internal helpers ──────────────────────────────────────────────────────────

func _do_spread(world: World, game_time: float) -> void:
	# Snapshot keys so we don't spread into newly-ignited tiles this frame.
	var snapshot: Array = _fires.keys()
	for key in snapshot:
		var parts: PackedStringArray = key.split(",")
		var fx: int = int(parts[0])
		var fz: int = int(parts[1])

		var neighbours: Array = [[-1, 0], [1, 0], [0, -1], [0, 1]]
		for d in neighbours:
			var nx: int = fx + int(d[0])
			var nz: int = fz + int(d[1])
			if nx < 0 or nx >= World.WORLD_WIDTH or nz < 0 or nz >= World.WORLD_HEIGHT:
				continue
			var nkey: String = "%d,%d" % [nx, nz]
			if _fires.has(nkey):
				continue
			var tile: Dictionary = world.get_tile(nx, nz)
			if tile.is_empty():
				continue
			var tile_type: int = int(tile.get("type", -1))
			if not (tile_type in FLAMMABLE_TYPES):
				continue
			if randf() < SPREAD_CHANCE:
				var duration: float = 30.0 + randf() * 30.0
				start_fire(nx, nz, duration, game_time, world)

func _extinguish(
	key: String,
	world: World,
	_game_time: float,
	_day: int,
	_history_log: HistoryLog
) -> void:
	_fires.erase(key)
	world.natural_fires.erase(key)

	var parts: PackedStringArray = key.split(",")
	var tx: int = int(parts[0])
	var tz: int = int(parts[1])
	var tile: Dictionary = world.get_tile(tx, tz)
	if tile.is_empty():
		return

	# FOREST → GRASS conversion on burnout.
	if int(tile.get("type", -1)) == World.TileType.FOREST:
		tile["type"]     = FIRE_BURNOUT_TYPE
		tile["tree_cut"] = false
		tile["resource"] = 0.2
		tile["tree_age"]   = -1.0
		tile["tree_stage"] = ""

	# Boost soil quality (capped at 1.0).
	var current_soil: float = float(tile.get("soil_quality", 1.0))
	tile["soil_quality"] = minf(1.0, current_soil + SOIL_QUALITY_BOOST)

func _lightning_strike(
	world: World,
	game_time: float,
	day: int,
	history_log: HistoryLog
) -> void:
	var forest_tiles: Array = world.get_tiles_of_type([World.TileType.FOREST])
	if forest_tiles.is_empty():
		return

	var target: Dictionary = forest_tiles[randi() % forest_tiles.size()]
	var lx: int = int(target.get("x", 0))
	var lz: int = int(target.get("z", 0))

	var duration: float = 28.0 + randf() * 18.0
	start_fire(lx, lz, duration, game_time, world)
	lightning_fire_pos = Vector2(float(lx), float(lz))

	history_log.add("fire", "Lightning struck a forest at (%d, %d)" % [lx, lz], day)
