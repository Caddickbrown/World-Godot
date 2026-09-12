class_name LineageTracker
extends RefCounted

## Records which agent first discovered each concept, and on what day, so the
## UI can render a chronological discovery timeline. Works alongside
## ConceptGraph's own first-discoverer bookkeeping but provides a standalone
## queryable store.

# concept_id (String) → { "concept_id": String, "name": String, "id": int, "day": int }
var _discoveries: Dictionary = {}


## Records a first discovery. Ignores duplicates — only the first call for a
## given concept_id is stored.
func record(concept_id: String, agent: Agent, day: int) -> void:
	if _discoveries.has(concept_id):
		return
	_discoveries[concept_id] = {
		"concept_id": concept_id,
		"name": agent.agent_name,
		"id": agent.agent_id,
		"day": day,
	}


## Returns the discoverer entry for a concept, or an empty Dictionary if none
## has been recorded yet.
func get_discoverer(concept_id: String) -> Dictionary:
	return _discoveries.get(concept_id, {})


## Returns all discovery entries sorted by day ascending, for a timeline view.
func all_discoveries() -> Array:
	var result: Array = _discoveries.values()
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["day"]) < int(b["day"]))
	return result


func clear() -> void:
	_discoveries.clear()
