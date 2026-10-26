class_name CultureSystem
extends RefCounted
## Camps with their own character, and camps meeting (docs/features/cultures.md).
##
## - Every settlement gets a Culture (dye, roofs, decoration, layout, food,
##   craft, name style): fresh from the world seed and its id, or a daughter's
##   copy of her mother's that drifts.
## - People visit a neighbouring camp's evening fire; now and then a visitor
##   and someone there pair up. A couple from two camps is a wedding between
##   camps: one moves (with their young children) and brings the ideas they
##   carry, which the new camp now knows.
## - Rarely two neighbouring camps fall out over the land between them. A feud
##   is grumbling, no visits, shoving matches (ConflictSystem; nobody dies). It
##   is always mended: in a few days, sooner with diplomacy, or by a wedding.
## - A crowded camp (or one that quarrels within) splits: a family and a few
##   others walk off and found a daughter camp in their mother's style.
##
## Runs on a slow cadence (every INTERVAL game seconds; daily things once a day).
## Returns story events for Main to hand to StoryKeeper.on_culture:
## {kind, text, pos, ids, major, moment, life: {agent_id: text}}.

const INTERVAL := 2.0
const VISIT_RANGE := 34.0          # tiles between hearths for a visit
const VISITS_PER_DAY := 0.6        # chance a day, for each pair of neighbours
const SPARK_CHANCE := 0.3          # a visit ends with the visitor paired up
const FEUD_RANGE := 26.0
const FEUD_PER_DAY := 0.03         # chance a day for each pair of neighbours (x2 on lean land)
const MAX_FEUDS := 1
const FEUD_COOLDOWN_DAYS := 6
const FEUD_MAX_DAYS := 5
const SPLIT_SIZE := 16             # a camp this big may split
const SPLIT_PER_DAY := 0.5
const QUARREL_SIZE := 9
const QUARREL_SPLIT_PER_DAY := 0.03
const SPLIT_COOLDOWN_DAYS := 3
const DAUGHTER_MIN := 13.0
const DAUGHTER_MAX := 24.0
const DRIFT_PER_DAY := 0.3
const STABLE_NIGHTS := 2           # nights at one camp before it counts as home for a wedding
const GRUMBLE_PER_SEC := 0.15     # a grumble a side, about one every 7 game seconds

var world: World = null
var settlement_system = null       # SettlementSystem
var concepts: Dictionary = {}      # ConceptGraph.concepts, for idea names

var home_of: Dictionary = {}       # agent_id -> settlement id they last slept at
var birth_of: Dictionary = {}      # agent_id -> settlement id born in (-2: came ashore)
var camp_names: Dictionary = {}    # settlement id -> name (kept after a camp is gone)
var feuds: Dictionary = {}         # "lo:hi" -> {a, b, start, reason}
var visits: Dictionary = {}        # agent_id -> {from, to, day}

# Counters (tools/balance.gd reports them).
var cross_marriages := 0
var ideas_carried := 0
var daughters := 0
var feuds_started := 0
var feuds_mended := 0
var visits_made := 0
var sparks := 0                    # visits that ended in a pairing

var _timer := 0.0
var _last_day := -1
var _started := false
var _wed: Dictionary = {}          # "lo:hi" couples already handled
var _feud_cool: Dictionary = {}    # "lo:hi" -> day a new feud may start
var _split_cool: Dictionary = {}   # settlement id -> day it may split again
var _water: Dictionary = {}        # settlement id -> [centre, near water]
var _nights: Dictionary = {}       # agent_id -> [settlement id, nights slept there in a row, last night]
var _last_wedding_day := -1
var _crafts_told: Dictionary = {}  # crafts some camp is already known for

func tick(delta: float, agents: Array, day: int, hour: float) -> Array:
	var out: Array = []
	if settlement_system == null:
		return out
	_timer += delta
	var new_day := day != _last_day
	if _timer < INTERVAL and not new_day:
		return out
	var dt := _timer
	_timer = 0.0
	var by_id: Dictionary = {}
	for a: Agent in agents:
		if not a.is_dead:
			by_id[a.agent_id] = a
	var settlements: Array = settlement_system.get_settlements()
	_ensure_cultures(settlements, out)
	_note_people(agents, by_id, day, hour)
	_marriages(agents, by_id, day, out)
	_end_visits(by_id, day, hour, out)
	_grumble(by_id, dt, hour)
	if new_day:
		_last_day = day
		if _started:
			_mend_feuds(day, out)
			_start_feuds(day, out)
			_start_visits(by_id, day)
			_splits(by_id, day, out)
			_drift()
		_started = true
	return out

