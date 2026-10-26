class_name LineageTracker
extends RefCounted

## The island's memory of who came from whom (docs/features/generations.md).
##
## Simulation side: Main feeds it births, deaths, discoveries and teaching, and
## it does three things the world can feel:
##   * keeps the family register (by id, so the dead stay in it after burial);
##   * names some children after a dead grandparent or a legend of their camp
##     (deterministic: a hash of the world seed and the child's id, never the
##     player and never the global RNG);
##   * turns notable dead into legends that elders tell at the evening fire.
##     A legend fades when nobody who knew them is left, unless their camp
##     knows oral tradition, when it lives on as a myth.
## What happens is queued in `events` for Main to hand the story (drain_events).
##
## It also still records who first discovered each concept, and on what day.

const NAMED_FOR_GRANDPARENT := 0.4   # chance, when a grandparent has died
const NAMED_FOR_LEGEND := 0.15       # chance, else, when the camp has a legend
## A legend: a first discovery, or a long life, many children, many taught.
const LEGEND_AGE_DAYS := 9.0
const LEGEND_CHILDREN := 7
const LEGEND_TAUGHT := 100
## Per second, per elder with a legend to tell, in the evening (at the fire,
## or wherever people sit together: in practice the fire is often empty).
const TELL_RATE := 1.0 / 25.0
const EVENING_FROM := 18.0
const EVENING_TO := 23.0
## How long a listener keeps turning a story over (game seconds; half a day).
const ECHO_SECONDS := 60.0
const TELL_SECONDS := 6.0
const HEAR_RADIUS := 5.0
const CHECK_INTERVAL := 3.0
const MYTH_IDEA := "oral_tradition"

## Phrases for what a first discoverer did, as the old tell it.
const FIRST_DEEDS := {
	"fire": "first made fire", "language": "spoke the first words", "sailing": "first sailed the sea",
	"agriculture": "planted the first field", "hunting": "led the first hunt", "fishing": "caught the first fish",
	"cooking": "cooked the first meal", "stone_tools": "struck the first stone blade",
	"swimming": "first swam in the sea", "music": "sang the first song", "oral_tradition": "told the first story",
	"shelter": "built the first shelter", "medicine": "first healed the sick",
}

# concept_id (String) → { "concept_id": String, "name": String, "id": int, "day": int }
var _discoveries: Dictionary = {}

## id → {id, name, parents, children, partner, born_day, died_day, age_days,
##       cause, founder, taught, named_for, camp, camp_name}
var people: Dictionary = {}
## id → {id, name, deed, camp, camp_name, day, knew, heard, myth, faded, told}
var legends: Dictionary = {}
var events: Array = []
var concept_names: Dictionary = {}   # id -> display name (for deeds)

var _seed := 0
var _rng := RandomNumberGenerator.new()
var _check := 0.0
var _echo: Dictionary = {}   # listener id -> seconds left with the story on their mind


func setup(founders: Array, world_seed: int, concepts: Dictionary = {}) -> void:
	_seed = world_seed
	_rng.seed = hash(world_seed) ^ 0x6e3e
	for id in concepts:
		concept_names[id] = str((concepts[id] as Dictionary).get("name", id))
	for a in founders:
		var p := _person(a, 1)
		p["founder"] = true


## Records a first discovery. Ignores duplicates — only the first call for a
## given concept_id is stored.
func record(concept_id: String, agent: Agent, day: int) -> void:
	if _discoveries.has(concept_id):
		return
	_discoveries[concept_id] = {
		"concept_id": concept_id,
		"name": agent.agent_name,
		"id": agent.agent_id,
		"day": day,
	}


## Returns the discoverer entry for a concept, or an empty Dictionary if none
## has been recorded yet.
func get_discoverer(concept_id: String) -> Dictionary:
	return _discoveries.get(concept_id, {})


## Returns all discovery entries sorted by day ascending, for a timeline view.
func all_discoveries() -> Array:
	var result: Array = _discoveries.values()
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["day"]) < int(b["day"]))
	return result


func clear() -> void:
	_discoveries.clear()
	people.clear()
	legends.clear()
	events.clear()


## How often each kind of event has happened (tools/balance.gd prints it).
var stats: Dictionary = {}

func _emit(evt: Dictionary) -> void:
	events.append(evt)
	stats[evt["kind"]] = int(stats.get(evt["kind"], 0)) + 1

func drain_events() -> Array:
	var out := events
	events = []
	return out

