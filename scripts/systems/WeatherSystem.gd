class_name WeatherSystem

# ── Weather state enum (mirrors JS WEATHER_META keys) ─────────────────────────
enum WeatherType { CLEAR, CLOUDY, RAIN, STORM }

const ZONES := 4  # zone grid is ZONES x ZONES (default 4x4 = 16 zones)

# Severity order for blending / "dominant zone" selection (higher = worse).
const SEVERITY := {
	WeatherType.CLEAR:  0,
	WeatherType.CLOUDY: 1,
	WeatherType.RAIN:   2,
	WeatherType.STORM:  3,
}

# Season -> per-state sampling weights.
const SEASON_WEIGHTS := {
	"Spring": { WeatherType.CLEAR: 3.0, WeatherType.CLOUDY: 2.0, WeatherType.RAIN: 3.0, WeatherType.STORM: 1.0 },
	"Summer": { WeatherType.CLEAR: 5.0, WeatherType.CLOUDY: 2.0, WeatherType.RAIN: 1.0, WeatherType.STORM: 0.0 },
	"Autumn": { WeatherType.CLEAR: 2.0, WeatherType.CLOUDY: 3.0, WeatherType.RAIN: 3.0, WeatherType.STORM: 2.0 },
	"Winter": { WeatherType.CLEAR: 1.0, WeatherType.CLOUDY: 2.0, WeatherType.RAIN: 2.0, WeatherType.STORM: 4.0 },
}

# Base temperature (°C) per season.
const SEASON_TEMP := { "Spring": 13.0, "Summer": 24.0, "Autumn": 9.0, "Winter": -5.0 }
# Temperature offset per weather state.
const WEATHER_TEMP := {
	WeatherType.CLEAR:  4.0,
	WeatherType.CLOUDY: 0.0,
	WeatherType.RAIN:   -4.0,
	WeatherType.STORM:  -10.0,
}
# Energy drain multiplier per weather state.
const WEATHER_ENERGY_MULT := {
	WeatherType.CLEAR:  1.00,
	WeatherType.CLOUDY: 1.05,
	WeatherType.RAIN:   1.30,
	WeatherType.STORM:  1.70,
}
const WEATHER_LABELS := {
	WeatherType.CLEAR:  "Clear",
	WeatherType.CLOUDY: "Cloudy",
	WeatherType.RAIN:   "Rain",
	WeatherType.STORM:  "Storm",
}

# 8-connected neighbour offsets used for spatial correlation when a zone re-samples.
const _NEIGHBOUR_DIRS := [
	Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
	Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1),
]

class Zone:
	var state: int = WeatherType.CLEAR
	var timer: float = 0.0
	var duration: float = 50.0

var _world_width: int
var _world_height: int
var _zones: Array = []  # Array[Array[Zone]] — [row][col], row-major (row = z-axis, col = x-axis)

var _season: String = "Spring"
var _total_time: float = 0.0

# Dominant (most-severe) zone state, kept for the legacy global API.
var current: int = WeatherType.CLEAR

# Rainbows: a zone whose rain clears by day (sun up, 07:00-18:00) shows one
# for RAINBOW_SECONDS. rainbow is true while any zone has one; rainbow_zone
# is the newest, rainbow_strength its fade (0..1, in and out).
const RAINBOW_SECONDS := 36.0           # game-seconds (~7 in-game hours at 1x)
const RAINBOW_HOURS := Vector2(7.0, 18.0)
## How grey the sky is under each state (what SkyLook eases toward).
const OVERCAST := {
	WeatherType.CLEAR: 0.0, WeatherType.CLOUDY: 0.3, WeatherType.RAIN: 0.6, WeatherType.STORM: 1.0,
}
var rainbow: bool = false
var _rainbow_timer: float = 0.0
var rainbow_zone := Vector2i(-1, -1)    # (row, col)
var rainbows_started := 0

# ── Legacy / global accessors (dominant zone) ─────────────────────────────────

var label: String:
	get: return WEATHER_LABELS.get(current, "Clear")

var temperature: float:
	get: return SEASON_TEMP.get(_season, 13.0) + WEATHER_TEMP.get(current, 0.0)