# ── Cultures ─────────────────────────────────────────────────────────────────

func _ensure_cultures(settlements: Array, out: Array) -> void:
	var used := {"dye": [], "roof": [], "deco": []}
	for s in settlements:
		if s.culture != null and (s.culture as Culture).generation == 0:
			_note_used(used, s.culture)
	for s in settlements:
		camp_names[s.id] = s.name
		if s.culture == null:
			var c := Culture.make(world.seed_val if world else 0, int(s.id), used)
			_note_used(used, c)
			s.culture = c
		var cul: Culture = s.culture
		var changed := cul.refresh(s.knowledge_pool, _near_water(s))
		if changed.has("craft") and cul.has_own_craft():
			# Big news the first time a craft makes a camp's name; after that, the camp's own.
			var first := not _crafts_told.has(cul.craft)
			_crafts_told[cul.craft] = true
			out.append(_evt("world", "%s has become known for its %s." % [s.name, cul.craft], s.centre, [], first))
	for id in _water.keys():
		if settlement_system.get_settlement_for_id(int(id)) == null:
			_water.erase(id)
			_split_cool.erase(id)

static func _note_used(used: Dictionary, c: Culture) -> void:
	used["dye"].append(c.dye_i)
	used["roof"].append(c.roof_i)
	used["deco"].append(c.deco_i)

func _near_water(s) -> bool:
	var e: Array = _water.get(s.id, [])
	if e.is_empty() or (e[0] as Vector2).distance_to(s.centre) > 0.5:
		var wet := true
		if world:
			wet = not world.find_nearest(s.centre.x, s.centre.y, [World.TileType.WATER, World.TileType.BEACH], 10.0).is_empty()
		e = [s.centre, wet]
		_water[s.id] = e
	return bool(e[1])

func culture_of(settlement_id: int) -> Culture:
	var s = settlement_system.get_settlement_for_id(settlement_id) if settlement_system else null
	return s.culture if s else null

## Daughters drift away from their mothers, a little at a time.
func _drift() -> void:
	for s in settlement_system.get_settlements():
		var c: Culture = s.culture
		if c and c.generation > 0 and randf() < DRIFT_PER_DAY:
			c.drift(0.02 if randf() < 0.5 else -0.02)

# ── Who lives where, who was born where ──────────────────────────────────────

func _note_people(agents: Array, by_id: Dictionary, day: int, hour: float) -> void:
	var night := hour >= 21.0 or hour < 5.0
	var night_id := day if hour >= 21.0 else day - 1
	for a: Agent in agents:
		if a.is_dead:
			continue
		var s = settlement_system.get_settlement_for_agent(a.agent_id)
		if not birth_of.has(a.agent_id):
			if not _started:
				birth_of[a.agent_id] = -2   # came ashore with the first forty
			else:
				var born := -1
				for pid in a.parents:
					if home_of.has(int(pid)):
						born = int(home_of[int(pid)])
						break
				if born < 0 and s:
					born = int(s.id)
				birth_of[a.agent_id] = born
				if born >= 0 and not home_of.has(a.agent_id):
					home_of[a.agent_id] = born
		if s == null or visits.has(a.agent_id):
			continue
		if not home_of.has(a.agent_id) or (night and a.night_sleeping) or settlement_system.is_pinned(a.agent_id):
			home_of[a.agent_id] = int(s.id)
		if night and a.night_sleeping:
			var rec: Array = _nights.get(a.agent_id, [-1, 0, -999])
			if int(rec[2]) != night_id:
				rec = [int(s.id), int(rec[1]) + 1 if int(rec[0]) == int(s.id) else 1, night_id]
				_nights[a.agent_id] = rec
	for id in home_of.keys():
		if not by_id.has(id):
			home_of.erase(id)
			_nights.erase(id)

## Settled: slept at their home camp STABLE_NIGHTS nights running (people
## drift between camps all the time; a wedding is between settled people).
func is_settled(agent_id: int) -> bool:
	var rec: Array = _nights.get(agent_id, [])
	return not rec.is_empty() and int(rec[1]) >= STABLE_NIGHTS and int(rec[0]) == int(home_of.get(agent_id, -2))

func home_name(agent_id: int) -> String:
	return str(camp_names.get(int(home_of.get(agent_id, -1)), ""))

