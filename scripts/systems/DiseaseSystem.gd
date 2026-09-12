class_name DiseaseSystem
extends RefCounted

## Population-level disease layer.
##
## Per-agent infection progression (health/energy drain, natural recovery,
## immunity) and proximity-based transmission already live in Agent.gd
## (`infected`, `infection_timer`, `immune_timer`, `_try_spread_infection`
## called from `_try_socialise`). This system adds what operates above a
## single agent: a rare spontaneous daily onset, medicine access shortening
## and softening an active infection, outbreak detection, and narrative
## logging — it never sets up transmission between agents itself.

# Spontaneous onset — at most one per in-game day.
const ONSET_CHANCE_PER_DAY := 0.04

# Agent.gd clears `infected` once `infection_timer >= 60.0`; that is the
# baseline duration this system speeds up for agents with medicine access.
const BASE_DURATION := 60.0
const MEDICINE_DURATION := 35.0
# Extra per-second progress added to infection_timer for medicated agents so
# their infection resolves in ~MEDICINE_DURATION seconds instead of BASE_DURATION.
const MEDICINE_TIMER_BOOST := (BASE_DURATION / MEDICINE_DURATION) - 1.0

# Agent.gd drains 0.0005 hp/sec while infected; medicine claws back roughly
# half of that, softening the infection's severity.
const MEDICINE_HEAL_PER_SEC := 0.00025

# Outbreak state uses hysteresis: it starts once the infected share of the
# living population crosses START_RATE and only clears once it falls back to
# END_RATE, so the status doesn't flicker right at the boundary.
const OUTBREAK_START_RATE := 0.15
const OUTBREAK_MIN_CASES := 2
const OUTBREAK_END_RATE := 0.05

# ── HUD-facing state ─────────────────────────────────────────────────────────

var outbreak_active: bool = false
var outbreak_start_day: int = -1
var outbreak_peak_count: int = 0
var infected_count: int = 0
var infection_rate: float = 0.0

var _last_onset_day: int = -1

# ── Public API ────────────────────────────────────────────────────────────────

## @param delta - game-seconds since last tick
## @param agents - Array[Agent]
## @param day - current game day (onset is rolled at most once per day)
## @param history_log - narrative log for outbreak start/end events
## @param settlement_system - optional; used to check settlement medicine pools
func tick(delta: float, agents: Array, day: int, history_log: HistoryLog,
		  settlement_system: SettlementSystem = null) -> void:
	var alive: Array = []
	for entry in agents:
		var a := entry as Agent
		if a != null and not a.is_dead and a.health > 0.0:
			alive.append(a)

	_roll_onset(alive, day)
	_apply_medicine(alive, delta, settlement_system)
	_update_outbreak(alive, day, history_log)


func is_outbreak_active() -> bool:
	return outbreak_active


func get_infected_count() -> int:
	return infected_count


## Convenience summary for a HUD widget, e.g. "N infected, outbreak active".
func get_status() -> Dictionary:
	return {
		"infected_count": infected_count,
		"infection_rate": infection_rate,
		"outbreak_active": outbreak_active,
		"outbreak_start_day": outbreak_start_day,
		"outbreak_peak_count": outbreak_peak_count,
	}

# ── Internals ─────────────────────────────────────────────────────────────────

func _roll_onset(alive: Array, day: int) -> void:
	if day == _last_onset_day:
		return
	_last_onset_day = day
	if randf() >= ONSET_CHANCE_PER_DAY:
		return

	var healthy: Array = []
	for entry in alive:
		var a := entry as Agent
		if not a.infected and not a.is_immune:
			healthy.append(a)
	if healthy.is_empty():
		return

	var victim := healthy[randi() % healthy.size()] as Agent
	victim.infected = true
	victim.infection_timer = 0.0


func _apply_medicine(alive: Array, delta: float, settlement_system: SettlementSystem) -> void:
	for entry in alive:
		var a := entry as Agent
		if not a.infected:
			continue
		if not _has_medicine_access(a, settlement_system):
			continue
		a.infection_timer += delta * MEDICINE_TIMER_BOOST
		a.health = minf(1.0, a.health + MEDICINE_HEAL_PER_SEC * delta)


func _has_medicine_access(agent: Agent, settlement_system: SettlementSystem) -> bool:
	if agent.knowledge.has("medicine"):
		return true
	if settlement_system == null:
		return false
	var settlement := settlement_system.get_settlement_for_agent(agent.agent_id) as SettlementSystem.Settlement
	if settlement == null:
		return false
	return settlement.knowledge_pool.has("medicine")


func _update_outbreak(alive: Array, day: int, history_log: HistoryLog) -> void:
	var count := 0
	for entry in alive:
		var a := entry as Agent
		if a.infected:
			count += 1

	infected_count = count
	infection_rate = float(count) / float(alive.size()) if alive.size() > 0 else 0.0

	if not outbreak_active:
		if count >= OUTBREAK_MIN_CASES and infection_rate >= OUTBREAK_START_RATE:
			outbreak_active = true
			outbreak_start_day = day
			outbreak_peak_count = count
			history_log.add("disease", "An outbreak of illness is spreading (%d infected)" % count, day)
	else:
		outbreak_peak_count = maxi(outbreak_peak_count, count)
		if infection_rate <= OUTBREAK_END_RATE:
			outbreak_active = false
			var duration: int = maxi(0, day - outbreak_start_day)
			history_log.add(
				"disease",
				"The outbreak has subsided after %d day(s), having peaked at %d infected" % [duration, outbreak_peak_count],
				day
			)
