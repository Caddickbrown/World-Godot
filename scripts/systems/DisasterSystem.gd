class_name DisasterSystem
extends RefCounted
## Droughts, floods and blights: rare, short (a day or three, in a 7-day
## season), and local to part of the island, so they make a story without
## ending one. Each has a place and a strength that rises and falls; while it
## lasts it changes the tiles in its reach, and those changes are what people
## feel and what the land shows:
##   drought  meadows and woods yield less (resource held under a cap that
##            sinks to DROUGHT_CAP at the heart); the ground browns
##   flood    low ground by a river or the shore goes under: no food there,
##            nobody walks it (World.is_walkable / can_traverse; swimmers
##            wade); a water sheet lies over it (DisasterView)
##   blight   crops and woods sicken (resource capped at BLIGHT_CAP), stores
##            spoil faster; the ground and the trees grey
## Tile fields written: "drought" and "blight" (0..1, in steps of 1/STEPS),
## "flooded" (bool). They are removed again when the disaster ends.

enum DisasterType { NONE = 0, DROUGHT = 1, FLOOD = 2, BLIGHT = 3 }

const DAY_LENGTH_SEC := TimeSystem.DAY_LENGTH

const DURATION_DROUGHT := 2.5 * DAY_LENGTH_SEC
const DURATION_FLOOD   := 1.5 * DAY_LENGTH_SEC
const DURATION_BLIGHT  := 2.0 * DAY_LENGTH_SEC
## Fraction of a disaster spent coming on, and going off again.
const RAMP := 0.18

const DAILY_CHANCE := 0.05
const FIRST_DAY := 4                    # nothing in the first days of a world

const DROUGHT_RADIUS := 34.0            # tiles
const FLOOD_RADIUS := 20.0
const BLIGHT_RADIUS := 18.0
const DROUGHT_CAP := 0.45               # resource ceiling at a drought's heart
const BLIGHT_CAP := 0.30
const FLOOD_RISE := 1.6                 # metres the water climbs above the sea at its height
const STEPS := 5.0                      # visual steps of drought / blight (each a chunk repaint)
const APPLY_EVERY := 2.0                # game-seconds between passes over the tiles
const SPOIL_BLIGHT := 2.0

var current: int = DisasterType.NONE
var remaining_time: float = 0.0
var duration: float = 0.0
var centre := Vector2(-1, -1)           # tile coords
var radius := 0.0
var _last_check_day: int = 0
var _apply_timer := 0.0
var _touched: Dictionary = {}           # Vector2i -> true: tiles carrying a field now
var flooded_count := 0
var water_level := 0.0                  # flood: height (metres) the water has reached
var _base_h := 0.0                      # flood: the ground height where it started

# ── Computed properties ───────────────────────────────────────────────────────

var label: String:
	get:
		match current:
			DisasterType.DROUGHT: return "Drought"
			DisasterType.FLOOD:   return "Flood"
			DisasterType.BLIGHT:  return "Blight"
		return "None"

## 0..1: how hard it bites now (rises over the first RAMP, falls over the last).
var intensity: float:
	get:
		if current == DisasterType.NONE or duration <= 0.0:
			return 0.0
		var done := 1.0 - remaining_time / duration
		return clampf(minf(done, 1.0 - done) / RAMP, 0.0, 1.0)

# ── Query helpers ─────────────────────────────────────────────────────────────

## Island-wide yield factor (1 = normal), the mean over the drought's reach;
## per tile see gather_mult_at.
func get_gather_mult() -> float:
	if current == DisasterType.DROUGHT:
		return 1.0 - (1.0 - DROUGHT_CAP) * 0.5 * intensity
	return 1.0

## How much a tile yields now relative to normal (its resource cap).
func gather_mult_at(x: float, z: float) -> float:
	var w := _weight(x, z)
	match current:
		DisasterType.DROUGHT: return 1.0 - (1.0 - DROUGHT_CAP) * w * intensity
		DisasterType.BLIGHT:  return 1.0 - (1.0 - BLIGHT_CAP) * w * intensity
	return 1.0

func is_flooded() -> bool:
	return current == DisasterType.FLOOD and flooded_count > 0

static func is_tile_flooded(tile: Dictionary) -> bool:
	return bool(tile.get("flooded", false))

func get_spoilage_mult() -> float:
	if current == DisasterType.BLIGHT:
		return 1.0 + (SPOIL_BLIGHT - 1.0) * intensity
	return 1.0