## For the follow card: where they live and where they were born.
func card_line(a: Agent) -> String:
	if a == null:
		return ""
	var home := home_name(a.agent_id)
	var b := int(birth_of.get(a.agent_id, -1))
	var born := ""
	if b == -2:
		born = "came ashore with the first forty"
	elif b >= 0:
		var bn := str(camp_names.get(b, ""))
		if bn != "" and bn != home:
			born = "born in %s" % bn
		elif bn != "":
			born = "born here"
	var head := ("Of %s" % home) if home != "" else "No settled home"
	return head + (" · " + born if born != "" else "")

## The home camp's ways, for the follow card ("" when they have no home).
func card_culture(a: Agent) -> String:
	if a == null:
		return ""
	var c := culture_of(int(home_of.get(a.agent_id, -1)))
	return c.short() if c else ""

# ── Visits and weddings ──────────────────────────────────────────────────────

func _neighbours(range_tiles: float) -> Array:
	var out: Array = []
	var all: Array = settlement_system.get_settlements()
	for i in all.size():
		for j in range(i + 1, all.size()):
			var a = all[i]
			var b = all[j]
			if a.member_ids.size() < 3 or b.member_ids.size() < 3:
				continue
			if a.centre.distance_to(b.centre) <= range_tiles:
				out.append([a, b])
	return out

static func _key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]

func is_feuding(sid_a: int, sid_b: int) -> bool:
	return feuds.has(_key(sid_a, sid_b))

func _free_adult(a: Agent) -> bool:
	return a != null and not a.is_dead and a.is_adult and not a.is_elderly and a.bonded_partner_id < 0 \
		and a.mourning <= 0.0 and a.trader_state.is_empty() and not visits.has(a.agent_id)

## Once a day, a neighbour may walk over to sit at another camp's fire tonight.
func _start_visits(by_id: Dictionary, day: int) -> void:
	for pair in _neighbours(VISIT_RANGE):
		if is_feuding(pair[0].id, pair[1].id) or randf() >= VISITS_PER_DAY:
			continue
		var flip := randf() < 0.5
		var from = pair[1] if flip else pair[0]
		var to = pair[0] if flip else pair[1]
		var pick: Agent = null
		var ids: Array = from.member_ids.duplicate()
		ids.shuffle()
		for id in ids:
			var a: Agent = by_id.get(int(id))
			if _free_adult(a) and float(a.needs["hunger"]) > 0.4:
				pick = a
				break
		if pick == null:
			continue
		visits[pick.agent_id] = {"from": from.id, "to": to.id, "day": day}
		settlement_system.pin_member(pick.agent_id, to, day + 1)
		visits_made += 1

## The morning after: home they go, and maybe not alone in their heart.
func _end_visits(by_id: Dictionary, day: int, hour: float, out: Array) -> void:
	for id in visits.keys():
		var v: Dictionary = visits[id]
		if day <= int(v["day"]) or hour < 7.0:
			continue
		visits.erase(id)
		var a: Agent = by_id.get(int(id))
		var home = settlement_system.get_settlement_for_id(int(v["from"]))
		var host = settlement_system.get_settlement_for_id(int(v["to"]))
		if a == null:
			continue
		if home:
			settlement_system.pin_member(a.agent_id, home, day + 1)
			home_of[a.agent_id] = int(home.id)
		if host == null or not _free_adult(a) or randf() >= SPARK_CHANCE:
			continue
		var options: Array = []
		for mid in host.member_ids:
			var b: Agent = by_id.get(int(mid))
			if _free_adult(b) and int(home_of.get(b.agent_id, -1)) == int(host.id):
				options.append(b)
		if options.is_empty():
			continue
		var b: Agent = options[randi() % options.size()]
		a.bonded_partner_id = b.agent_id
		b.bonded_partner_id = a.agent_id
		sparks += 1
		# The wedding (who moves, what they bring) is _marriages' to tell.

