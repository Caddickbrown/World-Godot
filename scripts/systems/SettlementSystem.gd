class_name SettlementSystem
extends RefCounted

# ---------------------------------------------------------------------------
# Settlement inner class
# ---------------------------------------------------------------------------

class Settlement extends RefCounted:
	var id: int = 0
	var name: String = ""
	var centre: Vector2 = Vector2.ZERO
	var member_ids: Array = []       # agent_id ints
	var tier: int = 0                # 0=camp, 1=hamlet, 2=named
	var has_temple: bool = false
	var temple_pos: Vector2 = Vector2.ZERO
	var knowledge_pool: Dictionary = {}  # concept_id → true
	var dialect: float = 0.0             # 0–1, cultural drift
	var food_store: float = 0.0
	var meals_served: int = 0        # times the store fed a hungry member
	var wood_store: float = 0.0
	var last_contact_day: int = 0
	var founding_day: int = 0
	var lean_days: int = 0           # days in a row the land round the hearth was stripped
	var moving_until_day: int = -1   # while moving, members are kept though far from the new hearth
	var moves: int = 0

# ---------------------------------------------------------------------------
# Naming tables
# ---------------------------------------------------------------------------

const HAMLET_ADJECTIVES: Array = [
	"Green", "Dark", "High", "Old", "New", "Cold",
	"Stone", "River", "Oak", "Ash", "Elm", "Iron"
]
const HAMLET_NOUNS: Array = [
	"Vale", "Hill", "Ford", "Wood", "Field", "Heath",
	"Mere", "Moor", "Gate", "Bridge", "Cross", "Keep"
]
const NAMED_PREFIXES: Array = [
	"Ash", "Elm", "Oak", "Thor", "Ald", "Burn",
	"Wick", "Ton", "Ham", "Stow"
]
const NAMED_SUFFIXES: Array = [
	"wick", "ford", "ton", "ham", "ley", "field",
	"gate", "bridge", "haven", "worth"
]

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var settlements: Array = []   # Array of Settlement
var _next_id: int = 0
var _formation_timer: float = 0.0
const FORMATION_INTERVAL: float = 30.0

# Membership, tiers, temples and knowledge pooling each sweep every agent
# against every settlement. None of them need frame resolution — a settlement's
# roster does not meaningfully change 60 times a second — so they run on a
# slower cadence. At a thousand agents this is the difference between ~36k
# checks per frame and ~36k every two seconds.
var _membership_timer: float = 0.0
const MEMBERSHIP_INTERVAL: float = 2.0
const MEMBERSHIP_RADIUS: float = 6.0
## Fewer, bigger camps: a group of FOUNDING_GROUP agents forms one, and never
## within FOUNDING_SPACING tiles of another (was 3 and 6: thirty camps of three).
const FOUNDING_GROUP: int = 4
const FOUNDING_SPACING: float = 12.0
## A camp nobody has lived in for this many days is abandoned.
const ABANDON_DAYS: int = 2
## A hamlet needs writing AND this many people to become a town.
const TOWN_SIZE: int = 10
## Migration: when the land round a hearth stays stripped, the camp moves.
const FOOD_RADIUS := 6
const LEAN_BELOW := 0.3          # average food on the land round the hearth
const LEAN_DAYS_TO_MOVE := 2
const MOVE_MIN := 10.0
const MOVE_MAX := 28.0
var world: World = null          # set by Main; migration needs the land
var _last_eval_day := -1
var _met_pairs: Dictionary = {}     # "lo:hi" settlement ids that have met
var _empty_since: Dictionary = {}   # settlement id -> day it emptied

# Tracks which agent_ids were in each settlement last tick (for join/leave logic)
var _prev_members: Dictionary = {}  # settlement id → Array of agent_id

