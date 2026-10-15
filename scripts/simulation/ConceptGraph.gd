class_name ConceptGraph

var concepts: Dictionary = {}   # id → concept dict
var known_by: Dictionary = {}   # id → Array of agent ids
var events: Array = []          # consumed by Main each frame
var birth_events: Array = []    # { x, z, parent_name, parent_a_id, parent_b_id, ... }

## World pacing. With the data's raw rates, 57 of 82 ideas were found by day 12
## and writing on day 3, so a world's story was spent in half an hour, and no
## idea was ever lost because everything spread too fast for anyone to die the
## last holder. Measured with tools/balance.gd; see the commit that set them.
## Re-measured after the double-ticked-newborn fix (which had been doubling
## every child's chances): discovery barely moves the result, because a
## discovery needs its prerequisites held by that one person; spreading is
## the real gate.
static var discovery_pace := 0.6
static var spread_pace := 0.9
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
			"has_knowledge", "has_concept":
				if not agent.knowledge.has(value): return false
			"inventory_item":
				if not agent.inventory.has(value): return false
			# These used to fall through unmatched, so the idea could be found
			# anywhere (sailing far inland, stone tools never, see near_tile).
			"adjacent_to":
				if not _type_within(world, tile, value, 1): return false
			"near_tile":
				if not _type_within(world, tile, value, NEAR_TILES): return false
			"tile_has_resource":
				if float(tile.get(str(value), -1.0)) <= 0.0: return false
			"near_bee_hive":
				# Real nests (AmbientLife); a world without them falls back
				# to "bees live in the woods".
				var hive := AmbientLife.hive_near(world, tile, float(value))
				if hive == 0: return false
				if hive < 0 and not _type_within(world, tile, ["WOODLAND", "FOREST"], int(value)): return false
	return true

const NEAR_TILES := 3

## Is a tile of this type (a name, or a list of names) within r tiles? WATER
## counts deep water too.
static func _type_within(world: World, tile: Dictionary, value: Variant, r: int) -> bool:
	if world == null or tile.is_empty():
		return true
	var want: Array = value if value is Array else [value]
	var types: Dictionary = {}
	for name in want:
		types[World.TileType.get(str(name), -1)] = true
		if str(name) == "WATER":
			types[World.TileType.DEEP_WATER] = true
	var cx := int(tile["x"])
	var cz := int(tile["z"])
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var t := world.get_tile(cx + dx, cz + dz)
			if not t.is_empty() and types.has(int(t["type"])):
				return true
	return false

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
		# How well this teacher passes ideas on (language, writing, printing,
		# temple, law...) and how ready this learner is to take them up (oral
		# tradition): ConceptEffects, from what each knows.
		spread_rate *= teacher.fxf("spread_rate_multiplier") * learner.fxf("concept_spread_rate_mult")
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

# ── Deeds ────────────────────────────────────────────────────────────────────
## Firsts people do (the first boat, the first climb, the first cooked meal),
## told once per world. Agents note them; Main passes them to the story.
var deeds: Array = []              # [{key, text, who}]
var _deeds_done: Dictionary = {}

func note_deed(key: String, text: String, who) -> void:
	if _deeds_done.has(key):
		return
	_deeds_done[key] = true
	deeds.append({"key": key, "text": text, "who": who})

func drain_deeds() -> Array:
	var out := deeds
	deeds = []
	return out
