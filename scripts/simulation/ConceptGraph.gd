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
## Lost ideas and their ghosts (IdeaMemory): who was the last, and where.
var memory := IdeaMemory.new()

func _init(concepts_data: Array) -> void:
	for c in concepts_data:
		concepts[c["id"]] = c
		known_by[c["id"]] = []
		_index[c["id"]] = _ids.size()
		_ids.append(c["id"])

# ── Discovery ────────────────────────────────────────────────────────────────

func check_discovery(agent: Agent, tile: Dictionary, delta: float, world: World, all_agents: Array, current_day: int = 0) -> String:
	# One roll a person a frame, not one an idea. Every idea's chance is tiny
	# (about 1e-4 a second), so the frame's odds are their sum: rolled once
	# against an upper bound (each idea at the most its fire or ghost bonus
	# could make it), then, on the rare hit, an idea picked in proportion and
	# kept with the odds its bonus really has here. The same odds as rolling
	# each idea (to first order: the chances are tiny), at a fraction of the
	# cost: 83 rolls a person a frame were a third of a frame at 20x.
	# Then, as before, the conditions (the costly part) only on a hit.
	var base: float = agent.curiosity * delta * discovery_pace * agent.fxf("discovery_bonus")
	if agent.knowledge.has("curiosity_culture"): base *= 1.2
	if agent.task == "scout": base *= 1.15
	if base <= 0.0:
		return ""
	var key: int = agent.knowledge.size() * 65536 + memory.version
	var m = _mass.get(agent.agent_id)
	if m == null or int(m[0]) != key:
		var total := 0.0
		for id in concepts:
			if not agent.knowledge.has(id):
				total += float(concepts[id].get("discovery_probability", 0.0001)) * _upper(id)
		m = [key, total]
		_mass[agent.agent_id] = m
	var mass: float = m[1]
	if mass * base > 0.05:
		# Not small (a test, a fast-forward): one roll an idea, exactly.
		return _discover_each(agent, tile, base, world, all_agents, current_day)
	if mass <= 0.0 or randf() >= mass * base:
		return ""
	# Which idea: in proportion to its (upper) share.
	var pick := randf() * mass
	var id := ""
	for cid in concepts:
		if agent.knowledge.has(cid):
			continue
		pick -= float(concepts[cid].get("discovery_probability", 0.0001)) * _upper(cid)
		if pick < 0.0:
			id = cid
			break
	if id == "":
		return ""
	# Kept with the odds its bonus really has here.
	var actual := memory.bonus(id, agent.pos)
	if id == "fire" and _near_wildfire(tile, world):
		actual *= FIRE_NEAR_WILDFIRE
	if randf() >= actual / _upper(id):
		return ""
	var concept: Dictionary = concepts[id]
	if not _prerequisites_met(agent, concept): return ""
	if not _conditions_met(agent, tile, concept, world, all_agents): return ""
	if IdeaMemory.reinvent < 1.0 and IdeaMemory.is_master_craft(id) and randf() >= IdeaMemory.reinvent \
			and memory.held_by_living(id, all_agents): return ""
	if known_by[id].is_empty():
		concept["first_discoverer"] = {"name": agent.agent_name, "id": agent.agent_id, "day": current_day}
	memory.note_refound(id, agent, current_day)
	_grant(agent, id, current_day)
	events.append({"type": "discovery", "agent_id": agent.agent_id, "agent_name": agent.agent_name, "concept_id": id})
	return id

## The plain way: every idea rolled on its own (used when the odds aren't
## small, where one roll for the lot would saturate).
func _discover_each(agent: Agent, tile: Dictionary, base: float, world: World, all_agents: Array, current_day: int) -> String:
	var fire_near := _near_wildfire(tile, world)
	for id in concepts:
		if agent.knowledge.has(id):
			continue
		var concept: Dictionary = concepts[id]
		var prob: float = float(concept.get("discovery_probability", 0.0001)) * base * memory.bonus(id, agent.pos)
		if id == "fire" and fire_near:
			prob *= FIRE_NEAR_WILDFIRE
		if randf() >= prob: continue
		if not _prerequisites_met(agent, concept): continue
		if not _conditions_met(agent, tile, concept, world, all_agents): continue
		if IdeaMemory.reinvent < 1.0 and IdeaMemory.is_master_craft(id) and randf() >= IdeaMemory.reinvent \
				and memory.held_by_living(id, all_agents): continue
		if known_by[id].is_empty():
			concept["first_discoverer"] = {"name": agent.agent_name, "id": agent.agent_id, "day": current_day}
		memory.note_refound(id, agent, current_day)
		_grant(agent, id, current_day)
		events.append({"type": "discovery", "agent_id": agent.agent_id, "agent_name": agent.agent_name, "concept_id": id})
		return id
	return ""

