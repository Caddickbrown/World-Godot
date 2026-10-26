class_name IdeaMemory
extends RefCounted
## Ideas are lost, and found again (docs/features/ideas.md, open decisions 0
## and 2 in docs/GAME_DESIGN.md).
##
## The simulation's side of it. When someone dies and nobody alive still
## holds an idea they knew, the idea is lost: a "ghost" of it stays where
## they died and at their camp's hearth. Anyone who could think of it again
## (they hold its prerequisites) thinks of it a little more easily near a
## ghost: the old kiln, the place the nets were mended. A ghost stays until
## the idea is found again.
##
## ConceptGraph owns one; Main tells it of each death. It reads agents and
## never changes them.

## Tiles from a ghost within which it helps.
const GHOST_RADIUS := 14.0
## How much easier an idea is to think of again near its ghost.
static var ghost_bonus := 4.0

## Master crafts: trades handed on master to apprentice, not picked up by
## watching. A master takes on at most `apprentices` in each craft; an
## apprentice knows the craft only when their apprenticeship is done,
## `apprenticeship` game seconds later, and only if their master is alive
## to finish it. So for days a new craft lives in one pair of hands and can
## die with them. Chosen as the specialist trades (and pottery, the brief's
## own example); none is a prerequisite whole branches of the tree wait on.
const MASTER_CRAFTS := ["pottery", "sailing", "boat_building", "navigation", "cartography", "printing",
	"beekeeping", "dyeing", "herbalism", "medicine_advanced", "horse_taming"]
static var apprenticeship := 3.0 * 120.0
static var apprentices := 2
## The chance someone works a master craft out alone while a master of it
## lives (1: as for any idea; 0: never, they'd go and learn it instead).
static var reinvent := 0.0

static func is_master_craft(id: String) -> bool:
	return MASTER_CRAFTS.has(id)

## id -> {places: Array[Vector2], day, last_name, last_id}
var ghosts: Dictionary = {}
## Bumped whenever a ghost comes or goes (ConceptGraph caches odds on it).
var version := 0
## id -> {day, lost_day, last_name, near} for the latest time each was found again.
var refound: Dictionary = {}
var lost_total := 0
var refound_total := 0

## Someone died. Returns the ideas lost with them. home: their camp's
## centre (Vector2(-1, -1) for none).
func note_death(dead: Agent, agents: Array, day: int, home: Vector2 = Vector2(-1, -1)) -> Array:
	_forget_person(dead)
	var lost: Array = []
	for id in dead.knowledge:
		if ghosts.has(id) or _held(str(id), dead, agents):
			continue
		var places: Array = [dead.pos]
		if home.x >= 0.0 and home.distance_to(dead.pos) > 2.0:
			places.append(home)
		ghosts[id] = {"places": places, "day": day, "last_name": dead.agent_name, "last_id": dead.agent_id}
		version += 1
		lost_total += 1
		lost.append(str(id))
	return lost

static func _held(id: String, dead: Agent, agents: Array) -> bool:
	for a in agents:
		if a != dead and not a.is_dead and a.health > 0.0 and a.knowledge.has(id):
			return true
	return false

func held_by_living(id: String, agents: Array) -> bool:
	return _held(id, null, agents)

func is_lost(id: String) -> bool:
	return ghosts.has(id)

## The discovery odds multiplier for this idea at this place: ghost_bonus
## near one of its ghosts, else 1.
func bonus(id: String, at: Vector2) -> float:
	if not ghosts.has(id):
		return 1.0
	return ghost_bonus if near_ghost(id, at) else 1.0

func near_ghost(id: String, at: Vector2) -> bool:
	for p in (ghosts.get(id, {}) as Dictionary).get("places", []):
		if (p as Vector2).distance_to(at) <= GHOST_RADIUS:
			return true
	return false

# ── Masters and apprentices ──────────────────────────────────────────────────

var _taken: Dictionary = {}       # master id -> {craft id: apprentices taken on}
var _learning: Dictionary = {}    # apprentice id -> {craft id: [master id, age begun]}

## Can this master take on another apprentice in this craft?
func may_take(master: Agent, id: String) -> bool:
	return int((_taken.get(master.agent_id, {}) as Dictionary).get(id, 0)) < apprentices

func is_learning(who: Agent, id: String) -> bool:
	return (_learning.get(who.agent_id, {}) as Dictionary).has(id)

func begin(master: Agent, learner: Agent, id: String) -> void:
	if not _taken.has(master.agent_id):
		_taken[master.agent_id] = {}
	_taken[master.agent_id][id] = int(_taken[master.agent_id].get(id, 0)) + 1
	if not _learning.has(learner.agent_id):
		_learning[learner.agent_id] = {}
	_learning[learner.agent_id][id] = [master.agent_id, learner.age]

## They meet their master again: is the apprenticeship done? (Clears it.)
func finished(learner: Agent, master: Agent, id: String) -> bool:
	var rec: Array = (_learning.get(learner.agent_id, {}) as Dictionary).get(id, [])
	if rec.is_empty() or int(rec[0]) != master.agent_id or learner.age - float(rec[1]) < apprenticeship:
		return false
	_learning[learner.agent_id].erase(id)
	return true

## A master's death ends their apprentices' learning; the dead keep no records.
func _forget_person(dead: Agent) -> void:
	_taken.erase(dead.agent_id)
	_learning.erase(dead.agent_id)
	for learner_id in _learning:
		var crafts: Dictionary = _learning[learner_id]
		for id in crafts.keys():
			if int(crafts[id][0]) == dead.agent_id:
				crafts.erase(id)

## Someone has thought of a lost idea again: the ghost is laid to rest.
func note_refound(id: String, who: Agent, day: int) -> void:
	if not ghosts.has(id):
		return
	var g: Dictionary = ghosts[id]
	refound[id] = {"day": day, "lost_day": int(g["day"]), "last_name": str(g["last_name"]),
		"near": near_ghost(id, who.pos), "by": who.agent_name}
	ghosts.erase(id)
	version += 1
	refound_total += 1
