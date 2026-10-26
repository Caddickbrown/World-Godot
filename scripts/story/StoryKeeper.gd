class_name StoryKeeper
extends RefCounted
## Turns what happens in the simulation into the things the player collects:
## the chronicle, a story for every life, the idea ledger, moments and hunches.
##
## Pillar 1: this only READS the simulation. Main calls the on_* hooks with
## events it already handles; tick() looks at agents but never writes to them.
## The one outward call is witness_fn, which asks Main whether the player could
## see a place (to unlock moments).

signal chronicle_added(entry: Dictionary)
signal moment_unlocked(id: String, title: String)

const KINDS := ["people", "ideas", "world"]
const RECOUNT_INTERVAL := 2.0   # game seconds between living-holder recounts
const TEACHER_THRESHOLD := 10
const MAX_CHRONICLE := 300
const FIRE_CIRCLE := 6          # people round one evening fire for the moment
const FED_TO_TELL := 5          # meals given to hungry children before it's in their story

var chronicle: Array = []       # {day, hour, kind, text, pos, agent_ids}
var lives: Dictionary = {}      # agent_id -> life record (see _life)
var ledger := IdeaLedger.new()
var moments := Moments.new()
var hunches := Hunches.new()
var concepts: Dictionary = {}

## Callable(tile_pos: Vector2, agent_ids: Array) -> bool. Unset = always seen.
var witness_fn: Callable = Callable()
var day := 1
var hour := 8.0

var _recount_timer := 0.0
var _recently_dead: Array = []
var _partner_seen: Dictionary = {}   # agent_id -> partner id we've already told
var _founders: Dictionary = {}       # agent_id -> true
var _founders_left := 0
var _seen_year := false
var _hunts := 0
var _fed_told: Dictionary = {}       # agent_id -> true once their caring is told

func setup(concept_graph: ConceptGraph, agents: Array, album_path: String = "user://world_album.json") -> void:
	concepts = concept_graph.concepts
	ledger.setup(concepts)
	moments.save_path = album_path
	moments.load_album()
	var saved := _load_extra()
	hunches.glimmers = int(saved.get("glimmers", 0))
	hunches.called = int(saved.get("called", 0))
	for a in agents:
		_founders[a.agent_id] = true
		_life(a).founder = true
	_founders_left = agents.size()
	add("people", "%d strangers woke on the shore." % agents.size(), Vector2(-1, -1), [])

# ── Hooks from Main ──────────────────────────────────────────────────────────

func on_birth(child: Agent, parent_a: Agent, parent_b: Agent) -> void:
	var life := _life(child)
	var pnames: Array = []
	for p in [parent_a, parent_b]:
		if p:
			pnames.append(p.agent_name)
			var pl := _life(p)
			pl.children.append(child.agent_name)
			_event(p, "%s was born." % child.agent_name, "people")
	life.parents = pnames
	life.events.append({"day": day, "text": "Born to %s." % " and ".join(pnames) if not pnames.is_empty() else "Born.", "kind": "people"})
	var who := " and ".join(pnames) if not pnames.is_empty() else "Someone"
	add("people", "%s had a child, %s." % [who, child.agent_name], child.pos, [child.agent_id] + _ids([parent_a, parent_b]), false)
	_try_moment("birth", child.pos, [child.agent_id], "%s, born day %d" % [child.agent_name, day])

func on_death(a: Agent) -> void:
	var life := _life(a)
	life.died_day = day
	life.cause = a.death_cause
	life.last_line = last_line(a)
	var phrase := _death_phrase(a.death_cause, a.agent_id)
	life.events.append({"day": day, "text": phrase.left(1).to_upper() + phrase.substr(1) + ".", "kind": "people"})
	_recently_dead.append(a)
	add("people", life.last_line, a.pos, [a.agent_id], not life.firsts.is_empty() or life.total_taught() >= 5 or _founders_left <= 1)
	if a.death_cause == "old_age":
		_try_moment("long_life", a.pos, [a.agent_id], life.last_line)
	if _founders.has(a.agent_id):
		_founders_left -= 1
		if _founders_left == 0:
			_try_moment("last_founder", a.pos, [a.agent_id], "%s, day %d" % [a.agent_name, day])

