class_name IdeaLedger
extends RefCounted
## What the world knows, counted among the LIVING (ConceptGraph.known_by keeps
## the dead too, so on its own an idea could never be lost).
##
## Stages: seed (nobody has thought of it), sprout (a few hold it), bloom (at
## least BLOOM_SHARE of the living), wilted (held once, now nobody alive does).
## Read-only: it looks at agents, it never changes them.

const BLOOM_SHARE := 0.4

enum Stage { SEED, SPROUT, BLOOM, WILTED }

## concept id -> {holders, peak, first_name, first_day, lost_day, lost_with, times_lost,
##                refound_by, refound_day, taught, stage, found, low, lost_pos}
## found: times anyone thought of it (first or again); low: the fewest living
## holders once it had reached three (how near it came to being lost).
var ideas: Dictionary = {}
var concept_names: Dictionary = {}

func setup(concepts: Dictionary) -> void:
	ideas.clear()
	for id in concepts:
		concept_names[id] = str((concepts[id] as Dictionary).get("name", id))
		ideas[id] = {"holders": 0, "peak": 0, "first_name": "", "first_day": -1, "lost_day": -1,
			"lost_with": "", "times_lost": 0, "refound_by": "", "refound_day": -1, "taught": 0,
			"stage": Stage.SEED, "found": 0, "low": -1, "lost_pos": Vector2(-1, -1)}

func name_of(id: String) -> String:
	return str(concept_names.get(id, id.replace("_", " ").capitalize()))

func note_discovery(id: String, who: String, day: int) -> Dictionary:
	## Returns {first: bool, refound: bool} so the keeper can word the event.
	var rec: Dictionary = ideas.get(id, {})
	if rec.is_empty():
		return {"first": false, "refound": false}
	# First means nobody has ever held it (peak 0), not merely "not seen yet".
	var first: bool = int(rec["first_day"]) < 0 and int(rec["peak"]) == 0
	var refound: bool = int(rec["stage"]) == Stage.WILTED
	rec["found"] = int(rec.get("found", 0)) + 1
	if first:
		rec["first_name"] = who
		rec["first_day"] = day
	if refound:
		rec["refound_by"] = who
		rec["refound_day"] = day
	return {"first": first, "refound": refound}

func note_taught(id: String) -> void:
	if ideas.has(id):
		ideas[id]["taught"] = int(ideas[id]["taught"]) + 1

## Recount living holders. Returns the ideas that changed stage as
## [{id, from, to, last_holder}] (last_holder is set when an idea wilts).
## recently_dead: people who died since the last recount, to name the last holder.
func recount(agents: Array, day: int, recently_dead: Array = []) -> Array:
	var alive := 0
	var counts: Dictionary = {}
	var last_holder: Dictionary = {}
	for a in agents:
		if a.is_dead or a.health <= 0.0:
			continue
		alive += 1
		for id in a.knowledge:
			counts[id] = int(counts.get(id, 0)) + 1
	# Remember who held each idea last time, so a wilting can name them.
	for a in recently_dead:
		for id in a.knowledge:
			if not counts.has(id):
				last_holder[id] = a
	var changes: Array = []
	for id in ideas:
		var rec: Dictionary = ideas[id]
		var n: int = int(counts.get(id, 0))
		rec["holders"] = n
		rec["peak"] = maxi(int(rec["peak"]), n)
		# The fewest who held it once it had taken hold (3+): how near it came to being lost.
		if int(rec["peak"]) >= 3:
			rec["low"] = n if int(rec.get("low", -1)) < 0 else mini(int(rec["low"]), n)
		var stage: int
		if n == 0:
			stage = Stage.WILTED if int(rec["peak"]) > 0 else Stage.SEED
		elif alive > 0 and float(n) / float(alive) >= BLOOM_SHARE:
			stage = Stage.BLOOM
		else:
			stage = Stage.SPROUT
		if stage != int(rec["stage"]):
			var change := {"id": id, "from": int(rec["stage"]), "to": stage, "last_holder": "", "last_id": -1}
			if stage == Stage.WILTED:
				rec["lost_day"] = day
				rec["times_lost"] = int(rec["times_lost"]) + 1
				rec["refound_by"] = ""
				rec["refound_day"] = -1
				var last = last_holder.get(id, null)
				rec["lost_with"] = last.agent_name if last else str(rec.get("lost_with", ""))
				# Where it was last known: the last holder's place when they died.
				rec["lost_pos"] = last.pos if last else Vector2(-1, -1)
				change["last_holder"] = rec["lost_with"]
				change["last_id"] = last.agent_id if last else -1
				change["pos"] = rec["lost_pos"]
			rec["stage"] = stage
			changes.append(change)
	return changes

func stage_of(id: String) -> int:
	return int((ideas.get(id, {}) as Dictionary).get("stage", Stage.SEED))

func count_in(stage: int) -> int:
	var n := 0
	for id in ideas:
		if int(ideas[id]["stage"]) == stage:
			n += 1
	return n

static func stage_name(stage: int) -> String:
	return ["not yet thought of", "spreading", "widely held", "lost"][stage]

func to_dict() -> Dictionary:
	return ideas.duplicate(true)