# ── Feeding (Main) ───────────────────────────────────────────────────────────

## A child is born. May rename them after someone gone; call before the child
## is drawn or told. living: the living people (for names already in use).
func note_birth(child: Agent, pa: Agent, pb: Agent, day: int, living: Array) -> void:
	var c := _person(child, day)
	for p in [pa, pb]:
		if p == null:
			continue
		var pr := _person(p, day)
		if not (child.agent_id in pr["children"]):
			pr["children"].append(child.agent_id)
		if not (p.agent_id in c["parents"]):
			c["parents"].append(p.agent_id)
	var pick := pick_namesake(child.agent_id, c["parents"], _names_in_use(living))
	if not pick.is_empty():
		var ns: Dictionary = people[int(pick["id"])]
		child.agent_name = str(ns["name"])
		c["name"] = child.agent_name
		c["named_for"] = int(pick["id"])
		_emit({"kind": "named", "child_id": child.agent_id, "child": child.agent_name,
			"namesake_id": int(pick["id"]), "why": pick["why"], "camp_name": str(pick.get("camp_name", "")),
			"pos": child.pos})
	# Four generations: a great-grandparent is alive to see this one born.
	for gg in ancestors(child.agent_id, 3):
		if int(people[gg]["died_day"]) < 0:
			_emit({"kind": "four_generations", "elder_id": gg, "elder": str(people[gg]["name"]),
				"child_id": child.agent_id, "child": child.agent_name, "pos": child.pos})
			break


## Who a child is named for: {id, why: "grandparent"|"legend"}, or {} for
## their own name. Pure in the register, the world seed and the child's id.
func pick_namesake(child_id: int, parent_ids: Array, in_use: Dictionary) -> Dictionary:
	var grand: Array = []
	for pid in parent_ids:
		for gid in (people.get(int(pid), {}) as Dictionary).get("parents", []):
			var g: Dictionary = people.get(int(gid), {})
			if not g.is_empty() and int(g["died_day"]) >= 0 and not in_use.has(str(g["name"])) and not (int(gid) in grand):
				grand.append(int(gid))
	if not grand.is_empty() and World.roll(_seed, child_id, 11) < NAMED_FOR_GRANDPARENT:
		grand.sort()
		return {"id": grand[int(World.roll(_seed, child_id, 12) * grand.size()) % grand.size()], "why": "grandparent"}
	var camp := -1
	for pid in parent_ids:
		camp = int((people.get(int(pid), {}) as Dictionary).get("camp", -1))
		if camp >= 0:
			break
	var told: Array = []
	for lid in legends:
		var l: Dictionary = legends[lid]
		if not l["faded"] and int(l["camp"]) == camp and not in_use.has(str(l["name"])):
			told.append(int(lid))
	if not told.is_empty() and World.roll(_seed, child_id, 13) < NAMED_FOR_LEGEND:
		told.sort()
		var lid: int = told[int(World.roll(_seed, child_id, 14) * told.size()) % told.size()]
		return {"id": lid, "why": "legend", "camp_name": str(legends[lid]["camp_name"])}
	return {}


func note_taught(teacher_id: int) -> void:
	if people.has(teacher_id):
		people[teacher_id]["taught"] = int(people[teacher_id]["taught"]) + 1


## Someone died. settlement_system may be null.
func note_death(a: Agent, day: int, settlement_system = null, living: Array = []) -> void:
	var p := _person(a, day)
	if int(p["died_day"]) >= 0:
		return
	p["died_day"] = day
	p["age_days"] = a.age / TimeSystem.DAY_LENGTH
	p["cause"] = a.death_cause
	if settlement_system:
		var st = settlement_system.get_settlement_for_agent(a.agent_id)
		if st:
			p["camp"] = int(st.id)
			p["camp_name"] = str(st.name)
	var deed := deed_of(a.agent_id)
	if deed == "":
		return
	var knew := {}
	for o in living:
		if o == a or o.is_dead:
			continue
		var op: Dictionary = people.get(o.agent_id, {})
		if (int(p["camp"]) >= 0 and int(op.get("camp", -2)) == int(p["camp"])) or relation(o.agent_id, a.agent_id) != "":
			knew[o.agent_id] = true
	legends[a.agent_id] = {"id": a.agent_id, "name": a.agent_name, "deed": deed, "camp": int(p["camp"]),
		"camp_name": str(p["camp_name"]), "day": day, "knew": knew, "heard": {}, "myth": false,
		"faded": false, "told": 0}
	_emit({"kind": "legend", "id": a.agent_id, "name": a.agent_name, "deed": deed,
		"camp_name": str(p["camp_name"]), "pos": a.pos})


