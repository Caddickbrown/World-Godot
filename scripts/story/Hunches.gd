class_name Hunches
extends RefCounted
## Guess what happens next. Hunches are questions the game asks about the
## world's near future; you lock in an answer and a right one adds a glimmer to
## the jar. Glimmers buy nothing. Nothing here touches the simulation.

const MAX_OPEN := 3
const FIRST_TO_DAYS := 6      # a "who thinks of X first" hunch lasts this long
const REFOUND_DAYS := 5       # "will X be found again before day N"
const SOMEONE_ELSE := "Someone else"

## {id, kind, concept, question, options, pick, deadline, resolved, correct, answer}
var open: Array = []
var history: Array = []
var glimmers := 0
var called := 0
var _next_id := 1

func pick(hunch_id: int, option: String) -> bool:
	for h in open:
		if int(h["id"]) == hunch_id and option in (h["options"] as Array):
			h["pick"] = option
			return true
	return false

## Offer new hunches from the state of the world. ledger: IdeaLedger.
func offer(agents: Array, ledger: IdeaLedger, concepts: Dictionary, day: int) -> Array:
	var added: Array = []
	if open.size() >= MAX_OPEN:
		return added
	# 1. A lost idea: will it come back in time?
	for id in ledger.ideas:
		if open.size() >= MAX_OPEN: break
		if ledger.stage_of(id) == IdeaLedger.Stage.WILTED and not _has_open("refound", id):
			added.append(_open("refound", id, "Will %s be known again before day %d?" % [ledger.name_of(id), day + REFOUND_DAYS],
				["Yes", "No"], day + REFOUND_DAYS))
	# 2. Who thinks of the next idea first?
	if open.size() < MAX_OPEN:
		var best_id := ""
		var best_ready: Array = []
		for id in concepts:
			if ledger.stage_of(id) != IdeaLedger.Stage.SEED or _has_open("first_to", id):
				continue
			var ready: Array = []
			for a in agents:
				if a.is_dead or a.health <= 0.0 or not a.is_adult:
					continue
				var ok := true
				for pre in (concepts[id] as Dictionary).get("prerequisites", []):
					if not a.knowledge.has(pre):
						ok = false
						break
				if ok:
					ready.append(a)
			if ready.size() >= 3 and ready.size() > best_ready.size() and not (concepts[id] as Dictionary).get("prerequisites", []).is_empty():
				best_id = id
				best_ready = ready
		if best_id != "":
			best_ready.sort_custom(func(x, y): return float(x.personality["curiosity"]) > float(y.personality["curiosity"]))
			var names: Array = best_ready.slice(0, 3).map(func(a): return a.agent_name)
			names.append(SOMEONE_ELSE)
			added.append(_open("first_to", best_id, "Who will first think of %s?" % ledger.name_of(best_id),
				names, day + FIRST_TO_DAYS))
	return added

## Feed events in; returns hunches resolved by this call.
func on_discovery(concept_id: String, who: String, refound: bool, first: bool, day: int) -> Array:
	var done: Array = []
	for h in open.duplicate():
		if h["concept"] != concept_id:
			continue
		if h["kind"] == "first_to" and first:
			var names: Array = h["options"]
			var answer: String = who if who in names else SOMEONE_ELSE
			done.append(_resolve(h, answer))
		elif h["kind"] == "refound" and refound:
			done.append(_resolve(h, "Yes"))
	return done

func on_day(day: int) -> Array:
	var done: Array = []
	for h in open.duplicate():
		if day > int(h["deadline"]):
			done.append(_resolve(h, "No" if h["kind"] == "refound" else "Nobody, yet"))
	return done

func _resolve(h: Dictionary, answer: String) -> Dictionary:
	open.erase(h)
	h["resolved"] = true
	h["answer"] = answer
	h["correct"] = str(h.get("pick", "")) == answer
	if str(h.get("pick", "")) != "":
		called += 1
		if h["correct"]:
			glimmers += 1
	history.append(h)
	return h

func _open(kind: String, concept: String, q: String, options: Array, deadline: int) -> Dictionary:
	var h := {"id": _next_id, "kind": kind, "concept": concept, "question": q, "options": options,
		"pick": "", "deadline": deadline, "resolved": false, "correct": false, "answer": ""}
	_next_id += 1
	open.append(h)
	return h

func _has_open(kind: String, concept: String) -> bool:
	for h in open:
		if h["kind"] == kind and h["concept"] == concept:
			return true
	return false