# agent_id → Settlement. get_settlement_for_agent() is called per agent from
# several systems every tick; without this it is a scan over every settlement's
# member list, which is quadratic in population.
var _settlement_by_agent: Dictionary = {}

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func tick(delta: float, agents: Array, concept_graph: ConceptGraph, day: int, history_log: HistoryLog,
		  spatial_grid = null) -> void:
	# 1. Formation check every 30 s
	_formation_timer += delta
	if _formation_timer >= FORMATION_INTERVAL:
		_formation_timer = 0.0
		_check_formation(agents, day, history_log)

	# 2-5. Roster-scale work, on a slower cadence than the frame.
	_membership_timer += delta
	if _membership_timer >= MEMBERSHIP_INTERVAL:
		_membership_timer = 0.0
		_update_membership(agents, spatial_grid)
		_reindex_members()
		_check_tier_upgrades(agents, history_log, day)
		_check_temple(agents)
		_sync_knowledge_pool(agents, concept_graph)

	# 6. Resource stores
	_tick_resources(delta, agents, history_log, day)

	# 7. Cultural drift
	_tick_dialect(delta, day)

	# 8. Inter-settlement contact
	_tick_inter_contact(day, history_log)
	# 9. Abandon camps nobody lives in any more
	_abandon_empty(day, history_log)
	# 10. Once a day, camps on stripped land move to better ground
	if day != _last_eval_day:
		_last_eval_day = day
		_check_migration(day, history_log)


func get_settlement_for_agent(agent_id: int) -> RefCounted:
	return _settlement_by_agent.get(agent_id, null)

# Rebuilds the agent → settlement index. Called whenever membership changes.
func _reindex_members() -> void:
	_settlement_by_agent.clear()
	for s: Settlement in settlements:
		for id in s.member_ids:
			_settlement_by_agent[int(id)] = s


func get_settlements() -> Array:
	return settlements


func clear() -> void:
	settlements.clear()
	_prev_members.clear()
	_settlement_by_agent.clear()
	_next_id = 0
	_formation_timer = 0.0

# ---------------------------------------------------------------------------
# Formation
# ---------------------------------------------------------------------------

func _check_formation(agents: Array, day: int, history_log: HistoryLog) -> void:
	# Build a list of agents not already in a settlement
	var free_agents: Array = []
	for a: Agent in agents:
		if a.is_dead:
			continue
		if get_settlement_for_agent(a.agent_id) == null:
			free_agents.append(a)

	# Find groups of 3+ within 4 tiles of each other
	var used: Dictionary = {}
	for i: int in range(free_agents.size()):
		if used.has(i):
			continue
		var group: Array = [free_agents[i]]
		for j: int in range(i + 1, free_agents.size()):
			if used.has(j):
				continue
			var a_i: Agent = free_agents[i]
			var a_j: Agent = free_agents[j]
			if a_i.pos.distance_to(a_j.pos) <= 4.0:
				group.append(free_agents[j])
				used[j] = true
		if group.size() < FOUNDING_GROUP:
			continue
		# Check no existing settlement centre within 6 tiles
		var centroid: Vector2 = _find_centroid_agents(group)
		var too_close: bool = false
		for s: Settlement in settlements:
			if s.centre.distance_to(centroid) <= FOUNDING_SPACING:
				too_close = true
				break
		if too_close:
			continue
		# Create new settlement
		_create_settlement(group, centroid, day, history_log)
		used[i] = true


func _create_settlement(group: Array, centroid: Vector2, day: int, history_log: HistoryLog) -> void:
	var s: Settlement = Settlement.new()
	s.id = _next_id
	_next_id += 1
	s.centre = centroid
	s.founding_day = day
	s.last_contact_day = day
	for a: Agent in group:
		s.member_ids.append(a.agent_id)
	s.tier = 0
	s.name = _unique_name()
	settlements.append(s)
	_prev_members[s.id] = s.member_ids.duplicate()
	history_log.add("settlement", "New camp founded at (%.1f, %.1f) with %d members: '%s'." % [centroid.x, centroid.y, group.size(), s.name], day)

# ---------------------------------------------------------------------------
# Membership
# ---------------------------------------------------------------------------

func _update_membership(agents: Array, spatial_grid = null) -> void:
	for s: Settlement in settlements:
		if s.moving_until_day >= 0:
			# On the move: keep who they are until most have reached the new
			# hearth (or two days pass), or a night's sleep would orphan them.
			var arrived := 0
			for entry in agents:
				var m := entry as Agent
				if m and m.agent_id in s.member_ids and not m.is_dead and m.pos.distance_to(s.centre) <= MEMBERSHIP_RADIUS:
					arrived += 1
			if arrived * 2 < s.member_ids.size() and _last_eval_day < s.moving_until_day:
				continue
			s.moving_until_day = -1
		var new_members: Array = []
		if spatial_grid != null:
			# Only agents near the settlement centre can be members, so ask the
			# grid rather than testing the whole population per settlement.
			for entry in spatial_grid.get_nearby_agents(s.centre, MEMBERSHIP_RADIUS):
				var a := entry as Agent
				if a != null and not a.is_dead:
					new_members.append(a.agent_id)
		else:
			for a: Agent in agents:
				if a.is_dead:
					continue
				if a.pos.distance_to(s.centre) <= MEMBERSHIP_RADIUS:
					new_members.append(a.agent_id)
		s.member_ids = new_members

