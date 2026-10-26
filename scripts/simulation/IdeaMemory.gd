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

## A new craft is fragile: whoever first thinks of one (era 2 and later) has
## to make it a few times before they can show anyone how, this many game
## seconds of their life. If they die first, it dies with them. Once someone
## has been shown, they can show others at once.
static var mastery_time := 0.0

## id -> {places: Array[Vector2], day, last_name, last_id}
var ghosts: Dictionary = {}
## id -> {day, lost_day, last_name, near} for the latest time each was found again.
var refound: Dictionary = {}
var lost_total := 0
var refound_total := 0

## Someone died. Returns the ideas lost with them. home: their camp's
## centre (Vector2(-1, -1) for none).
func note_death(dead: Agent, agents: Array, day: int, home: Vector2 = Vector2(-1, -1)) -> Array:
	_since.erase(dead.agent_id)
	var lost: Array = []
	for id in dead.knowledge:
		if ghosts.has(id) or _held(str(id), dead, agents):
			continue
		var places: Array = [dead.pos]
		if home.x >= 0.0 and home.distance_to(dead.pos) > 2.0:
			places.append(home)
		ghosts[id] = {"places": places, "day": day, "last_name": dead.agent_name, "last_id": dead.agent_id}
		lost_total += 1
		lost.append(str(id))
	return lost

static func _held(id: String, dead: Agent, agents: Array) -> bool:
	for a in agents:
		if a != dead and not a.is_dead and a.health > 0.0 and a.knowledge.has(id):
			return true
	return false

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

# ── A new craft needs practice ───────────────────────────────────────────────

var _since: Dictionary = {}    # agent_id -> {craft id: age when they thought of it}

## They thought of a craft themselves: it is theirs to practise first.
func note_invented(who: Agent, id: String) -> void:
	if mastery_time > 0.0:
		if not _since.has(who.agent_id):
			_since[who.agent_id] = {}
		_since[who.agent_id][id] = who.age

## Can they show someone this craft yet?
func may_teach(teacher: Agent, id: String) -> bool:
	if mastery_time <= 0.0 or not _since.has(teacher.agent_id):
		return true
	var since: Dictionary = _since[teacher.agent_id]
	if not since.has(id):
		return true
	if teacher.age - float(since[id]) < mastery_time:
		return false
	since.erase(id)
	return true

## Someone has thought of a lost idea again: the ghost is laid to rest.
func note_refound(id: String, who: Agent, day: int) -> void:
	if not ghosts.has(id):
		return
	var g: Dictionary = ghosts[id]
	refound[id] = {"day": day, "lost_day": int(g["day"]), "last_name": str(g["last_name"]),
		"near": near_ghost(id, who.pos), "by": who.agent_name}
	ghosts.erase(id)
	refound_total += 1
