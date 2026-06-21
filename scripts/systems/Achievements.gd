class_name Achievements
extends RefCounted

const ACHIEVEMENTS: Dictionary = {
	"prometheus": { "name": "The Gift of Fire", "description": "Discover fire" },
	"survivor": { "name": "Survivor", "description": "Reach day 100" },
	"community": { "name": "Community", "description": "Reach a population of 25" },
	"elder": { "name": "Elder", "description": "An agent lives to old age" },
	"polymath": { "name": "Polymath", "description": "An agent learns 10 concepts" },
	"well_fed": { "name": "Well Fed", "description": "All agents are well fed at once" },
}

var unlocked: Dictionary = {}
var _checks_done: Dictionary = {}


func tick(agents: Array, concept_graph: ConceptGraph, day: int) -> Array:
	var newly_unlocked: Array = []

	# prometheus — first agent discovers fire concept
	if not bool(_checks_done.get("prometheus", false)):
		var discovered: Array = concept_graph.get_discovered_concepts()
		for concept: Dictionary in discovered:
			var concept_name: String = String(concept.get("name", ""))
			if concept_name.to_lower() == "fire":
				newly_unlocked.append(_unlock("prometheus", day))
				break

	# survivor — civilisation survives to day 100
	if not bool(_checks_done.get("survivor", false)):
		if day >= 100:
			newly_unlocked.append(_unlock("survivor", day))

	# community — population reaches 25 alive at once
	if not bool(_checks_done.get("community", false)):
		var alive_count: int = 0
		for agent: Agent in agents:
			if not agent.is_dead:
				alive_count += 1
		if alive_count >= 25:
			newly_unlocked.append(_unlock("community", day))

	# elder — any agent reaches 95% of their life_expectancy
	if not bool(_checks_done.get("elder", false)):
		for agent: Agent in agents:
			if agent.life_expectancy > 0.0 and agent.age >= agent.life_expectancy * 0.95:
				newly_unlocked.append(_unlock("elder", day))
				break

	# polymath — any agent knows 10+ concepts
	if not bool(_checks_done.get("polymath", false)):
		for agent: Agent in agents:
			if agent.knowledge.size() >= 10:
				newly_unlocked.append(_unlock("polymath", day))
				break

	# well_fed — all alive agents have hunger > 0.8 at the same time
	if not bool(_checks_done.get("well_fed", false)):
		var alive_agents: Array = []
		for agent: Agent in agents:
			if not agent.is_dead:
				alive_agents.append(agent)
		if alive_agents.size() > 0:
			var all_fed: bool = true
			for agent: Agent in alive_agents:
				var hunger: float = float(agent.needs.get("hunger", 0.0))
				if hunger <= 0.8:
					all_fed = false
					break
			if all_fed:
				newly_unlocked.append(_unlock("well_fed", day))

	# Filter out empty dicts (already-unlocked achievements return {} from _unlock)
	var result: Array = []
	for item in newly_unlocked:
		if not item.is_empty():
			result.append(item)
	return result


func _unlock(id: String, day: int) -> Dictionary:
	if bool(_checks_done.get(id, false)):
		return {}
	_checks_done[id] = true
	var data: Dictionary = ACHIEVEMENTS[id] as Dictionary
	var entry: Dictionary = {
		"id": id,
		"name": String(data.get("name", "")),
		"description": String(data.get("description", "")),
		"day": day,
	}
	unlocked[id] = { "name": String(data.get("name", "")), "day": day }
	return entry


func is_unlocked(id: String) -> bool:
	return unlocked.has(id)


func get_unlocked_list() -> Array:
	var result: Array = []
	for id: String in unlocked.keys():
		var entry: Dictionary = unlocked[id] as Dictionary
		var data: Dictionary = ACHIEVEMENTS[id] as Dictionary
		result.append({
			"id": id,
			"name": String(entry.get("name", "")),
			"description": String(data.get("description", "")),
			"day": int(entry.get("day", 0)),
		})
	return result
