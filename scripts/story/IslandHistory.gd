class_name IslandHistory
extends RefCounted
## The island over time, for the Island screen's graphs: population, ideas
## known among the living, ideas ever found, and settlements by size, sampled
## every SAMPLE_DAYS of game time. Reads the world, never writes it. Kept to
## MAX_SAMPLES by thinning the oldest half when full, so a long world still
## draws its whole story.

const SAMPLE_DAYS := 0.125          # three hours of game time
const MAX_SAMPLES := 480

var samples: Array = []             # {t (days since start), pop, known, found, camps, hamlets, towns}
var _next_t := 0.0
var peak_pop := 0
var world_ref: WeakRef = null

## Time in days (1.0 = the first dawn) from day and hour.
static func days_of(day: int, hour: float) -> float:
	return float(day - 1) + hour / 24.0

func clear() -> void:
	samples.clear()
	_next_t = 0.0
	peak_pop = 0

## Called with Main every HUD update; records a sample when one is due. A new
## world (R, a new seed) starts a new history.
func observe(main: Node) -> void:
	if main == null or main.world == null or main.time_system == null:
		return
	if world_ref == null or world_ref.get_ref() != main.world:
		world_ref = weakref(main.world)
		clear()
	var t := days_of(main.time_system.day, main.time_system.hour)
	if not samples.is_empty() and t < float(samples[-1]["t"]):
		clear()
	if t < _next_t and not samples.is_empty():
		return
	_next_t = (floor(t / SAMPLE_DAYS) + 1.0) * SAMPLE_DAYS
	record(t, main)

func record(t: float, main: Node) -> void:
	var pop := 0
	for a in main.agents:
		if not a.is_dead and a.health > 0.0:
			pop += 1
	var known := 0
	var ledger = main.story.ledger if main.story else null
	if ledger:
		known = ledger.count_in(IdeaLedger.Stage.SPROUT) + ledger.count_in(IdeaLedger.Stage.BLOOM)
	var found: int = main.concept_graph.get_discovered_concepts().size() if main.concept_graph else 0
	var tiers := [0, 0, 0]
	if main.settlement_system:
		for s in main.settlement_system.get_settlements():
			tiers[clampi(int(s.tier), 0, 2)] += 1
	add({"t": t, "pop": pop, "known": known, "found": found, "camps": tiers[0], "hamlets": tiers[1], "towns": tiers[2]})

func add(sample: Dictionary) -> void:
	samples.append(sample)
	peak_pop = maxi(peak_pop, int(sample["pop"]))
	if samples.size() > MAX_SAMPLES:
		var kept: Array = []
		var half := samples.size() / 2
		for i in samples.size():
			if i >= half or i % 2 == 0:
				kept.append(samples[i])
		samples = kept

## One series as Vector2(t, value) points.
func series(key: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	for s in samples:
		out.append(Vector2(float(s["t"]), float(s[key])))
	return out
