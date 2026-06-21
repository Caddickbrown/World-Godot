class_name HistoryLog
extends RefCounted

const MAX_ENTRIES := 200

var entries: Array = []


func add(type: String, msg: String, day: int) -> void:
	var entry: Dictionary = { "type": type, "msg": msg, "day": day }
	entries.append(entry)
	if entries.size() > MAX_ENTRIES:
		entries.pop_front()


func get_recent(count: int) -> Array:
	var start: int = maxi(0, entries.size() - count)
	return entries.slice(start)


func get_by_type(type: String) -> Array:
	var result: Array = []
	for entry: Dictionary in entries:
		var entry_type: String = String(entry.get("type", ""))
		if entry_type == type:
			result.append(entry)
	return result


func clear() -> void:
	entries.clear()


func format_death(agent_name: String, cause: String) -> String:
	match cause:
		"starvation":
			return agent_name + " starved to death"
		"old_age":
			return agent_name + " lived a full life and passed away"
		"disease":
			return agent_name + " succumbed to illness"
		"conflict":
			return agent_name + " fell in conflict"
		_:
			return agent_name + " has died"