func on_discovery(a: Agent, concept_id: String) -> void:
	var how := ledger.note_discovery(concept_id, a.agent_name, day)
	var cname := ledger.name_of(concept_id).to_lower()
	var life := _life(a)
	if how["first"]:
		life.firsts.append(concept_id)
		_event(a, "Was the first to think of %s." % cname, "ideas")
		add("ideas", "%s was the first to think of %s." % [a.agent_name, cname], a.pos, [a.agent_id])
		_try_moment("first_idea", a.pos, [a.agent_id], "%s: %s" % [a.agent_name, cname])
		var special := {"fire": "first_fire", "language": "first_words", "sailing": "first_crossing",
			"agriculture": "first_harvest", "oral_tradition": "first_story"}
		if special.has(concept_id):
			_try_moment(special[concept_id], a.pos, [a.agent_id], "%s, day %d" % [a.agent_name, day])
	elif how["refound"]:
		_event(a, "Found %s again, long after it was lost." % cname, "ideas")
		add("ideas", "%s is known again: %s worked it out anew." % [cname.left(1).to_upper() + cname.substr(1), a.agent_name], a.pos, [a.agent_id])
		ledger.ideas[concept_id]["stage"] = IdeaLedger.Stage.SPROUT
		_try_moment("idea_refound", a.pos, [a.agent_id], "%s, by %s" % [cname, a.agent_name])
	else:
		_event(a, "Worked out %s." % cname, "ideas")
	for h in hunches.on_discovery(concept_id, a.agent_name, how["refound"], how["first"], day):
		_tell_hunch(h)

func on_spread(learner: Agent, teacher: Agent, concept_id: String) -> void:
	ledger.note_taught(concept_id)
	if teacher == null:
		return
	var tl := _life(teacher)
	tl.taught[concept_id] = int(tl.taught.get(concept_id, 0)) + 1
	var n: int = tl.taught[concept_id]
	if n == TEACHER_THRESHOLD:
		var cname := ledger.name_of(concept_id).to_lower()
		_event(teacher, "Has taught %s to %d people." % [cname, n], "ideas")
		add("ideas", "%s has taught %s to %d people." % [teacher.agent_name, cname, n], teacher.pos, [teacher.agent_id])
		_try_moment("teacher", teacher.pos, [teacher.agent_id], "%s: %s" % [teacher.agent_name, cname])
	if learner and tl.taught.size() == 1 and n == 1:
		_event(teacher, "Taught %s to %s, the first idea they passed on." % [ledger.name_of(concept_id).to_lower(), learner.agent_name], "ideas")

var _fellings := 0
var _plantings := 0
var _replanted := false

func on_hunt(hunter: Agent, prey_type: int, shared: int) -> void:
	var prey := HuntingSystem.prey_name(prey_type)
	var line := "Brought down %s%s." % [prey, (" and shared it with %d" % shared) if shared > 0 else ""]
	_event(hunter, line, "people")
	_hunts += 1
	if _hunts == 1:
		add("people", "%s brought down %s: the first hunt." % [hunter.agent_name, prey], hunter.pos, [hunter.agent_id])
		_try_moment("first_hunt", hunter.pos, [hunter.agent_id], "%s, day %d" % [hunter.agent_name, day])
	else:
		add("people", "%s brought down %s%s." % [hunter.agent_name, prey, (", and %d ate well" % shared) if shared > 1 else ""], hunter.pos, [hunter.agent_id], false)

## ForestSystem events: {kind: felled|replanted|planted, who, tile}.
func on_forest(evt: Dictionary) -> void:
	var who: Agent = evt["who"]
	var t: Vector2i = evt["tile"]
	var pos := Vector2(t.x + 0.5, t.y + 0.5)
	match str(evt["kind"]):
		"felled", "replanted":
			_event(who, "Felled a tree for timber%s." % (" and planted another" if evt["kind"] == "replanted" else ""), "people")
			_fellings += 1
			if _fellings == 1:
				add("people", "%s felled a tree for timber: the first axe in the woods." % who.agent_name, pos, [who.agent_id])
				_try_moment("first_felling", pos, [who.agent_id], "%s, day %d" % [who.agent_name, day])
			if evt["kind"] == "replanted" and not _replanted:
				_replanted = true
				add("people", "%s felled a tree and planted a sapling in its place." % who.agent_name, pos, [who.agent_id])
		"planted":
			_event(who, "Planted a tree near home.", "people")
			_plantings += 1
			if _plantings == 1:
				add("people", "%s planted a tree they may never sit under." % who.agent_name, pos, [who.agent_id])
				_try_moment("planted", pos, [who.agent_id], "%s, day %d" % [who.agent_name, day])
			elif _plantings % 10 == 0:
				add("people", "A planted grove is coming up round %s's home." % who.agent_name, pos, [who.agent_id], false)