## A couple from two camps: one moves to the other's, with their young
## children, and brings the ideas they carry.
func _marriages(agents: Array, by_id: Dictionary, day: int, out: Array) -> void:
	for a: Agent in agents:
		if a.is_dead or a.bonded_partner_id < 0 or a.agent_id > a.bonded_partner_id:
			continue
		var key := _key(a.agent_id, a.bonded_partner_id)
		if _wed.has(key):
			continue
		var b: Agent = by_id.get(a.bonded_partner_id)
		if b == null:
			continue
		var ha := int(home_of.get(a.agent_id, -1))
		var hb := int(home_of.get(b.agent_id, -1))
		if ha < 0 or hb < 0 or visits.has(a.agent_id) or visits.has(b.agent_id):
			continue
		if ha == hb:
			_wed[key] = true
			continue
		# Between settled people only, and one wedding a day across the island.
		if not is_settled(a.agent_id) or not is_settled(b.agent_id) or day == _last_wedding_day:
			continue
		_wed[key] = true
		_last_wedding_day = day
		var sa = settlement_system.get_settlement_for_id(ha)
		var sb = settlement_system.get_settlement_for_id(hb)
		if sa == null or sb == null:
			continue
		# The one from the bigger camp moves (it eases the crowding).
		var mover: Agent = a
		var stayer: Agent = b
		var from = sa
		var to = sb
		if sb.member_ids.size() > sa.member_ids.size():
			mover = b
			stayer = a
			from = sb
			to = sa
		out.append(wed(mover, stayer, from, to, agents, day))

## Move mover (and their young children) from one camp to another; returns the story.
func wed(mover: Agent, stayer: Agent, from, to, agents: Array, day: int) -> Dictionary:
	cross_marriages += 1
	var movers: Array = [mover]
	for c: Agent in agents:
		if not c.is_dead and not c.is_adult and mover.agent_id in c.parents \
				and int(home_of.get(c.agent_id, -1)) == int(from.id):
			movers.append(c)
	for m: Agent in movers:
		settlement_system.pin_member(m.agent_id, to, day + 2)
		home_of[m.agent_id] = int(to.id)
	var brought := _carry_ideas(mover, to)
	var kids := movers.size() - 1
	var with_kids := "" if kids == 0 else (" with their child" if kids == 1 else " with their %d children" % kids)
	var text := "%s of %s married %s of %s and moved there%s" % [mover.agent_name, from.name, stayer.agent_name, to.name, with_kids]
	text += (", bringing %s with them." % brought) if brought != "" else "."
	var evt := _evt("people", text, to.centre, [mover.agent_id, stayer.agent_id], brought != "" or cross_marriages <= 3)
	evt["moment"] = "wedding_camps"
	evt["note"] = "%s and %s: %s to %s" % [mover.agent_name, stayer.agent_name, from.name, to.name]
	evt["life"] = {
		mover.agent_id: "Married %s and moved from %s to %s." % [stayer.agent_name, from.name, to.name],
		stayer.agent_id: "Married %s of %s, who came to live in %s." % [mover.agent_name, from.name, to.name],
	}
	if is_feuding(from.id, to.id):
		var mended := _mend(_key(from.id, to.id), day, "a wedding between them")
		if not mended.is_empty():
			evt["then"] = mended
	return evt

## Ideas the mover knows that their new camp doesn't: the camp knows them now.
## Returns the name of the most advanced one ("" if none).
func _carry_ideas(mover: Agent, to) -> String:
	var best := ""
	var best_era := -1
	for k in mover.knowledge.keys():
		var id := str(k)
		if to.knowledge_pool.has(id):
			continue
		to.knowledge_pool[id] = true
		ideas_carried += 1
		var era := int((concepts.get(id, {}) as Dictionary).get("era", 0))
		if era > best_era or (era == best_era and id < best):
			best_era = era
			best = id
	if best == "":
		return ""
	return str((concepts.get(best, {}) as Dictionary).get("name", best.replace("_", " "))).to_lower()

# ── Feuds ────────────────────────────────────────────────────────────────────

const REASONS := ["the hazel thicket between them", "who found the berry patch first",
	"the best fishing rock", "a path one camp swore was theirs", "the spring both camps drink from",
	"a meadow both had been gathering in", "where one camp's land ends and the other's begins"]
const GRUMBLES := ["Hmph. %s folk.", "Not them again.", "That's OUR thicket.", "%s? Never heard of them.",
	"Don't look at the %s lot."]

func _start_feuds(day: int, out: Array) -> void:
	if feuds.size() >= MAX_FEUDS:
		return
	for pair in _neighbours(FEUD_RANGE):
		var a = pair[0]
		var b = pair[1]
		var key := _key(a.id, b.id)
		if feuds.has(key) or day < int(_feud_cool.get(key, 0)):
			continue
		var p := FEUD_PER_DAY
		if a.lean_days > 0 or b.lean_days > 0:
			p *= 2.0     # hungry land makes short tempers
		if _peaceful(a) or _peaceful(b):
			p *= 0.4
		if randf() >= p:
			continue
		var reason: String = REASONS[randi() % REASONS.size()]
		feuds[key] = {"a": a.id, "b": b.id, "start": day, "reason": reason}
		feuds_started += 1
		out.append(_evt("world", "%s and %s have fallen out over %s, and aren't speaking." % [a.name, b.name, reason],
			(a.centre + b.centre) * 0.5, [], true))
		return