# ---------------------------------------------------------------------------
# Tier upgrades
# ---------------------------------------------------------------------------

const HAMLET_TIMBER := 12.0   # three felled trees
const TOWN_TIMBER := 30.0

func _check_tier_upgrades(agents: Array, history_log: HistoryLog, day: int) -> void:
	for s: Settlement in settlements:
		# Names stick: a place keeps the name it was founded with as it grows.
		# Huts and houses are built of timber (ForestSystem fells it), so a
		# camp stays tents until it has felled enough.
		if s.tier == 0 and s.member_ids.size() >= 5 and s.wood_store >= HAMLET_TIMBER:
			s.tier = 1
			s.wood_store -= HAMLET_TIMBER
			history_log.add("settlement", "Camp has grown into hamlet '%s'." % s.name, day)
		elif s.tier == 1 and s.member_ids.size() >= TOWN_SIZE and s.wood_store >= TOWN_TIMBER:
			var any_writing: bool = _any_member_knows(s, agents, "writing")
			if any_writing:
				s.tier = 2
				s.wood_store -= TOWN_TIMBER
				history_log.add("settlement", "Hamlet elevated to named settlement '%s'." % s.name, day)

func _any_member_knows(s: Settlement, agents: Array, concept_id: String) -> bool:
	for a: Agent in agents:
		if s.member_ids.has(a.agent_id) and a.knowledge.has(concept_id):
			return true
	return false

# ---------------------------------------------------------------------------
# Temple
# ---------------------------------------------------------------------------

func _check_temple(agents: Array) -> void:
	for s: Settlement in settlements:
		if s.has_temple:
			continue
		var count: int = 0
		for a: Agent in agents:
			if not s.member_ids.has(a.agent_id):
				continue
			if a.knowledge.has("animism") or a.knowledge.has("ritual"):
				count += 1
		if count >= 3:
			s.has_temple = true
			s.temple_pos = s.centre + Vector2(1.5, 1.5)

# ---------------------------------------------------------------------------
# Knowledge pool
# ---------------------------------------------------------------------------

func _sync_knowledge_pool(agents: Array, concept_graph: ConceptGraph) -> void:
	for s: Settlement in settlements:
		var prev: Array = []
		if _prev_members.has(s.id):
			prev = _prev_members[s.id] as Array

		var current_set: Dictionary = {}
		for mid: int in s.member_ids:
			current_set[mid] = true

		var prev_set: Dictionary = {}
		for mid: int in prev:
			prev_set[mid] = true

		# Agents who just joined — contribute knowledge to pool
		for a: Agent in agents:
			if current_set.has(a.agent_id) and not prev_set.has(a.agent_id):
				for k in a.knowledge.keys():
					var concept_key: String = str(k)
					s.knowledge_pool[concept_key] = true

		# Agents who just left — may learn one concept from pool
		for a: Agent in agents:
			if prev_set.has(a.agent_id) and not current_set.has(a.agent_id):
				if s.knowledge_pool.is_empty():
					continue
				if randf() < 0.2:
					var pool_keys: Array = s.knowledge_pool.keys()
					var chosen: String = str(pool_keys[randi() % pool_keys.size()])
					# Only from someone still there to show them: the pool outlives
					# its holders, and learning from it brought lost ideas back
					# unseen (feat/ideas).
					if not a.is_dead and not a.knowledge.has(chosen) and _member_holds(s, chosen, agents):
						if concept_graph: concept_graph._grant(a, chosen)
						else: a.knowledge[chosen] = true

		# Contributing all current members' knowledge to pool each tick
		for a: Agent in agents:
			if current_set.has(a.agent_id):
				for k in a.knowledge.keys():
					s.knowledge_pool[str(k)] = true

		_prev_members[s.id] = s.member_ids.duplicate()
	_reindex_members()

# ---------------------------------------------------------------------------
# Resources
# ---------------------------------------------------------------------------

