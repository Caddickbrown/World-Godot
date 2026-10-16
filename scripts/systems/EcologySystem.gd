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

# Herb spawn chance when WOODLAND is created.
const HERB_SPAWN_CHANCE        := 0.30

# ── Main tick ─────────────────────────────────────────────────────────────────

# (A soil-quality sweep lived here: a striped pass over every tile's
# Dictionary each frame, for a value nothing read. Removed.)
## Overgrazed desert recovering: tile -> seconds since it turned.
var _recovering: Dictionary = {}

func tick(delta: float, world: World, agents: Array, day: int, history_log: HistoryLog) -> void:
	_forest_timer += delta
	if _forest_timer >= FOREST_SPREAD_INTERVAL:
		_forest_timer -= FOREST_SPREAD_INTERVAL
		_do_forest_spread(world, day, history_log)

	_graze_timer += delta
	if _graze_timer >= GRAZE_CHECK_INTERVAL:
		_graze_timer -= GRAZE_CHECK_INTERVAL
		_do_overgraze_check(agents, world, day, history_log)

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
	# The whole map is rolled from tile types alone (natively when built:
	# 27 ms of Dictionaries before); the rest of each rule is checked here on
	# the few tiles that rolled. Same odds: the roll and the rest are
	# independent. Every hit is checked against the world as it is now, so
	# two woods seeding one meadow make one wood.
	var seed := randi()
	var events: PackedInt32Array
	if World.kernels:
		events = World.kernels.forest_spread(world.layer_type, world.width, seed, spread_prob, revert_prob, succession_prob)
	else:
		events = forest_spread_gd(world.layer_type, world.width, seed, spread_prob, revert_prob, succession_prob)
	var w := world.width
	for k in range(0, events.size(), 3):
		var i: int = events[k + 1]
		var x := i % w
		var z := i / w
		var tile: Dictionary = world.tiles[z][x]
		match events[k]:
			SEED:
				var o: int = events[k + 2]
				var src: Dictionary = world.tiles[o / w][o % w]
				var st := int(src["type"])
				var grown_wood := st == World.TileType.WOODLAND and float(src.get("growth", 1.0)) >= 0.8 \
					and not bool(src.get("tree_cut", false))
				if not (st == World.TileType.FOREST or grown_wood):
					continue
				if int(tile["type"]) != World.TileType.GRASS or float(tile.get("burnt", 0.0)) > 0.0:
					continue
				# Seeded from the wood next door: it starts as seedlings.
				world.set_type(tile, World.TileType.WOODLAND)
				tile["growth"] = 0.0
				tile["tree_cut"] = false
				world.mark_growing(x, z)
				world.mark_tile_dirty(x, z)
				world.mark_flora_dirty(x, z)
				if bool(tile.get("burnt_once", false)) and not _told_return and history_log:
					_told_return = true
					return_pos = Vector2(x + 0.5, z + 0.5)
					history_log.add("ecology", "Seedlings are coming up where the woods burned.", day)
				if randf() < HERB_SPAWN_CHANCE:
					world.set_herbs(tile, 1.0)
			REVERT:
				# A lone wild wood fades back to grass; planted groves are tended.
				if int(tile["type"]) != World.TileType.WOODLAND or bool(tile.get("planted", false)):
					continue
				world.set_type(tile, World.TileType.GRASS)
				tile["growth"] = -1.0
				world.mark_tile_dirty(x, z)
				world.mark_flora_dirty(x, z)
			SUCCEED:
				# Grown woodland beside forest: pines come up through it.
				if int(tile["type"]) != World.TileType.WOODLAND or float(tile.get("growth", 1.0)) < 0.95 \
						or bool(tile.get("tree_cut", false)):
					continue
				world.set_type(tile, World.TileType.FOREST)
				tile["growth"] = 0.5
				world.mark_growing(x, z)
				world.mark_tile_dirty(x, z)
				world.mark_flora_dirty(x, z)

## Forest spread events, as native/world_kernels forest_spread makes them.
const SEED := 0
const REVERT := 1
const SUCCEED := 2

## The GDScript twin of the native forest_spread (the fallback, and what the
## parity test holds it to): [kind, tile, other, ...].
static func forest_spread_gd(types: PackedByteArray, w: int, seed: int, p_spread: float, p_revert: float, p_succeed: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var h := types.size() / w
	var dirs := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
	for z in h:
		for x in w:
			var i := z * w + x
			var ty := types[i]
			if ty != World.TileType.FOREST and ty != World.TileType.WOODLAND:
				continue
			var p := p_spread if ty == World.TileType.FOREST else p_spread * 0.5
			var forest_near := false
			var woods_near := false
			for k in 4:
				var nx: int = x + dirs[k].x
				var nz: int = z + dirs[k].y
				if nx < 0 or nz < 0 or nx >= w or nz >= h:
					continue
				var j := nz * w + nx
				var nt := types[j]
				if nt == World.TileType.GRASS and World.roll(seed, i, k) < p:
					out.append_array([SEED, j, i])
				forest_near = forest_near or nt == World.TileType.FOREST
				woods_near = woods_near or nt == World.TileType.FOREST or nt == World.TileType.WOODLAND
			if ty == World.TileType.WOODLAND:
				if not woods_near:
					if World.roll(seed, i, 4) < p_revert:
						out.append_array([REVERT, i, i])
				elif forest_near and World.roll(seed, i, 5) < p_succeed:
					out.append_array([SUCCEED, i, i])
	return out

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
					world.set_type(tile, World.TileType.DESERT)
					world.mark_tile_dirty(tx, tz)
					_recovering[Vector2i(tx, tz)] = 0.0
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

	# Recovery of overgrazed desert: the few tiles it happened to, not a
	# sweep of the map looking for them.
	for key in _recovering.keys():
		var tile: Dictionary = world.get_tile(key.x, key.y)
		if tile.is_empty() or int(tile["type"]) != World.TileType.DESERT:
			_recovering.erase(key)
			continue
		var ot: float = _recovering[key] + delta
		_recovering[key] = ot
		if ot >= OVERGRAZE_RECOVER_TIME:
			_recovering.erase(key)
			world.set_type(tile, World.TileType.GRASS)
			world.mark_tile_dirty(key.x, key.y)
			history_log.add(
				"ecology",
				"An overgrazed desert at (%d, %d) has recovered to grassland" % [key.x, key.y],
				day
			)