var temp_label: String:
	get: return "%.0f°C" % temperature

var is_raining: bool:
	get: return current == WeatherType.RAIN or current == WeatherType.STORM

var is_storm: bool:
	get: return current == WeatherType.STORM

var energy_drain_mult: float:
	get: return WEATHER_ENERGY_MULT.get(current, 1.0)


func _init(world_width: int = World.WORLD_WIDTH, world_height: int = World.WORLD_HEIGHT) -> void:
	_world_width = maxi(1, world_width)
	_world_height = maxi(1, world_height)

	_zones.resize(ZONES)
	for r in range(ZONES):
		var row: Array = []
		row.resize(ZONES)
		for c in range(ZONES):
			var zone := Zone.new()
			# Stagger initial timers so zones don't all resample in lockstep.
			zone.timer = float(r * ZONES + c) * (50.0 / float(ZONES * ZONES))
			row[c] = zone
		_zones[r] = row

# ── Zone helpers ────────────────────────────────────────────────────────────

## Convert world tile coords to zone row/col (row = z-axis, col = x-axis).
func _zone_of(x: float, z: float) -> Vector2i:
	var c: int = clampi(int(floor(x / float(_world_width) * float(ZONES))), 0, ZONES - 1)
	var r: int = clampi(int(floor(z / float(_world_height) * float(ZONES))), 0, ZONES - 1)
	return Vector2i(r, c)

## Sample a new weather state weighted by season + neighbour pressure.
func _sample_state(season: String, r: int, c: int) -> int:
	var base_weights: Dictionary = SEASON_WEIGHTS.get(season, SEASON_WEIGHTS["Spring"])
	var weights: Dictionary = base_weights.duplicate()

	for d in _NEIGHBOUR_DIRS:
		var nr: int = r + d.x
		var nc: int = c + d.y
		if nr < 0 or nr >= ZONES or nc < 0 or nc >= ZONES:
			continue
		var n_state: int = (_zones[nr][nc] as Zone).state
		weights[n_state] = float(weights.get(n_state, 0.0)) + 1.5

	var total: float = 0.0
	for v in weights.values():
		total += float(v)

	var rand: float = randf() * total
	for key in weights.keys():
		rand -= float(weights[key])
		if rand <= 0.0:
			return int(key)
	return WeatherType.CLEAR

# ── Public API ────────────────────────────────────────────────────────────────

## Update all zone timers. Call once per game tick with game-time delta.
## `world` is optional; when omitted no world-scan lightning logic runs (the
## project's FireSystem already owns lightning-strike-on-forest behaviour
## driven off `is_storm`, so WeatherSystem does not duplicate a world scan
## here). Returns true if the dominant (global) weather state changed.
func update(delta: float, season: String, _world: World = null, hour: float = -1.0) -> bool:
	_season = season
	_total_time += delta

	var dominant: int = WeatherType.CLEAR
	for r in range(ZONES):
		for c in range(ZONES):
			var zone: Zone = _zones[r][c]
			zone.timer += delta
			if zone.timer >= zone.duration:
				zone.timer = 0.0
				zone.duration = 25.0 + randf() * 55.0
				var was: int = zone.state
				zone.state = _sample_state(season, r, c)
				if _wet(was) and not _wet(zone.state):
					_maybe_rainbow(Vector2i(r, c), hour)
			if SEVERITY[zone.state] > SEVERITY[dominant]:
				dominant = zone.state

	var prev_dominant := current
	current = dominant

	if rainbow:
		_rainbow_timer -= delta
		if _rainbow_timer <= 0.0:
			rainbow = false
			_rainbow_timer = 0.0
			rainbow_zone = Vector2i(-1, -1)

	return current != prev_dominant

static func _wet(state: int) -> bool:
	return state == WeatherType.RAIN or state == WeatherType.STORM

## The rain over a zone has just cleared: a rainbow, if the sun is up to make one.
func _maybe_rainbow(rc: Vector2i, hour: float) -> void:
	if hour >= 0.0 and (hour < RAINBOW_HOURS.x or hour > RAINBOW_HOURS.y):
		return
	rainbow = true
	_rainbow_timer = RAINBOW_SECONDS
	rainbow_zone = rc
	rainbows_started += 1

