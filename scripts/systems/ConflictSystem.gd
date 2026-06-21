class_name ConflictSystem
extends RefCounted

## Agent-level and settlement-level conflict simulation.

var _conflict_pairs: Dictionary = {}  # "id1:id2" → cooldown float

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func tick(delta: float, agents: Array, day: int, history_log: HistoryLog) -> void:
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

	# Check pairs of alive agents for potential conflict
	for i: int in range(alive.size()):
		var agent_a := alive[i] as Agent
		if agent_a == null:
			continue
		for j: int in range(i + 1, alive.size()):
			var agent_b := alive[j] as Agent
			if agent_b == null:
				continue
			_check_agent_conflict(agent_a, agent_b, day, history_log)


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


func get_faction(agent: Agent) -> int:
	return agent.agent_id % 2


func is_in_conflict(agent: Agent) -> bool:
	return float(agent.get_meta("conflict_cooldown", 0.0)) > 0.0

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _check_agent_conflict(agent_a: Agent, agent_b: Agent, day: int, history_log: HistoryLog) -> void:
	# Must be different factions
	if get_faction(agent_a) == get_faction(agent_b):
		return

	# Must be within 1.5 tiles
	var dist: float = agent_a.pos.distance_to(agent_b.pos)
	if dist > 1.5:
		return

	# Either on cooldown — skip
	if is_in_conflict(agent_a) or is_in_conflict(agent_b):
		return

	# 20% chance per second (scaled by delta stored as accumulated probability).
	# Because tick() is called each frame we need to decide here with raw 20% per call
	# and the caller must ensure tick() is called roughly once per second for the
	# stated semantics to hold.  We expose the raw check so callers can pass
	# delta-weighted probability if desired — here we use a simple constant roll.
	if randf() > 0.20:
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
