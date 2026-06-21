class_name WeatherSystem

enum WeatherType { CLEAR, CLOUDY, RAIN, STORM }

var current: int = WeatherType.CLEAR
var _timer: float = 0.0
var _total_time: float = 0.0
var temperature: float = 20.0

var label: String:
	get:
		match current:
			WeatherType.CLEAR:  return "Clear"
			WeatherType.CLOUDY: return "Cloudy"
			WeatherType.RAIN:   return "Rain"
			WeatherType.STORM:  return "Storm"
		return "Clear"

var temp_label: String:
	get: return "%.0f°C" % temperature

var is_raining: bool:
	get: return current == WeatherType.RAIN or current == WeatherType.STORM

var is_storm: bool:
	get: return current == WeatherType.STORM

func update(delta: float, season: String) -> bool:
	_total_time += delta
	_timer -= delta
	if _timer > 0.0:
		return false

	_timer = 30.0 + randf() * 60.0

	# Season affects weather probabilities
	var storm_chance := 0.05
	var rain_chance  := 0.20
	var cloudy_chance := 0.30
	match season:
		"Winter":
			storm_chance = 0.10
			rain_chance  = 0.35
			temperature = lerpf(temperature, -5.0, 0.1)
		"Spring":
			rain_chance = 0.30
			temperature = lerpf(temperature, 15.0, 0.1)
		"Summer":
			storm_chance = 0.08
			rain_chance  = 0.10
			temperature = lerpf(temperature, 28.0, 0.1)
		"Autumn":
			rain_chance = 0.25
			temperature = lerpf(temperature, 10.0, 0.1)

	var prev := current
	var roll := randf()
	if roll < storm_chance:
		current = WeatherType.STORM
	elif roll < storm_chance + rain_chance:
		current = WeatherType.RAIN
	elif roll < storm_chance + rain_chance + cloudy_chance:
		current = WeatherType.CLOUDY
	else:
		current = WeatherType.CLEAR

	return current != prev

func energy_drain_mult_at(_x: float, _z: float) -> float:
	match current:
		WeatherType.STORM: return 1.8
		WeatherType.RAIN:  return 1.3
		WeatherType.CLOUDY: return 1.1
	return 1.0

func get_tide_level() -> float:
	return sin((_total_time / 900.0) * PI * 2.0)