## Fire is 30x likelier beside a wildfire.
const FIRE_NEAR_WILDFIRE := 30.0
## agent id -> [key, sum of ideas' upper odds] (see check_discovery).
var _mass: Dictionary = {}

## The most an idea's odds can be multiplied by anywhere: by a wildfire
## (fire) and by its ghost (a lost idea, near where it was last known).
func _upper(id: String) -> float:
	var u := FIRE_NEAR_WILDFIRE if id == "fire" else 1.0
	if memory.ghosts.has(id):
		u *= maxf(1.0, IdeaMemory.ghost_bonus)
	return u

func _near_wildfire(tile: Dictionary, world: World) -> bool:
	if world.natural_fires.is_empty() or tile.is_empty():
		return false
	for d in [[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1]]:
		if world.natural_fires.has("%d,%d" % [int(tile["x"]) + d[0], int(tile["z"]) + d[1]]):
			return true
	return false

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
				if (world.tile_value(tile, str(value)) if world else float(tile.get(str(value), -1.0))) <= 0.0: return false
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

## Who knows what, as bits (an idea's index in _ids): two ints of 63.
var _ids: Array = []              # index -> idea id
var _index: Dictionary = {}       # idea id -> index
var _masks: Dictionary = {}       # agent id -> [knowledge size, lo bits, hi bits]

## A person's ideas as bits, rebuilt when they know more (knowledge only grows).
func _mask(a: Agent) -> Array:
	var m = _masks.get(a.agent_id)
	if m != null and int(m[0]) == a.knowledge.size():
		return m
	var lo := 0
	var hi := 0
	for id in a.knowledge:
		var i: int = _index.get(id, -1)
		if i < 0:
			continue
		if i < 63:
			lo |= 1 << i
		else:
			hi |= 1 << (i - 63)
	m = [a.knowledge.size(), lo, hi]
	_masks[a.agent_id] = m
	return m

## Two people near each other may pass on what one knows and the other
## doesn't. Only those ideas are looked at (the bits that differ), in the
## same order as ever, so the same dice fall: neighbours by a fire mostly
## know the same things, and checking all 83 for every pair was a third of
## the people's time.
func try_spread(agent_a: Agent, agent_b: Agent, delta_time: float = 5.0) -> void:
	var ma := _mask(agent_a)
	var mb := _mask(agent_b)
	var x0: int = int(ma[1]) ^ int(mb[1])
	var x1: int = int(ma[2]) ^ int(mb[2])
	if x0 == 0 and x1 == 0:
		return
	for i in _ids.size():
		if i < 63:
			if (x0 >> i) & 1 == 0:
				continue
		elif (x1 >> (i - 63)) & 1 == 0:
			continue
		var id: String = _ids[i]
		var concept: Dictionary = concepts[id]
		var a_knows: bool = agent_a.knowledge.has(id)
		var b_knows: bool = agent_b.knowledge.has(id)
		if a_knows == b_knows: continue

		var learner: Agent = agent_b if a_knows else agent_a
		var teacher: Agent = agent_a if a_knows else agent_b

		var craft := int(concept.get("era", 1)) >= 2
		if craft and (not teacher.is_adult or learner.life_stage == "infant"):
			continue
		# A master craft: an apprentice learns it from one master, over days.
		var master := IdeaMemory.is_master_craft(id)
		if master and memory.is_learning(learner, id):
			if memory.finished(learner, teacher, id):
				_grant(learner, id)
				events.append({"type": "spread", "agent_id": learner.agent_id, "agent_name": learner.agent_name,
					"concept_id": id, "teacher_id": teacher.agent_id})
			continue
		if master and not memory.may_take(teacher, id):
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
			if master:
				memory.begin(teacher, learner, id)
				continue
			_grant(learner, id)
			events.append({"type": "spread", "agent_id": learner.agent_id, "agent_name": learner.agent_name,
				"concept_id": id, "teacher_id": teacher.agent_id})

## Main tells the graph of each death: an idea nobody alive holds any more is
## lost (IdeaMemory leaves its ghost). Returns the ids lost.
func note_death(dead: Agent, agents: Array, day: int, home: Vector2 = Vector2(-1, -1)) -> Array:
	var lost := memory.note_death(dead, agents, day, home)
	for id in lost:
		events.append({"type": "lost", "agent_id": dead.agent_id, "agent_name": dead.agent_name, "concept_id": id})
	return lost

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
## Kept by id, not the Agent: an Agent holds this graph, so holding the
## Agent back made a cycle that was never freed.
var deeds: Array = []              # [{key, text, id, pos}]
var _deeds_done: Dictionary = {}

func note_deed(key: String, text: String, who) -> void:
	if _deeds_done.has(key):
		return
	_deeds_done[key] = true
	deeds.append({"key": key, "text": text, "id": int(who.agent_id), "pos": who.pos})

func drain_deeds() -> Array:
	var out := deeds
	deeds = []
	return out