## 0..1 reach of the disaster at a tile (soft edge, a little ragged).
func _weight(x: float, z: float) -> float:
	if current == DisasterType.NONE or radius <= 0.0:
		return 0.0
	var d := Vector2(x, z).distance_to(centre) / radius
	var wob := sin(x * 0.31 + z * 0.17) * cos(z * 0.23 - x * 0.11) * 0.12
	return 1.0 - smoothstep(0.55, 1.0, d + wob)

# ── Main tick ─────────────────────────────────────────────────────────────────

## world / agents are optional so old callers still work (then nothing on the
## land changes).
func tick(delta: float, day: int, history_log: HistoryLog, world: World = null, agents: Array = []) -> void:
	# Daily activation roll (only when no disaster is active).
	if day != _last_check_day:
		_last_check_day = day
		if current == DisasterType.NONE and day >= FIRST_DAY:
			if randf() < DAILY_CHANCE:
				start(_pick_random_disaster(), day, history_log, world)

	# Count down the active disaster.
	if current != DisasterType.NONE:
		remaining_time -= delta
		_apply_timer -= delta
		if world and _apply_timer <= 0.0:
			_apply_timer = APPLY_EVERY
			apply(world, agents)
		if remaining_time <= 0.0:
			_end(day, history_log, world)

# ── Internal helpers ──────────────────────────────────────────────────────────

func _pick_random_disaster() -> int:
	var roll: int = randi() % 3
	match roll:
		0: return DisasterType.DROUGHT
		1: return DisasterType.FLOOD
		_: return DisasterType.BLIGHT

## Begin a disaster now (the daily roll, or a capture / test forcing one).
func start(disaster_type: int, day: int, history_log: HistoryLog, world: World = null, at: Vector2 = Vector2(-1, -1)) -> void:
	if current != DisasterType.NONE:
		_clear_fields(world)
	current = disaster_type
	match disaster_type:
		DisasterType.DROUGHT:
			duration = DURATION_DROUGHT
			radius = DROUGHT_RADIUS
		DisasterType.FLOOD:
			duration = DURATION_FLOOD
			radius = FLOOD_RADIUS
		DisasterType.BLIGHT:
			duration = DURATION_BLIGHT
			radius = BLIGHT_RADIUS
	remaining_time = duration
	_apply_timer = 0.0
	centre = at if at.x >= 0.0 else _pick_centre(disaster_type, world)
	# Floods rise from the sea (rivers burst first, being lower): measured from
	# the centre's own ground, a centre at a hill's foot drowned everything
	# below it, forest and all.
	_base_h = 0.0
	water_level = _base_h
	if history_log:
		history_log.add("disaster", _start_message(disaster_type), day)

## Where it strikes: a flood by a river (or failing that low land by the
## shore), a blight among meadows and woods, a drought anywhere on land.
func _pick_centre(disaster_type: int, world: World) -> Vector2:
	if world == null:
		return Vector2(World.WORLD_WIDTH / 2.0, World.WORLD_HEIGHT / 2.0)
	var good: Array = []
	var fallback: Array = []
	for z in range(4, world.height - 4, 3):
		for x in range(4, world.width - 4, 3):
			var t: Dictionary = world.tiles[z][x]
			var tt := int(t["type"])
			if not world.is_walkable(x, z):
				continue
			match disaster_type:
				DisasterType.FLOOD:
					if bool(t.get("river", false)):
						good.append(Vector2(x + 0.5, z + 0.5))
					elif tt == World.TileType.BEACH or tt == World.TileType.GRASS and world.surface_y(x + 0.5, z + 0.5) < 1.2:
						fallback.append(Vector2(x + 0.5, z + 0.5))
				DisasterType.BLIGHT:
					if tt == World.TileType.GRASS or tt == World.TileType.WOODLAND:
						good.append(Vector2(x + 0.5, z + 0.5))
				_:
					if tt == World.TileType.GRASS or tt == World.TileType.WOODLAND or tt == World.TileType.FOREST:
						good.append(Vector2(x + 0.5, z + 0.5))
	var pool := good if not good.is_empty() else fallback
	if pool.is_empty():
		return Vector2(world.width / 2.0, world.height / 2.0)
	return pool[randi() % pool.size()]