var _breaches := 0
var _honey_eaters: Dictionary = {}   # agent_id -> true once it's in their story

## AmbientLife events: {kind: breach|chorus|honey, pos (tile), agent_id?}.
## Whales and frogs only unlock moments (the chronicle hears of the first
## breach); honey is a person's doing, so it goes in their story.
func on_wild(evt: Dictionary, agents: Array = []) -> void:
	var pos: Vector2 = evt.get("pos", Vector2(-1, -1))
	match str(evt.get("kind", "")):
		"breach":
			_breaches += 1
			if _breaches == 1:
				add("world", "A whale breached off the coast, the first anyone saw.", pos, [], false)
			_try_moment("whale_breach", pos, [], "day %d" % day)
		"chorus":
			_try_moment("frog_chorus", pos, [], "day %d" % day)
		"honey":
			var id := int(evt.get("agent_id", -1))
			var who: Agent = _find(agents, id)
			if who == null or _honey_eaters.has(id):
				return
			_honey_eaters[id] = true
			_event(who, "Ate wild honey from a bees' nest.", "people")
			if _honey_eaters.size() == 1:
				add("people", "%s found a bees' nest in the woods and ate the honey." % who.agent_name, pos, [id])
			_try_moment("wild_honey", pos, [id], "%s, day %d" % [who.agent_name, day])

func on_grief(mourner: Agent, dead: Agent, relation: String) -> void:
	var what: String = {"partner": "their partner", "parent": "their parent", "child": "their child"}.get(relation, "someone close")
	_event(mourner, "Lost %s, %s." % [what, dead.agent_name], "people")

## FestivalSystem events: {kind: began|gathered|ongoing|ended, festival, pos,
## ids, text?, major?, moment?, note?, life?, people?}. Told once the camp has
## gathered; the album moment can be had any time while it lasts.
func on_festival(evt: Dictionary) -> void:
	var pos: Vector2 = evt.get("pos", Vector2(-1, -1))
	var ids: Array = evt.get("ids", [])
	if str(evt.get("text", "")) != "":
		add("people", str(evt["text"]), pos, ids, bool(evt.get("major", true)))
	for a in evt.get("people", []):
		_event(a, str(evt.get("life", "")), "people")
	if str(evt.get("moment", "")) != "" and not ids.is_empty():
		_try_moment(str(evt["moment"]), pos, ids, str(evt.get("note", "")))

## World events (weather, fire, settlements). moment: optional moment id.
func on_world(text: String, pos: Vector2 = Vector2(-1, -1), moment: String = "") -> void:
	add("world", text, pos, [])
	if moment != "":
		_try_moment(moment, pos, [], "day %d: %s" % [day, text])

## CultureSystem events (feat/cultures): weddings between camps, feuds and
## their mending, daughter camps. {kind, text, pos, ids, major, moment, note,
## life: {agent_id: text}, then: a follow-on event}.
func on_culture(evt: Dictionary, agents: Array = []) -> void:
	add(str(evt["kind"]), str(evt["text"]), evt["pos"], evt["ids"], bool(evt["major"]))
	var life: Dictionary = evt.get("life", {})
	for id in life:
		var who: Agent = _find(agents, int(id))
		if who:
			_event(who, str(life[id]), "people")
	if str(evt.get("moment", "")) != "":
		_try_moment(str(evt["moment"]), evt["pos"], evt["ids"], str(evt.get("note", "")))
	if evt.has("then"):
		on_culture(evt["then"], agents)