## The larder. It used to fill itself from nothing and was never eaten.
## Now it holds what members carry home beyond their own fill, feeds members
## who come home hungry, and spoils: in about two days, or eight once the camp
## knows fermentation (or salting/pottery, if those are ever thought of).
const DEADWOOD_PER_MEMBER := 0.0015   # per second: a five-person camp gathers a hut's worth in ~13 days
const STORE_RADIUS := 6.0          # tiles from the hearth to drop off or eat from the store
const STORE_PER_MEMBER := 2.0      # cap
const STORE_HUNGRY_BELOW := 0.3
const STORE_MEAL := 0.4
const SPOIL_DAYS := 2.0
const SPOIL_DAYS_PRESERVED := 8.0
const PRESERVING := ["fermentation", "pottery", "salting"]

var _larder_told := false   # the chronicle tells of the first larder once per world

func _tick_resources(delta: float, agents: Array = [], history_log: HistoryLog = null, day: int = 0) -> void:
	var by_id: Dictionary = {}
	for a in agents:
		by_id[a.agent_id] = a
	for s: Settlement in settlements:
		var cap: float = float(s.member_ids.size()) * STORE_PER_MEMBER * float(ConceptEffects.settlement_fx(s)["store_bonus"])   # barn, mathematics
		# Fallen branches: a trickle anyone can pick up. Felling is the real supply.
		s.wood_store = minf(s.wood_store + float(s.member_ids.size()) * DEADWOOD_PER_MEMBER * delta, float(s.member_ids.size()) * 100.0)
		for id in s.member_ids:
			var a = by_id.get(id)
			if a == null or a.is_dead or a.pos.distance_to(s.centre) > STORE_RADIUS:
				continue
			if a.carrying_food > 0.0:
				s.food_store = minf(cap, s.food_store + a.carrying_food)
				a.carrying_food = 0.0
			if a.needs["hunger"] < STORE_HUNGRY_BELOW and s.food_store > 0.05:
				var meal := minf(STORE_MEAL, s.food_store)
				s.food_store -= meal
				a.needs["hunger"] = minf(1.0, a.needs["hunger"] + meal)
				s.meals_served += 1
				if s.meals_served == 1 and history_log and not _larder_told:
					_larder_told = true
					history_log.add("settlement", "Food put by in '%s' fed someone hungry: the first larder." % s.name, day)
		var days := SPOIL_DAYS
		for k in PRESERVING:
			if s.knowledge_pool.has(k):
				days = SPOIL_DAYS_PRESERVED
				break
		s.food_store *= exp(-delta / (days * TimeSystem.DAY_LENGTH))

# ---------------------------------------------------------------------------
# Cultural drift
# ---------------------------------------------------------------------------

func _tick_dialect(delta: float, day: int) -> void:
	for s: Settlement in settlements:
		if day - s.founding_day < 50:
			continue
		var drift: float = (randf() * 2.0 - 1.0) * 0.005
		s.dialect = clampf(s.dialect + drift, 0.0, 1.0)

# ---------------------------------------------------------------------------
# Inter-settlement contact
# ---------------------------------------------------------------------------

func _tick_inter_contact(day: int, history_log: HistoryLog) -> void:
	for i: int in range(settlements.size()):
		var s_a: Settlement = settlements[i] as Settlement
		for j: int in range(i + 1, settlements.size()):
			var s_b: Settlement = settlements[j] as Settlement
			if s_a.centre.distance_to(s_b.centre) > 12.0:
				continue
			# Once per day check
			if s_a.last_contact_day == day or s_b.last_contact_day == day:
				continue
			if randf() >= 0.3:
				continue
			# Share one concept from s_a pool to s_b pool
			if not s_a.knowledge_pool.is_empty():
				var keys_a: Array = s_a.knowledge_pool.keys()
				var concept: String = str(keys_a[randi() % keys_a.size()])
				s_b.knowledge_pool[concept] = true
			s_a.last_contact_day = day
			s_b.last_contact_day = day
			# Ideas keep flowing between neighbours, but they only *meet* once.
			var key := "%d:%d" % [mini(s_a.id, s_b.id), maxi(s_a.id, s_b.id)]
			if not _met_pairs.has(key):
				_met_pairs[key] = true
				history_log.add("settlement", "Settlements '%s' and '%s' made contact." % [s_a.name, s_b.name], day)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Average food left on the land round a point (walkable tiles only).