## One pass over the tiles in reach: hold yields down, raise or lower the
## water, and write the fields the renderers draw.
func apply(world: World, agents: Array = []) -> void:
	var inten := intensity
	var r := int(ceil(radius))
	var cx := int(centre.x)
	var cz := int(centre.y)
	var occupied := {}
	if current == DisasterType.FLOOD:
		for a in agents:
			if not a.is_dead and a.health > 0.0:
				occupied[Vector2i(int(a.pos.x), int(a.pos.y))] = true
		water_level = _base_h + FLOOD_RISE * inten
	flooded_count = 0
	for z in range(maxi(0, cz - r), mini(world.height, cz + r + 1)):
		for x in range(maxi(0, cx - r), mini(world.width, cx + r + 1)):
			var w := _weight(x + 0.5, z + 0.5)
			var tile: Dictionary = world.tiles[z][x]
			var key := Vector2i(x, z)
			match current:
				DisasterType.DROUGHT:
					_hold(tile, 1.0 - (1.0 - DROUGHT_CAP) * w * inten, [World.TileType.GRASS, World.TileType.WOODLAND, World.TileType.FOREST])
					_set_field(world, tile, key, "drought", w * inten)
				DisasterType.BLIGHT:
					_hold(tile, 1.0 - (1.0 - BLIGHT_CAP) * w * inten, [World.TileType.GRASS, World.TileType.WOODLAND, World.TileType.FOREST])
					_set_field(world, tile, key, "blight", w * inten)
				DisasterType.FLOOD:
					_flood_tile(world, tile, key, w, occupied)

## Keep a tile's food under a ceiling (that is what the gatherer takes home).
static func _hold(tile: Dictionary, cap: float, types: Array) -> void:
	if int(tile["type"]) in types and float(tile.get("resource", 0.0)) > cap:
		tile["resource"] = cap

func _set_field(world: World, tile: Dictionary, key: Vector2i, field: String, v: float) -> void:
	var q := roundf(clampf(v, 0.0, 1.0) * STEPS) / STEPS
	if absf(float(tile.get(field, 0.0)) - q) < 0.001:
		return
	if q <= 0.0:
		tile.erase(field)
		_touched.erase(key)
	else:
		tile[field] = q
		_touched[key] = true
	world.mark_tile_dirty(key.x, key.y)
	world.mark_flora_dirty(key.x, key.y)

## Low land in reach goes under as the water climbs; it never rises over
## someone standing there (they'd be stranded), and it drains as it falls.
func _flood_tile(world: World, tile: Dictionary, key: Vector2i, w: float, occupied: Dictionary) -> void:
	var tt := int(tile["type"])
	var land := tt != World.TileType.WATER and tt != World.TileType.DEEP_WATER and tt != World.TileType.MOUNTAIN \
		and tt != World.TileType.GLACIER and tt != World.TileType.LAVA
	var h := world.surface_y(key.x + 0.5, key.y + 0.5)
	if bool(tile.get("river", false)):
		h -= 0.6   # rivers burst their banks first
	var under := land and w > 0.05 and h < _base_h + (water_level - _base_h) * w
	var was := bool(tile.get("flooded", false))
	if under and not was and occupied.has(key):
		under = false
	if under:
		flooded_count += 1
		tile["resource"] = 0.0
	if under == was:
		return
	if under:
		tile["flooded"] = true
		_touched[key] = true
	else:
		tile.erase("flooded")
		_touched.erase(key)
	world.mark_tile_dirty(key.x, key.y)
	world.mark_flora_dirty(key.x, key.y)

## Tiles under water now (for DisasterView's water sheet).
func flooded_tiles(world: World) -> Array:
	var out: Array = []
	for key in _touched:
		var t := world.get_tile(key.x, key.y)
		if bool(t.get("flooded", false)):
			out.append(key)
	return out

func _clear_fields(world: World) -> void:
	if world:
		for key in _touched:
			var t := world.get_tile(key.x, key.y)
			if t.is_empty():
				continue
			t.erase("drought")
			t.erase("blight")
			t.erase("flooded")
			world.mark_tile_dirty(key.x, key.y)
			world.mark_flora_dirty(key.x, key.y)
	_touched.clear()
	flooded_count = 0
	water_level = 0.0

func _end(day: int, history_log: HistoryLog, world: World = null) -> void:
	if history_log:
		history_log.add("disaster", _end_message(current), day)
	_clear_fields(world)
	current = DisasterType.NONE
	remaining_time = 0.0
	duration = 0.0
	radius = 0.0
	centre = Vector2(-1, -1)

func _start_message(disaster_type: int) -> String:
	match disaster_type:
		DisasterType.DROUGHT: return "A drought has set in; the meadows are browning"
		DisasterType.FLOOD:   return "Floodwater has spread over the low ground"
		DisasterType.BLIGHT:  return "A blight is spreading through the crops and woods"
	return "A disaster has begun"

func _end_message(disaster_type: int) -> String:
	match disaster_type:
		DisasterType.DROUGHT: return "The drought has broken"
		DisasterType.FLOOD:   return "The flood has gone down"
		DisasterType.BLIGHT:  return "The blight has passed"
	return "The disaster has ended"