static func _peaceful(s) -> bool:
	for id in ["diplomacy", "governance", "law"]:
		if s.knowledge_pool.has(id):
			return true
	return false

func _mend_feuds(day: int, out: Array) -> void:
	for key in feuds.keys():
		var f: Dictionary = feuds[key]
		var a = settlement_system.get_settlement_for_id(int(f["a"]))
		var b = settlement_system.get_settlement_for_id(int(f["b"]))
		if a == null or b == null:
			feuds.erase(key)
			continue
		var age := day - int(f["start"])
		var p := 0.15 + 0.2 * age
		var how := ""
		if _peaceful(a) or _peaceful(b):
			p += 0.3
			how = "talking it through, as people who know diplomacy do"
		elif SettlementRenderer.larder_fill(a) > 0.5 and SettlementRenderer.larder_fill(b) > 0.5:
			how = "sharing a feast from their full larders"
		else:
			how = ["deciding nobody could remember what it was about", "two of their children becoming fast friends",
				"a cold night that made them glad of neighbours", "splitting the difference down the middle"][randi() % 4]
		if age >= FEUD_MAX_DAYS or randf() < p:
			var e := _mend(key, day, how)
			if not e.is_empty():
				out.append(e)

func _mend(key: String, day: int, how: String) -> Dictionary:
	var f: Dictionary = feuds.get(key, {})
	if f.is_empty():
		return {}
	feuds.erase(key)
	_feud_cool[key] = day + FEUD_COOLDOWN_DAYS
	feuds_mended += 1
	var a = settlement_system.get_settlement_for_id(int(f["a"]))
	var b = settlement_system.get_settlement_for_id(int(f["b"]))
	if a == null or b == null:
		return {}
	var evt := _evt("world", "The quarrel between %s and %s over %s is mended, by %s." % [a.name, b.name, f["reason"], how],
		(a.centre + b.centre) * 0.5, [], true)
	evt["moment"] = "quarrel_mended"
	evt["note"] = "%s and %s, day %d" % [a.name, b.name, day]
	return evt

## People of feuding camps grumble about each other (speech only).
func _grumble(by_id: Dictionary, dt: float, hour: float) -> void:
	if feuds.is_empty() or hour < 8.0 or hour > 18.0:
		return
	for key in feuds:
		var f: Dictionary = feuds[key]
		for side in [["a", "b"], ["b", "a"]]:
			if randf() >= GRUMBLE_PER_SEC * dt:
				continue
			var s = settlement_system.get_settlement_for_id(int(f[side[0]]))
			var other = settlement_system.get_settlement_for_id(int(f[side[1]]))
			if s == null or other == null or s.member_ids.is_empty():
				continue
			var who: Agent = by_id.get(int(s.member_ids[randi() % s.member_ids.size()]))
			if who and who.is_adult and who.speech_bubble_timer <= 0.0:
				var line: String = GRUMBLES[randi() % GRUMBLES.size()]
				who.say(line % other.name if line.contains("%s") else line)

# ── Daughter camps ───────────────────────────────────────────────────────────

