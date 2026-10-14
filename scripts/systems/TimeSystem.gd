class_name TimeSystem

const DAY_LENGTH := 120.0  # real game-seconds per in-game day

var game_time: float = (8.0 / 24.0) * DAY_LENGTH  # start at 08:00
var speed: float = 1.0

var day: int:
	get: return int(floor(game_time / DAY_LENGTH)) + 1

var time_of_day: float:
	get: return fmod(game_time / DAY_LENGTH, 1.0)

var hour: float:
	get: return time_of_day * 24.0

## Seasons last SEASON_DAYS in-game days and a world starts in spring, so a
## sitting sees the year turn (a 365-day year meant a 12-hour winter first).
const SEASON_DAYS := 7
const SEASONS: Array[String] = ["Spring", "Summer", "Autumn", "Winter"]

var season: String:
	get: return season_for_day(day)

static func season_for_day(d: int) -> String:
	return SEASONS[int((d - 1) / SEASON_DAYS) % SEASONS.size()]

# Returns game-seconds elapsed (scaled by speed)
func update(real_delta: float) -> float:
	var game_delta := real_delta * speed
	game_time += game_delta
	return game_delta

func set_speed(s: float) -> void:
	speed = s

func is_night() -> bool:
	return hour >= 20.0 or hour < 6.0

func is_dawn() -> bool:
	return hour >= 6.0 and hour < 8.0

func is_dusk() -> bool:
	return hour >= 18.0 and hour < 20.0