## Player-side moments (zoomed out, walked, listened).
func on_player(moment: String, note: String = "") -> void:
	_try_moment(moment, Vector2(-1, -1), [], note if note != "" else "day %d" % day)

## Called every frame with the simulated delta; reads agents only.
func tick(game_delta: float, agents: Array, p_day: int, p_hour: float, alive: int) -> void:
	var new_day := p_day != day
	day = p_day
	hour = p_hour
	# Pairings: the sim sets bonded_partner_id silently; notice it once.
	for a in agents:
		if a.is_dead or a.bonded_partner_id < 0:
			continue
		if int(_partner_seen.get(a.agent_id, -1)) == a.bonded_partner_id:
			continue
		_partner_seen[a.agent_id] = a.bonded_partner_id
		if a.agent_id > a.bonded_partner_id:
			continue  # tell each pair once, from the lower id
		var b: Agent = _find(agents, a.bonded_partner_id)
		if b == null:
			continue
		_partner_seen[b.agent_id] = a.agent_id
		_life(a).partner = b.agent_name
		_life(b).partner = a.agent_name
		_event(a, "Paired up with %s." % b.agent_name, "people")
		_event(b, "Paired up with %s." % a.agent_name, "people")
		add("people", "%s and %s have paired up." % [a.agent_name, b.agent_name], a.pos, [a.agent_id, b.agent_id], false)
		_try_moment("pairing", a.pos, [a.agent_id, b.agent_id], "%s and %s" % [a.agent_name, b.agent_name])

	_recount_timer += game_delta
	if _recount_timer >= RECOUNT_INTERVAL:
		_recount_timer = 0.0
		for c in ledger.recount(agents, day, _recently_dead):
			if int(c["to"]) == IdeaLedger.Stage.WILTED:
				var cname := ledger.name_of(c["id"])
				var who: String = c["last_holder"]
				add("ideas", ("%s is forgotten: %s was the last who knew it." % [cname, who]) if who != ""
					else "%s is forgotten. No one alive remembers it." % cname, Vector2(-1, -1), [])
				_try_moment("idea_lost", Vector2(-1, -1), [], cname)
		_recently_dead.clear()
		if ledger.count_in(IdeaLedger.Stage.BLOOM) + ledger.count_in(IdeaLedger.Stage.SPROUT) >= 10:
			_try_moment("ten_ideas", Vector2(-1, -1), [], "day %d" % day)
		hunches.offer(agents, ledger, concepts, day)
	if alive >= 100:
		_try_moment("hundred", Vector2(-1, -1), [], "day %d" % day)
	# The evening fire, and the parents who kept their children fed.
	var at_fire: Array = []
	for a in agents:
		if a.is_dead:
			continue
		if a.at_fire:
			at_fire.append(a)
		if a.fed_children >= FED_TO_TELL and not _fed_told.has(a.agent_id):
			_fed_told[a.agent_id] = true
			_event(a, "Kept their children fed when food was short.", "people")
	if at_fire.size() >= FIRE_CIRCLE:
		_try_moment("fire_circle", at_fire[0].pos, at_fire.map(func(x): return x.agent_id), "day %d" % day)
	if day > TimeSystem.SEASON_DAYS * 4 and not _seen_year:
		_seen_year = true
		_try_moment("full_year", Vector2(-1, -1), [], "day %d" % day)
	if hour >= 23.5 or hour < 0.5:
		_try_moment("night_watch", Vector2(-1, -1), [], "day %d" % day)
	if new_day:
		for h in hunches.on_day(day):
			_tell_hunch(h)

# ── Chronicle and lives ──────────────────────────────────────────────────────

## major: worth telling everyone (firsts, lost ideas, new places, notable
## lives). Minor entries (ordinary births, pairings, deaths) still go in the
## chronicle and in lives, but the HUD only shows them for people you follow.
func add(kind: String, text: String, pos: Vector2, agent_ids: Array, major: bool = true) -> Dictionary:
	var entry := {"day": day, "hour": hour, "kind": kind, "text": text, "pos": pos, "agent_ids": agent_ids, "major": major}
	chronicle.append(entry)
	if chronicle.size() > MAX_CHRONICLE:
		chronicle.pop_front()
	chronicle_added.emit(entry)
	return entry