func _splits(by_id: Dictionary, day: int, out: Array) -> void:
	for s in settlement_system.get_settlements().duplicate():
		var n: int = s.member_ids.size()
		if s.culture == null or s.moving_until_day >= 0 or day - int(s.founding_day) < 2 or day < int(_split_cool.get(s.id, 0)):
			continue
		var why := ""
		if n >= SPLIT_SIZE and randf() < SPLIT_PER_DAY:
			why = "crowded"
		elif n >= QUARREL_SIZE and randf() < QUARREL_SPLIT_PER_DAY:
			why = "quarrel"
		if why == "":
			continue
		var site := _daughter_site(s)
		if site.x < 0.0:
			_split_cool[s.id] = day + 1
			continue
		var group := _split_group(s, by_id, clampi(int(n / 3.0), 4, 7))
		if group.size() < SettlementSystem.FOUNDING_GROUP:
			continue
		var taken: Dictionary = {}
		for o in settlement_system.get_settlements():
			taken[o.name] = true
		var mother_c: Culture = s.culture
		var d_name := mother_c.daughter_name(str(s.name), taken)
		var ids: Array = group.map(func(g): return g.agent_id)
		var d = settlement_system.found_camp(ids, site, day, d_name)
		d.knowledge_pool = s.knowledge_pool.duplicate()
		d.culture = Culture.daughter_of(mother_c, int(d.id), int(s.id), str(s.name))
		(d.culture as Culture).refresh(d.knowledge_pool, _near_water(d))
		var share := float(group.size()) / float(maxi(1, n))
		d.food_store = s.food_store * share
		s.food_store -= d.food_store
		d.wood_store = s.wood_store * share
		s.wood_store -= d.wood_store
		for g: Agent in group:
			home_of[g.agent_id] = int(d.id)
		camp_names[d.id] = d.name
		_split_cool[s.id] = day + SPLIT_COOLDOWN_DAYS
		_split_cool[d.id] = day + SPLIT_COOLDOWN_DAYS * 2
		daughters += 1
		var leader: Agent = group[0]
		var cause := "%s had grown crowded" % s.name if why == "crowded" else "a quarrel round the %s fire" % s.name
		var text := "After %s, %s and %d others walked %s and founded %s, a daughter of %s." % [
			cause, leader.agent_name, group.size() - 1, SettlementSystem._heading(site - s.centre), d.name, s.name]
		var evt := _evt("world", text, site, [leader.agent_id], true)
		evt["moment"] = "new_camp"
		evt["note"] = "%s, from %s, day %d" % [d.name, s.name, day]
		var life := {}
		for g: Agent in group:
			life[g.agent_id] = "Left %s to help found %s." % [s.name, d.name]
		evt["life"] = life
		out.append(evt)
		return   # one a day across the island

## Good land a walk away, not crowding anyone.
func _daughter_site(s) -> Vector2:
	if world == null:
		return Vector2(-1, -1)
	var best := Vector2(-1, -1)
	var best_food := 0.25
	for i in 16:
		var a := randf() * TAU
		var r := randf_range(DAUGHTER_MIN, DAUGHTER_MAX)
		var c: Vector2 = s.centre + Vector2(cos(a), sin(a)) * r
		if not world.is_walkable(c.x, c.y):
			continue
		var crowded := false
		for o in settlement_system.get_settlements():
			if o.centre.distance_to(c) < SettlementSystem.FOUNDING_SPACING:
				crowded = true
				break
		if crowded:
			continue
		var f: float = settlement_system.food_around(c, 4)
		if f > best_food:
			best_food = f
			best = c
	return best

## A family to lead it (a couple and their children), then a few others.
func _split_group(s, by_id: Dictionary, want: int) -> Array:
	var adults: Array = []
	for id in s.member_ids:
		var a: Agent = by_id.get(int(id))
		if a and a.is_adult and a.trader_state.is_empty() and not visits.has(a.agent_id) \
				and int(home_of.get(a.agent_id, -1)) == int(s.id):
			adults.append(a)
	if adults.size() < want + 3:
		return []
	adults.shuffle()
	# Prefer a couple to lead.
	adults.sort_custom(func(x, y): return int(x.bonded_partner_id >= 0) > int(y.bonded_partner_id >= 0))
	var group: Array = []
	var taken: Dictionary = {}
	var add := func(a: Agent) -> void:
		if a and not taken.has(a.agent_id):
			taken[a.agent_id] = true
			group.append(a)
	for a: Agent in adults:
		if group.size() >= want:
			break
		if taken.has(a.agent_id):
			continue
		var family: Array = [a]
		if a.bonded_partner_id >= 0 and s.member_ids.has(a.bonded_partner_id):
			family.append(by_id.get(a.bonded_partner_id))
		for cid in a.children:
			var c: Agent = by_id.get(int(cid))
			if c and not c.is_adult and s.member_ids.has(c.agent_id):
				family.append(c)
		if not group.is_empty() and group.size() + family.size() > want + 1:
			continue   # too many: another family goes instead
		for m in family:
			add.call(m)
	return group

# ── Helpers ──────────────────────────────────────────────────────────────────

static func _evt(kind: String, text: String, pos: Vector2, ids: Array, major: bool) -> Dictionary:
	return {"kind": kind, "text": text, "pos": pos, "ids": ids, "major": major, "moment": "", "note": "", "life": {}}
