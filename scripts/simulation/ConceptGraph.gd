class_name ConceptGraph

var concepts: Dictionary = {}   # id → concept dict
var known_by: Dictionary = {}   # id → Array of agent ids
var events: Array = []          # consumed by Main each frame
var birth_events: Array = []    # { x, z, parent_name, parent_a_id, parent_b_id, ... }

## World pacing. With the data's raw rates, 57 of 82 ideas were found by day 12
## and writing on day 3, so a world's story was spent in half an hour, and no
## idea was ever lost because everything spread too fast for anyone to die the
## last holder. Measured with tools/balance.gd; see the commit that set them.
static var discovery_pace := 0.35
static var spread_pace := 0.45
## Crafts (era 2 and later) have to be taught: only an adult can pass one on,
## infants can't take one up, and they spread more slowly than ideas anyone
## can copy by watching. That makes them fragile: a craft held by a few can
## die with them. Children learn fastest from their own parents.
static var craft_pace := 0.4
const PARENT_TEACHING := 2.0

func _init(concepts_data: Array) -> void:
	for c in concepts_data:
		concepts[c["id"]] = c
		known_by[c["id"]] = []

# ── Discovery ────────────────────────────────────────────────────────────────

func check_discovery(agent: Agent, tile: Dictionary, delta: float, world: World, all_agents: Array, current_day: int = 0) -> String:
	for id in concepts:
		var concept: Dictionary = concepts[id]
		if agent.knowledge.has(id): continue
		if not _prerequisites_met(agent, concept): continue
		if not _conditions_met(agent, tile, concept, world, all_agents): continue

		var prob: float = float(concept.get("discovery_probability", 0.0001)) * agent.curiosity * delta * discovery_pace
		if agent.knowledge.has("curiosity_culture"): prob *= 1.2
		if agent.task == "scout": prob *= 1.15

		if id == "fire" and not world.natural_fires.is_empty():
			var adj := [[0,0],[1,0],[-1,0],[0,1],[0,-1]]
			for d in adj:
				var key := "%d,%d" % [tile["x"] + d[0], tile["z"] + d[1]]
				if world.natural_fires.has(key):
					prob *= 30.0
					break

		if randf() < prob:
			if known_by[id].is_empty():
				concept["first_discoverer"] = {"name": agent.agent_name, "id": agent.agent_id, "day": current_day}
			_grant(agent, id, current_day)
			events.append({"type": "discovery", "agent_id": agent.agent_id, "agent_name": agent.agent_name, "concept_id": id})
			return id
	return ""

func _prerequisites_met(agent: Agent, concept: Dictionary) -> bool:
	for prereq in concept.get("prerequisites", []):
		if not agent.knowledge.has(prereq): return false
	return true

func _conditions_met(agent: Agent, tile: Dictionary, concept: Dictionary, world: World, all_agents: Array) -> bool:
	for cond in concept.get("discovery_conditions", []):
		var ctype: String = cond.get("type", "")
		var value: Variant = cond.get("value", "")
		match ctype:
			"tile_type":
				if World.TileType.keys()[tile.get("type", 0)] != value and \
				   tile.get("type", 0) != _tile_type_from_string(value):
					return false
			"population_nearby":
				var count := 0
				for other in all_agents:
					if other == agent: continue
					if other.health <= 0: continue
					if abs(other.pos.x - agent.pos.x) + abs(other.pos.y - agent.pos.y) < 5.0:
						count += 1
				if count < int(value): return false
			"has_knowledge":
				if not agent.knowledge.has(value): return false
			"inventory_item":
				if not agent.inventory.has(value): return false
	return true

func _tile_type_from_string(s: String) -> int:
	return World.TileType.get(s, -1)

func _grant(agent: Agent, id: String, _day: int = 0) -> void:
	agent.knowledge[id] = true
	if not known_by.has(id):
		known_by[id] = []
	if not agent.agent_id in known_by[id]:
		known_by[id].append(agent.agent_id)

# ── Spreading ────────────────────────────────────────────────────────────────

func try_spread(agent_a: Agent, agent_b: Agent, delta_time: float = 5.0) -> void:
	for id in concepts:
		var concept: Dictionary = concepts[id]
		var a_knows: bool = agent_a.knowledge.has(id)
		var b_knows: bool = agent_b.knowledge.has(id)
		if a_knows == b_knows: continue

		var learner: Agent = agent_b if a_knows else agent_a
		var teacher: Agent = agent_a if a_knows else agent_b

		var craft := int(concept.get("era", 1)) >= 2
		if craft and (not teacher.is_adult or learner.life_stage == "infant"):
			continue
		var spread_rate: float = float(concept.get("spread_rate", 0.01)) * delta_time * spread_pace
		if craft:
			spread_rate *= craft_pace
		if learner.agent_id in teacher.children:
			spread_rate *= PARENT_TEACHING
		if teacher.knowledge.has("language"): spread_rate *= 2.0
		if teacher.knowledge.has("writing"):  spread_rate *= 1.5
		if teacher.task == "teacher":         spread_rate *= 1.1

		if randf() < spread_rate:
			_grant(learner, id)
			events.append({"type": "spread", "agent_id": learner.agent_id, "agent_name": learner.agent_name,
				"concept_id": id, "teacher_id": teacher.agent_id})

# ── Queries ──────────────────────────────────────────────────────────────────

func drain_events() -> Array:
	var out := events.duplicate()
	events.clear()
	return out

func drain_birth_events() -> Array:
	var out := birth_events.duplicate()
	birth_events.clear()
	return out

func get_discovered_concepts() -> Array:
	var out: Array = []
	for id in known_by:
		if not known_by[id].is_empty():
			var c: Dictionary = concepts.get(id, {})
			out.append({"id": id, "name": c.get("name", id), "icon": c.get("icon", ""),
				"known_count": known_by[id].size()})
	return out