## Newest first. focus_id: also include minor entries about this person.
func recent(kind: String = "all", count: int = 6, focus_id: int = -1) -> Array:
	var out: Array = []
	for i in range(chronicle.size() - 1, -1, -1):
		var e: Dictionary = chronicle[i]
		if not (bool(e.get("major", true)) or focus_id in (e["agent_ids"] as Array)):
			continue
		if kind == "all" or e["kind"] == kind:
			out.append(e)
			if out.size() >= count:
				break
	return out

func life_of(a: Agent) -> LifeRecord:
	return _life(a)

## The line a life ends on: "Orulen, who first thought of honey, died old."
func last_line(a: Agent) -> String:
	var life := _life(a)
	var epithet := ""
	if not life.firsts.is_empty():
		epithet = "who first thought of %s" % ledger.name_of(life.firsts[0]).to_lower()
	else:
		var best := ""
		var most := 0
		for id in life.taught:
			if int(life.taught[id]) > most:
				most = int(life.taught[id])
				best = id
		if most >= 3:
			epithet = "who taught %s to %d people" % [ledger.name_of(best).to_lower(), most]
		elif life.children.size() >= 2:
			epithet = "parent of %d" % life.children.size()
		elif life.partner != "":
			epithet = "%s's partner" % life.partner
		elif life.founder:
			epithet = "one of the first forty"
	var head := a.agent_name + (", " + epithet + "," if epithet != "" else "")
	return "%s %s." % [head, _death_phrase(a.death_cause, a.agent_id)]

## A few ways to say each, picked by who it is, so the chronicle doesn't drone.
const DEATH_PHRASES := {
	"old_age": ["died old, in the warmth of the camp", "lived a long life and slept away",
		"died with grandchildren close by", "grew old and was gone by morning"],
	"starvation": ["starved in a hungry season", "went hungry one winter too many",
		"could not find enough to eat"],
	"disease": ["was taken by fever", "fell sick and did not get up", "was carried off by the sickness"],
	"conflict": ["fell in a quarrel between camps", "was killed in a fight over food"],
	"wolf": ["was taken by a wolf, far from the fire", "went out alone and met a wolf"],
	"bear": ["was killed by a bear", "met a bear in the dark and did not come home"],
}

static func _death_phrase(cause: String, who: int = 0) -> String:
	var options: Array = DEATH_PHRASES.get(cause, ["is gone"])
	return options[posmod(who, options.size())]

func _life(a: Agent) -> LifeRecord:
	if not lives.has(a.agent_id):
		var l := LifeRecord.new()
		l.agent_id = a.agent_id
		l.name = a.agent_name
		l.born_day = day
		lives[a.agent_id] = l
	return lives[a.agent_id]

func _event(a: Agent, text: String, kind: String) -> void:
	_life(a).events.append({"day": day, "text": text, "kind": kind})

# ── Moments, hunches ─────────────────────────────────────────────────────────

func _try_moment(id: String, pos: Vector2, agent_ids: Array, note: String) -> void:
	if moments.is_unlocked(id):
		return
	if moments.needs_witness(id) and witness_fn.is_valid() and not bool(witness_fn.call(pos, agent_ids)):
		return
	if moments.unlock(id, day, note):
		moment_unlocked.emit(id, moments.name_of(id))
		_save()

func _tell_hunch(h: Dictionary) -> void:
	if str(h.get("pick", "")) == "":
		return
	var verdict := "You called it" if h["correct"] else "Not this time"
	add("world", "%s: %s (%s)." % [verdict, h["question"], h["answer"]], Vector2(-1, -1), [])
	_save()

func _save() -> void:
	moments.save_album({"glimmers": hunches.glimmers, "called": hunches.called})

func _load_extra() -> Dictionary:
	if not FileAccess.file_exists(moments.save_path):
		return {}
	var f := FileAccess.open(moments.save_path, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text()) if f else null
	return data if data is Dictionary else {}

static func _ids(people: Array) -> Array:
	var out: Array = []
	for p in people:
		if p:
			out.append(p.agent_id)
	return out

static func _find(agents: Array, id: int) -> Agent:
	for a in agents:
		if a.agent_id == id:
			return a
	return null