## Keeps partners and camps current, lets legends fade or become myths, and
## has elders at the fire tell them. Reads agents; writes only a teller's
## speech bubble and what listeners have heard.
## hour < 0: only those at the fire tell (tests).
func tick(delta: float, agents: Array, settlement_system = null, hour: float = -1.0) -> void:
	_check += delta
	if not _echo.is_empty() and delta > 0.0:
		_fade_echoes(delta, agents)
	if _check >= CHECK_INTERVAL:
		_check = 0.0
		_refresh(agents, settlement_system)
	if legends.is_empty() or delta <= 0.0:
		return
	var evening := hour >= EVENING_FROM and hour < EVENING_TO
	for a in agents:
		if a.is_dead or not a.is_elderly or a.speech_bubble_timer > 0.0:
			continue
		if not (a.at_fire or (evening and a.state != Agent.State.SLEEPING)):
			continue
		if _rng.randf() >= TELL_RATE * delta:
			continue
		var lid := _legend_for(a)
		if lid < 0:
			continue
		_tell(a, lid, agents)

# ── Reading ──────────────────────────────────────────────────────────────────

func person(id: int) -> Dictionary:
	return people.get(id, {})

func is_legend(id: int) -> bool:
	return legends.has(id)

## Ids `generations` steps up (1: parents, 2: grandparents, 3: great-).
func ancestors(id: int, generations: int) -> Array:
	var level: Array = [id]
	for _g in generations:
		var up: Array = []
		for x in level:
			for pid in (people.get(int(x), {}) as Dictionary).get("parents", []):
				if people.has(int(pid)) and not (int(pid) in up):
					up.append(int(pid))
		level = up
	return level

## Ids `generations` steps down (1: children, 2: grandchildren...).
func descendants(id: int, generations: int) -> Array:
	var level: Array = [id]
	for _g in generations:
		var down: Array = []
		for x in level:
			for cid in (people.get(int(x), {}) as Dictionary).get("children", []):
				if people.has(int(cid)) and not (int(cid) in down):
					down.append(int(cid))
		level = down
	return level

## What `of` is to `who`: "partner", "parent", "child", "grandparent",
## "grandchild", "sibling" or "".
func relation(who: int, of: int) -> String:
	var w: Dictionary = people.get(who, {})
	if w.is_empty():
		return ""
	if int(w["partner"]) == of:
		return "partner"
	if of in w["parents"]:
		return "parent"
	if of in w["children"]:
		return "child"
	if of in ancestors(who, 2):
		return "grandparent"
	if of in descendants(who, 2):
		return "grandchild"
	for pid in w["parents"]:
		if of in (people.get(int(pid), {}) as Dictionary).get("children", []):
			return "sibling"
	return ""

## How a life is remembered, or "" if it isn't legend-worthy.
func deed_of(id: int) -> String:
	var p: Dictionary = people.get(id, {})
	if p.is_empty():
		return ""
	for e in all_discoveries():
		if int(e["id"]) == id:
			var cid := str(e["concept_id"])
			return str(FIRST_DEEDS.get(cid, "first thought of %s" % str(concept_names.get(cid, cid)).to_lower()))
	if (p["children"] as Array).size() >= LEGEND_CHILDREN:
		return "raised %d children" % (p["children"] as Array).size()
	if int(p["taught"]) >= LEGEND_TAUGHT:
		return "taught %d people what they knew" % int(p["taught"])
	if float(p["age_days"]) >= LEGEND_AGE_DAYS:
		return "lived to a great age"
	return ""

## The line a teller says: "Old Aya first made fire, they say."
func legend_line(teller_id: int, lid: int) -> String:
	var l: Dictionary = legends[lid]
	var rel := relation(teller_id, lid)
	var nm := str(l["name"])
	match rel:
		"parent": return "My parent %s %s." % [nm, l["deed"]]
		"grandparent": return "My grandparent %s %s, you know." % [nm, l["deed"]]
		"partner": return "My %s %s. I miss them." % [nm, l["deed"]]
	if l["myth"]:
		return "Long ago, %s %s, they say." % [nm, l["deed"]]
	var old := float((people.get(lid, {}) as Dictionary).get("age_days", 0.0)) >= 6.0
	return "%s%s %s, they say." % ["Old " if old else "", nm, l["deed"]]

