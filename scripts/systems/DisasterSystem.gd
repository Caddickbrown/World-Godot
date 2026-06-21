class_name DisasterSystem
extends RefCounted

enum DisasterType { NONE = 0, DROUGHT = 1, FLOOD = 2, BLIGHT = 3 }

# Game-seconds per in-game day (matches TimeSystem.DAY_LENGTH = 120.0).
const DAY_LENGTH_SEC := 120.0

const DURATION_DROUGHT := 60.0 * DAY_LENGTH_SEC  # 7200 s
const DURATION_FLOOD   := 30.0 * DAY_LENGTH_SEC  # 3600 s
const DURATION_BLIGHT  := 45.0 * DAY_LENGTH_SEC  # 5400 s

const DAILY_CHANCE := 0.05

var current: int = DisasterType.NONE
var remaining_time: float = 0.0
var _last_check_day: int = 0

# ── Computed properties ───────────────────────────────────────────────────────

var label: String:
	get:
		match current:
			DisasterType.DROUGHT: return "Drought"
			DisasterType.FLOOD:   return "Flood"
			DisasterType.BLIGHT:  return "Blight"
		return "None"

# ── Query helpers ─────────────────────────────────────────────────────────────

func get_gather_mult() -> float:
	if current == DisasterType.DROUGHT:
		return 0.5
	return 1.0

func is_flooded() -> bool:
	return current == DisasterType.FLOOD

func get_spoilage_mult() -> float:
	if current == DisasterType.BLIGHT:
		return 5.0
	return 1.0

# ── Main tick ─────────────────────────────────────────────────────────────────

func tick(delta: float, day: int, history_log: HistoryLog) -> void:
	# Daily activation roll (only when no disaster is active).
	if day != _last_check_day:
		_last_check_day = day
		if current == DisasterType.NONE:
			if randf() < DAILY_CHANCE:
				_activate(_pick_random_disaster(), day, history_log)

	# Count down the active disaster.
	if current != DisasterType.NONE:
		remaining_time -= delta
		if remaining_time <= 0.0:
			_end(day, history_log)

# ── Internal helpers ──────────────────────────────────────────────────────────

func _pick_random_disaster() -> int:
	var roll: int = randi() % 3
	match roll:
		0: return DisasterType.DROUGHT
		1: return DisasterType.FLOOD
		_: return DisasterType.BLIGHT

func _activate(disaster_type: int, day: int, history_log: HistoryLog) -> void:
	current = disaster_type
	match disaster_type:
		DisasterType.DROUGHT: remaining_time = DURATION_DROUGHT
		DisasterType.FLOOD:   remaining_time = DURATION_FLOOD
		DisasterType.BLIGHT:  remaining_time = DURATION_BLIGHT

	var msg: String = _start_message(disaster_type)
	history_log.add("disaster", msg, day)

func _end(day: int, history_log: HistoryLog) -> void:
	var msg: String = _end_message(current)
	history_log.add("disaster", msg, day)
	current = DisasterType.NONE
	remaining_time = 0.0

func _start_message(disaster_type: int) -> String:
	match disaster_type:
		DisasterType.DROUGHT: return "A great drought has begun"
		DisasterType.FLOOD:   return "A great flood has begun"
		DisasterType.BLIGHT:  return "A terrible blight has spread across the land"
	return "A disaster has begun"

func _end_message(disaster_type: int) -> String:
	match disaster_type:
		DisasterType.DROUGHT: return "The drought has ended"
		DisasterType.FLOOD:   return "The flood has receded"
		DisasterType.BLIGHT:  return "The blight has passed"
	return "The disaster has ended"
