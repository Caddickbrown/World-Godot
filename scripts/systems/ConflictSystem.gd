class_name ConflictSystem
extends RefCounted

## Agent-level and settlement-level conflict simulation.

var _conflict_pairs: Dictionary = {}  # "id1:id2" → cooldown float

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Settlement membership decides who is "us". Agents with no settlement belong
## to nobody's faction and never clash; nor do two members of one settlement.
var settlement_system = null  # SettlementSystem, optional

var _delta: float = 0.0

func tick(delta: float, agents: Array, day: int, history_log: HistoryLog,
		  spatial_grid = null) -> void:
	_delta = delta
	var alive: Array = []
	for entry in agents:
		var a := entry as Agent
		if a == null:
			continue
		if not a.is_dead:
			alive.append(a)

	# Decrement all per-agent conflict cooldowns
	for entry in alive:
		var a := entry as Agent
		var cd: float = float(a.get_meta("conflict_cooldown", 0.0))
		if cd > 0.0:
			cd = maxf(0.0, cd - delta)
			a.set_meta("conflict_cooldown", cd)
			if cd <= 0.0:
				a.set_meta("in_conflict", false)

	# Only run conflict checks when population exceeds threshold
	if alive.size() <= 15:
		return

	# Conflict only fires within CONFLICT_RADIUS tiles, so an all-pairs sweep is
	# almost entirely wasted work — at a thousand agents that is half a million
	# distance checks a frame. Ask the spatial grid for the handful of agents
	# actually close enough to clash.
	if spatial_grid != null:
		var seen: Dictionary = {}
		for entry in alive:
			var agent_a := entry as Agent
			if agent_a == null:
				continue
			for other in spatial_grid.get_nearby_agents(agent_a.pos, CONFLICT_RADIUS):
				var agent_b := other as Agent
				if agent_b == null or agent_b.agent_id == agent_a.agent_id:
					continue
				# Each unordered pair once.
				var lo: int = mini(agent_a.agent_id, agent_b.agent_id)
				var hi: int = maxi(agent_a.agent_id, agent_b.agent_id)
				var key: int = lo * 100000 + hi
				if seen.has(key):
					continue
				seen[key] = true
				_check_agent_conflict(agent_a, agent_b, day, history_log)
		return

	# Fallback when no grid is supplied.
	for i: int in range(alive.size()):
		var agent_a2 := alive[i] as Agent
		if agent_a2 == null:
			continue
		for j: int in range(i + 1, alive.size()):
			var agent_b2 := alive[j] as Agent
			if agent_b2 == null:
				continue
			_check_agent_conflict(agent_a2, agent_b2, day, history_log)


func trigger_war(side_a: Array, side_b: Array, day: int, history_log: HistoryLog) -> void:
	if side_a.is_empty() or side_b.is_empty():
		return

	# Mark all agents as at war
	for entry in side_a:
		var a := entry as Agent
		if a != null and not a.is_dead:
			a.set_meta("at_war", true)
	for entry in side_b:
		var b := entry as Agent
		if b != null and not b.is_dead:
			b.set_meta("at_war", true)

	# Calculate casualties: 10–20% per side
	var casualties_a: int = _apply_casualties(side_a)
	var casualties_b: int = _apply_casualties(side_b)
	var total_fallen: int = casualties_a + casualties_b

	var name_a: String = _side_name(side_a)
	var name_b: String = _side_name(side_b)
	var msg: String = "%s and %s went to war — %d fell" % [name_a, name_b, total_fallen]
	history_log.add("war", msg, day)


## -1 = no faction. Used to be agent_id % 2, which split every family down the
## middle and had 40 founders "clashing" in the first minute of a new world.
func get_faction(agent: Agent) -> int:
	if settlement_system == null:
		return -1
	var s = settlement_system.get_settlement_for_agent(agent.agent_id)
	return -1 if s == null else int(s.id)


func is_in_conflict(agent: Agent) -> bool:
	return float(agent.get_meta("conflict_cooldown", 0.0)) > 0.0

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

# Maximum distance at which two agents can clash.
const CONFLICT_RADIUS := 1.5
## A hungry pair from rival settlements, side by side, clashes about once in
## five seconds of game time (was 20% per frame, i.e. at once).
const CLASH_CHANCE_PER_SEC := 0.2
const HUNGRY_BELOW := 0.35

func _check_agent_conflict(agent_a: Agent, agent_b: Agent, day: int, history_log: HistoryLog) -> void:
	# Must be members of two different settlements
	var fa := get_faction(agent_a)
	var fb := get_faction(agent_b)
	if fa < 0 or fb < 0 or fa == fb:
		return

	# People fight over food, not for sport: one of them must be going hungry.
	if minf(float(agent_a.needs.get("hunger", 1.0)), float(agent_b.needs.get("hunger", 1.0))) > HUNGRY_BELOW:
		return

	# Must be within CONFLICT_RADIUS tiles
	var dist: float = agent_a.pos.distance_to(agent_b.pos)
	if dist > CONFLICT_RADIUS:
		return

	# Either on cooldown — skip
	if is_in_conflict(agent_a) or is_in_conflict(agent_b):
		return

	# 20% chance per second (scaled by delta stored as accumulated probability).
	# Because tick() is called each frame we need to decide here with raw 20% per call
	# and the caller must ensure tick() is called roughly once per second for the
	# stated semantics to hold.  We expose the raw check so callers can pass
	# delta-weighted probability if desired — here we use a simple constant roll.
	if randf() > CLASH_CHANCE_PER_SEC * _delta:
		return

	# Apply conflict effects
	agent_a.needs["energy"] = maxf(0.0, float(agent_a.needs.get("energy", 1.0)) - 0.05)
	agent_b.needs["energy"] = maxf(0.0, float(agent_b.needs.get("energy", 1.0)) - 0.05)

	agent_a.set_meta("conflict_cooldown", 30.0)
	agent_b.set_meta("conflict_cooldown", 30.0)
	agent_a.set_meta("in_conflict", true)
	agent_b.set_meta("in_conflict", true)

	var msg: String = "%s and %s clashed" % [agent_a.agent_name, agent_b.agent_name]
	history_log.add("conflict", msg, day)


func _apply_casualties(side: Array) -> int:
	var alive: Array = []
	for entry in side:
		var a := entry as Agent
		if a != null and not a.is_dead:
			alive.append(a)

	# 10–20% casualties
	var count: int = alive.size()
	var pct: float = 0.10 + randf() * 0.10
	var num_casualties: int = maxi(0, int(float(count) * pct))

	alive.shuffle()
	for i: int in range(num_casualties):
		var victim := alive[i] as Agent
		if victim == null:
			continue
		victim.health = 0.0
		victim.is_dead = true
		victim.death_cause = "conflict"

	return num_casualties


func _side_name(side: Array) -> String:
	for entry in side:
		var a := entry as Agent
		if a != null:
			return a.agent_name
	return "Unknown"