func food_around(c: Vector2, radius: int = FOOD_RADIUS) -> float:
	if world == null:
		return 1.0
	var total := 0.0
	var n := 0
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var x := int(c.x) + dx
			var z := int(c.y) + dz
			if not world.is_walkable(x + 0.5, z + 0.5):
				continue
			var t := world.get_tile(x, z)
			if int(t["type"]) in [World.TileType.GRASS, World.TileType.WOODLAND, World.TileType.FOREST]:
				total += world.food_of(t)
			n += 1
	return total / float(n) if n > 0 else 0.0

func _check_migration(day: int, history_log: HistoryLog) -> void:
	if world == null:
		return
	for s: Settlement in settlements:
		if s.member_ids.is_empty() or s.moving_until_day >= 0:
			continue
		var here := food_around(s.centre)
		s.lean_days = s.lean_days + 1 if here < LEAN_BELOW else 0
		if s.lean_days < LEAN_DAYS_TO_MOVE:
			continue
		var best := Vector2(-1, -1)
		var best_food := here + 0.15
		for i in 40:
			var a := randf() * TAU
			var r := randf_range(MOVE_MIN, MOVE_MAX)
			var c := s.centre + Vector2(cos(a), sin(a)) * r
			if not world.is_walkable(c.x, c.y):
				continue
			var crowded := false
			for other: Settlement in settlements:
				if other != s and other.centre.distance_to(c) < FOUNDING_SPACING:
					crowded = true
					break
			if crowded:
				continue
			var f := food_around(c)
			if f > best_food:
				best_food = f
				best = c
		if best.x < 0.0:
			continue
		var heading := _heading(best - s.centre)
		s.centre = best
		s.lean_days = 0
		s.moves += 1
		s.moving_until_day = day + 2
		history_log.add("settlement", "The people of '%s' packed up and moved %s, to better land." % [s.name, heading], day)

static func _heading(v: Vector2) -> String:
	var a := fposmod(rad_to_deg(atan2(v.x, -v.y)), 360.0)  # 0 = north (-z)
	return ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"][int(round(a / 45.0)) % 8]

## A name no living settlement already has (hamlet style, then town style).
func _unique_name() -> String:
	var taken: Dictionary = {}
	for s: Settlement in settlements:
		taken[s.name] = true
	for attempt in 40:
		var n := _generate_name(1 if attempt < 20 else 2, false)
		if not taken.has(n):
			return n
	return "Camp %d" % _next_id

## Settlements nobody lives in fade away after ABANDON_DAYS.
func _abandon_empty(day: int, history_log: HistoryLog) -> void:
	for s: Settlement in settlements.duplicate():
		if not s.member_ids.is_empty():
			_empty_since.erase(s.id)
			continue
		if not _empty_since.has(s.id):
			_empty_since[s.id] = day
		elif day - int(_empty_since[s.id]) >= ABANDON_DAYS:
			settlements.erase(s)
			_empty_since.erase(s.id)
			_prev_members.erase(s.id)
			history_log.add("settlement", "'%s' was abandoned." % s.name, day)

func _generate_name(tier: int, _has_writing: bool) -> String:
	if tier <= 0:
		return "Camp"
	if tier == 1:
		var adj: String = HAMLET_ADJECTIVES[randi() % HAMLET_ADJECTIVES.size()]
		var noun: String = HAMLET_NOUNS[randi() % HAMLET_NOUNS.size()]
		return adj + " " + noun
	# tier 2
	var prefix: String = NAMED_PREFIXES[randi() % NAMED_PREFIXES.size()]
	var suffix: String = NAMED_SUFFIXES[randi() % NAMED_SUFFIXES.size()]
	return prefix + suffix


func _find_centroid(agent_positions: Array) -> Vector2:
	if agent_positions.is_empty():
		return Vector2.ZERO
	var sum: Vector2 = Vector2.ZERO
	for p in agent_positions:
		sum += p as Vector2
	return sum / float(agent_positions.size())


func _find_centroid_agents(agents_group: Array) -> Vector2:
	if agents_group.is_empty():
		return Vector2.ZERO
	var sum: Vector2 = Vector2.ZERO
	for a: Agent in agents_group:
		sum += a.pos
	return sum / float(agents_group.size())

static func _member_holds(s, id: String, agents: Array) -> bool:
	for b: Agent in agents:
		if not b.is_dead and b.health > 0.0 and b.knowledge.has(id) and s.member_ids.has(b.agent_id):
			return true
	return false
