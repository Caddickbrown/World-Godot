class_name AnimalSkillSystem
extends RefCounted
## What an animal learns in its life. Wired (AnimalSim): every escape from a
## predator, a hunter or a stooping eagle raises "escape", and a wary animal
## notices people and predators from further off (up to 1.5x) and runs faster
## (up to 1.25x), so old survivors are the hard ones to catch. Foraging and
## camouflage are kept but read by nothing: an animal eating better would
## change nothing anyone could watch (see docs/features/animals.md).

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


## Escape skill without creating an entry (cheap enough to ask every tick).
func escape_of(animal_type: int, anim_id: int) -> float:
	var d = _skills.get(_key(animal_type, anim_id))
	return float(d.get("escape", 0.0)) if d != null else 0.0


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
	d["escape"] = minf(float(d.get("escape", 0.0)) + ESCAPE_GAIN, 1.0)


## Skill per escape: about a dozen narrow escapes make a deer as wary as it gets.
const ESCAPE_GAIN := 0.08

## Passive gain. It used to add 0.001/s to everything, so every animal maxed
## every skill by day 8 whatever happened to it; skill now comes from what
## an animal lived through. Kept as a no-op for callers (Main ticks it).
func tick_passive(_delta: float) -> void:
	pass


## Returns a speed multiplier based on escape skill: 1.0 – 1.25.
func get_escape_speed_mult(animal_type: int, anim_id: int) -> float:
	var d: Dictionary = get_skills(animal_type, anim_id)
	return 1.0 + float(d.get("escape", 0.0)) * 0.25


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
