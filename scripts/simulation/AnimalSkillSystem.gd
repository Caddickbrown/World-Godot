class_name AnimalSkillSystem
extends RefCounted

# ---------------------------------------------------------------------------
# Storage: "type:id" → { "foraging": float, "escape": float, "camouflage": float }
# ---------------------------------------------------------------------------

var _skills: Dictionary = {}

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _key(animal_type: int, anim_id: int) -> String:
	return "%d:%d" % [animal_type, anim_id]


func _ensure(key: String) -> void:
	if not _skills.has(key):
		_skills[key] = { "foraging": 0.0, "escape": 0.0, "camouflage": 0.0 }

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Returns the skill dict for this animal, initialising to 0.0 if absent.
func get_skills(animal_type: int, anim_id: int) -> Dictionary:
	var key: String = _key(animal_type, anim_id)
	_ensure(key)
	return _skills[key] as Dictionary


## Call when an animal successfully forages; raises foraging skill.
func on_successful_forage(animal_type: int, anim_id: int) -> void:
	var key: String = _key(animal_type, anim_id)
	_ensure(key)
	var d: Dictionary = _skills[key] as Dictionary
	d["foraging"] = minf(float(d.get("foraging", 0.0)) + 0.005, 1.0)


## Call when an animal successfully escapes a threat; raises escape skill.
func on_successful_escape(animal_type: int, anim_id: int) -> void:
	var key: String = _key(animal_type, anim_id)
	_ensure(key)
	var d: Dictionary = _skills[key] as Dictionary
	d["escape"] = minf(float(d.get("escape", 0.0)) + 0.005, 1.0)


## Apply slow passive gain to every tracked animal each frame.
func tick_passive(delta: float) -> void:
	for key in _skills.keys():
		var d: Dictionary = _skills[key] as Dictionary
		d["foraging"]   = minf(float(d.get("foraging",   0.0)) + 0.001 * delta, 1.0)
		d["escape"]     = minf(float(d.get("escape",     0.0)) + 0.001 * delta, 1.0)
		d["camouflage"] = minf(float(d.get("camouflage", 0.0)) + 0.001 * delta, 1.0)


## Returns a speed multiplier based on escape skill: 1.0 – 1.5.
func get_escape_speed_mult(animal_type: int, anim_id: int) -> float:
	var d: Dictionary = get_skills(animal_type, anim_id)
	return 1.0 + float(d.get("escape", 0.0)) * 0.5


## Returns a forage yield multiplier based on foraging skill: 1.0 – 1.3.
func get_forage_mult(animal_type: int, anim_id: int) -> float:
	var d: Dictionary = get_skills(animal_type, anim_id)
	return 1.0 + float(d.get("foraging", 0.0)) * 0.3


## Remove skill data for a dead animal.
func clear_animal(animal_type: int, anim_id: int) -> void:
	var key: String = _key(animal_type, anim_id)
	_skills.erase(key)


## Wipe all skill data.
func clear() -> void:
	_skills.clear()