# ── Inside ───────────────────────────────────────────────────────────────────

func _person(a: Agent, day: int) -> Dictionary:
	if not people.has(a.agent_id):
		people[a.agent_id] = {"id": a.agent_id, "name": a.agent_name, "parents": a.parents.duplicate(),
			"children": a.children.duplicate(), "partner": a.bonded_partner_id, "born_day": day,
			"died_day": -1, "age_days": 0.0, "cause": "", "founder": false, "taught": 0,
			"named_for": -1, "camp": -1, "camp_name": ""}
	return people[a.agent_id]

func _names_in_use(living: Array) -> Dictionary:
	var out := {}
	for a in living:
		if not a.is_dead:
			out[a.agent_name] = true
	return out

func _refresh(agents: Array, settlement_system) -> void:
	var camp_ideas := {}   # camp id -> true if a living member knows MYTH_IDEA (-1: anyone)
	for a in agents:
		if a.is_dead:
			continue
		var p := _person(a, 1)
		p["partner"] = a.bonded_partner_id if a.bonded_partner_id >= 0 else int(p["partner"])
		if settlement_system:
			var st = settlement_system.get_settlement_for_agent(a.agent_id)
			p["camp"] = int(st.id) if st else -1
			p["camp_name"] = str(st.name) if st else ""
		if a.knowledge.has(MYTH_IDEA):
			camp_ideas[int(p["camp"])] = true
			camp_ideas[-1] = true
	var alive := {}
	for a in agents:
		if not a.is_dead:
			alive[a.agent_id] = true
	for lid in legends:
		var l: Dictionary = legends[lid]
		if l["faded"] or l["myth"]:
			continue
		var anyone := false
		for k in l["knew"]:
			if alive.has(k):
				anyone = true
				break
		if anyone:
			continue
		if camp_ideas.has(int(l["camp"])):
			l["myth"] = true
			_emit({"kind": "myth", "id": lid, "name": l["name"], "deed": l["deed"], "camp_name": l["camp_name"]})
		else:
			l["faded"] = true
			_emit({"kind": "faded", "id": lid, "name": l["name"], "deed": l["deed"], "camp_name": l["camp_name"]})

## The legend this elder would tell now (least told first), or -1.
func _legend_for(a: Agent) -> int:
	var camp := int((people.get(a.agent_id, {}) as Dictionary).get("camp", -1))
	var best := -1
	for lid in legends:
		var l: Dictionary = legends[lid]
		if l["faded"] or (int(l["camp"]) >= 0 and int(l["camp"]) != camp):
			continue
		if not (l["myth"] or (l["knew"] as Dictionary).has(a.agent_id) or (l["heard"] as Dictionary).has(a.agent_id)):
			continue
		if best < 0 or int(l["told"]) < int(legends[best]["told"]) or (int(l["told"]) == int(legends[best]["told"]) and int(lid) < best):
			best = int(lid)
	return best

func _tell(a: Agent, lid: int, agents: Array) -> void:
	var l: Dictionary = legends[lid]
	var line := legend_line(a.agent_id, lid)
	a.say(line, TELL_SECONDS)
	var heard: Array = []
	for o in agents:
		if o == a or o.is_dead or o.state == Agent.State.SLEEPING or o.pos.distance_to(a.pos) > HEAR_RADIUS:
			continue
		(l["heard"] as Dictionary)[o.agent_id] = true
		o.heard_legend = line
		_echo[o.agent_id] = ECHO_SECONDS
		heard.append(o.agent_id)
	if heard.is_empty():
		# Nobody to tell: they keep it for another evening.
		a.speech_bubble = ""
		a.speech_bubble_timer = 0.0
		return
	_emit({"kind": "told", "teller_id": a.agent_id, "teller": a.agent_name, "legend_id": lid,
		"legend": l["name"], "deed": l["deed"], "line": line, "pos": a.pos, "first": int(l["told"]) == 0,
		"heard": heard, "at_fire": a.at_fire})
	l["told"] = int(l["told"]) + 1

func _fade_echoes(delta: float, agents: Array) -> void:
	var done: Array = []
	for id in _echo:
		_echo[id] = float(_echo[id]) - delta
		if float(_echo[id]) <= 0.0:
			done.append(id)
	for id in done:
		_echo.erase(id)
		for a in agents:
			if a.agent_id == id:
				a.heard_legend = ""
				break