## Fade of the current rainbow: up over its first tenth, down over its last third.
var rainbow_strength: float:
	get:
		if not rainbow:
			return 0.0
		var age := RAINBOW_SECONDS - _rainbow_timer
		return clampf(age / (RAINBOW_SECONDS * 0.1), 0.0, 1.0) * clampf(_rainbow_timer / (RAINBOW_SECONDS * 0.33), 0.0, 1.0)

## Tile-space centre of a zone (row, col).
func zone_centre(rc: Vector2i) -> Vector2:
	return Vector2((rc.y + 0.5) * float(_world_width) / ZONES, (rc.x + 0.5) * float(_world_height) / ZONES)

## Where the rainbow stands (tile coords), or (-1, -1).
func rainbow_pos() -> Vector2:
	return zone_centre(rainbow_zone) if rainbow else Vector2(-1, -1)

## Force a rainbow over the zone at a tile (captures, tests).
func force_rainbow(x: float, z: float) -> void:
	_maybe_rainbow(_zone_of(x, z), -1.0)

func zone_state(r: int, c: int) -> int:
	return (_zones[clampi(r, 0, ZONES - 1)][clampi(c, 0, ZONES - 1)] as Zone).state

func set_zone_state(r: int, c: int, state: int) -> void:
	(_zones[r][c] as Zone).state = state

## How overcast the sky looks at a tile: the zones round it blended by
## distance from their centres, so panning across a front eases the grey in.
func overcast_at(x: float, z: float) -> float:
	var fx := x / float(_world_width) * ZONES - 0.5
	var fz := z / float(_world_height) * ZONES - 0.5
	var c0 := floori(fx)
	var r0 := floori(fz)
	var tx := clampf(fx - c0, 0.0, 1.0)
	var tz := clampf(fz - r0, 0.0, 1.0)
	# Hold the zone you're in at full weight over its middle half.
	tx = smoothstep(0.25, 0.75, tx)
	tz = smoothstep(0.25, 0.75, tz)
	var a: float = OVERCAST[zone_state(r0, c0)]
	var b: float = OVERCAST[zone_state(r0, c0 + 1)]
	var c: float = OVERCAST[zone_state(r0 + 1, c0)]
	var d: float = OVERCAST[zone_state(r0 + 1, c0 + 1)]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)

func label_at(x: float, z: float) -> String:
	return WEATHER_LABELS.get(get_weather_at(x, z), "Clear")

func temperature_at(x: float, z: float) -> float:
	return SEASON_TEMP.get(_season, 13.0) + WEATHER_TEMP.get(get_weather_at(x, z), 0.0)

## Return the WeatherType for a given world position (O(1) zone lookup).
func get_weather_at(x: float, z: float) -> int:
	var rc := _zone_of(x, z)
	return (_zones[rc.x][rc.y] as Zone).state

## Return a small metadata dict (label, energy_mult) for the weather at a position.
func get_meta_at(x: float, z: float) -> Dictionary:
	var state: int = get_weather_at(x, z)
	return {
		"label": WEATHER_LABELS.get(state, "Clear"),
		"energy_mult": WEATHER_ENERGY_MULT.get(state, 1.0),
	}

## True if it is raining (or storming) at the given position.
func is_raining_at(x: float, z: float) -> bool:
	var state: int = get_weather_at(x, z)
	return state == WeatherType.RAIN or state == WeatherType.STORM

## True if a storm is active at the given position.
func is_storm_at(x: float, z: float) -> bool:
	return get_weather_at(x, z) == WeatherType.STORM

## Energy drain multiplier for an agent at (x, z). O(1) — called every agent, every frame.
func energy_drain_mult_at(x: float, z: float) -> float:
	return WEATHER_ENERGY_MULT.get(get_weather_at(x, z), 1.0)

func get_tide_level() -> float:
	return sin((_total_time / 900.0) * PI * 2.0)