# ── Generations (feat/generations; see LineageTracker) ───────────────────────

var _four_gens := 0

## LineageTracker events: named, four_generations, legend, told, myth, faded.
func on_lineage(evt: Dictionary) -> void:
	var pos: Vector2 = evt.get("pos", Vector2(-1, -1))
	match str(evt.get("kind", "")):
		"named":
			var ns := int(evt["namesake_id"])
			var ns_name: String = lives[ns].name if lives.has(ns) else str(evt["child"])
			var line := ("A new baby is called %s, after a grandparent gone before they were born." % ns_name) \
				if evt["why"] == "grandparent" else ("A new baby is called %s, after the legend of %s." % [ns_name, evt["camp_name"] if str(evt["camp_name"]) != "" else "the island"])
			add("people", line, pos, [int(evt["child_id"])], false)
			if lives.has(int(evt["child_id"])):
				lives[int(evt["child_id"])].events.append({"day": day, "text": "Named for %s." % ns_name, "kind": "people"})
			if lives.has(ns):
				lives[ns].events.append({"day": day, "text": "%s was named for them." % evt["child"], "kind": "people"})
			_try_moment("named_for", pos, [int(evt["child_id"])], "%s, for %s" % [evt["child"], ns_name])
		"four_generations":
			_four_gens += 1
			add("people", "%s was born, and their great-grandparent %s is alive to see it: four generations." % [evt["child"], evt["elder"]],
				pos, [int(evt["child_id"]), int(evt["elder_id"])], _four_gens == 1)
			if lives.has(int(evt["elder_id"])):
				lives[int(evt["elder_id"])].events.append({"day": day, "text": "Lived to see a great-grandchild, %s." % evt["child"], "kind": "people"})
			_try_moment("four_generations", pos, [int(evt["child_id"]), int(evt["elder_id"])], "%s and %s" % [evt["elder"], evt["child"]])
		"legend":
			var camp: String = evt["camp_name"] if str(evt["camp_name"]) != "" else "the island"
			add("people", "%s, who %s, is one of the legends of %s now." % [evt["name"], evt["deed"], camp], pos, [int(evt["id"])])
			if lives.has(int(evt["id"])):
				lives[int(evt["id"])].events.append({"day": day, "text": "Became a legend of %s." % camp, "kind": "people"})
		"told":
			if lives.has(int(evt["teller_id"])) and bool(evt["first"]):
				lives[int(evt["teller_id"])].events.append({"day": day, "text": "Told the story of %s at the fire." % evt["legend"], "kind": "people"})
			if bool(evt["first"]):
				add("people", "%s, %s told the little ones about %s, who %s." % ["At the fire" if bool(evt.get("at_fire", true)) else "One evening", evt["teller"], evt["legend"], evt["deed"]],
					pos, [int(evt["teller_id"])], false)
			_try_moment("legend_told", pos, [int(evt["teller_id"])] + (evt.get("heard", []) as Array), "%s: \"%s\"" % [evt["teller"], evt["line"]])
		"myth":
			var camp2: String = evt["camp_name"] if str(evt["camp_name"]) != "" else "the island"
			add("ideas", "No one who knew %s is left, but %s still tells how they %s. %s is a myth now." % [evt["name"], camp2, evt["deed"], evt["name"]], Vector2(-1, -1), [int(evt["id"])])
			_try_moment("myth", Vector2(-1, -1), [int(evt["id"])], "%s, who %s" % [evt["name"], evt["deed"]])
		"faded":
			add("ideas", "No one is left who remembers %s, or how they %s." % [evt["name"], evt["deed"]], Vector2(-1, -1), [int(evt["id"])], false)

## Keep a life's page in the album, after this world is gone.
func press_life(agent_id: int, lineage: LineageTracker = null, world_seed: int = 0) -> bool:
	if not lives.has(agent_id):
		return false
	moments.press(PressedLife.page(lives[agent_id], ledger, lineage, world_seed, day))
	_try_moment("pressed_life", Vector2(-1, -1), [agent_id], lives[agent_id].name)
	_save()
	return true

func is_pressed(agent_id: int, world_seed: int = 0) -> bool:
	return moments.pressed_index(PressedLife.key(agent_id, world_seed)) >= 0
