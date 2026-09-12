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
	var wood_store: float = 0.0
	var last_contact_day: int = 0
	var founding_day: int = 0

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
	_tick_resources(delta)

	# 7. Cultural drift
	_tick_dialect(delta, day)

	# 8. Inter-settlement contact
	_tick_inter_contact(day, history_log)


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
		if group.size() < 3:
			continue
		# Check no existing settlement centre within 6 tiles
		var centroid: Vector2 = _find_centroid_agents(group)
		var too_close: bool = false
		for s: Settlement in settlements:
			if s.centre.distance_to(centroid) <= 6.0:
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
	s.name = "Camp"
	settlements.append(s)
	_prev_members[s.id] = s.member_ids.duplicate()
	history_log.add("settlement", "New camp founded at (%.1f, %.1f) with %d members." % [centroid.x, centroid.y, group.size()], day)

# ---------------------------------------------------------------------------
# Membership
# ---------------------------------------------------------------------------

func _update_membership(agents: Array, spatial_grid = null) -> void:
	for s: Settlement in settlements:
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

func _check_tier_upgrades(agents: Array, history_log: HistoryLog, day: int) -> void:
	for s: Settlement in settlements:
		if s.tier == 0 and s.member_ids.size() >= 5:
			s.tier = 1
			s.name = _generate_name(1, false)
			history_log.add("settlement", "Camp has grown into hamlet '%s'." % s.name, day)
		elif s.tier == 1:
			var any_writing: bool = _any_member_knows(s, agents, "writing")
			if any_writing:
				s.tier = 2
				s.name = _generate_name(2, true)
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
					if not a.knowledge.has(chosen):
						a.knowledge[chosen] = true

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

func _tick_resources(delta: float) -> void:
	for s: Settlement in settlements:
		var cap: float = float(s.member_ids.size()) * 100.0
		s.food_store = minf(s.food_store + float(s.member_ids.size()) * 0.01 * delta, cap)
		s.wood_store = minf(s.wood_store + float(s.member_ids.size()) * 0.005 * delta, cap)

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
			history_log.add("settlement", "Settlements '%s' and '%s' made contact." % [s_a.name, s_b.name], day)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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
