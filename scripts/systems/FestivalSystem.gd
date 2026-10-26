class_name FestivalSystem
extends RefCounted
## The year's rhythm: days worth being there for, kept by camps that know
## enough to keep them. A camp that knows farming sows together in spring and
## eats the harvest at one long table in autumn; a camp with fire and some
## belief or art dances round a great fire on midsummer night; with stories,
## it hangs out lights on the longest night; with animism it gathers at the
## shrine each autumn to remember its dead.
##
## This is the simulation doing it (pillar 1: the player has no lever). Each
## festival pulls the camp's people (Agent.State.FESTIVAL) to a spot, moves
## the spot for dancing or sowing, and lets them go when it ends, hungry or
## tired. Those who were there come away in good spirits (Agent.ritual_morale);
## the harvest feast shares out the larder (food moved, never made).
##
## Sound and anything else can listen: festival_started(kind, pos) and
## festival_ended(kind, pos), pos in world metres on the ground (Main relays
## both, so a listener survives a new world). Story events go out through
## drain_events() (Main feeds them to StoryKeeper.on_festival).
##
## Cheap: the openings are checked once a game second against each camp (no
## map scans); only the people at a festival are touched each frame.

signal festival_started(kind: String, pos: Vector3)
signal festival_ended(kind: String, pos: Vector3)

const CHECK_INTERVAL := 1.0        # game seconds between openings/recruiting checks
const MIN_MEMBERS := 4             # smaller camps keep no festivals
const GATHER_RADIUS := 40.0        # tiles from the hearth people will come in from
const GATHERED_SHARE := 0.5        # of the camp there before it counts as held
const GATHERED_MIN := 3
const LEAVE_HUNGER := 0.15         # people go off to eat below this
const LEAVE_ENERGY := 0.08
const JOIN_HUNGER := 0.25          # ...and don't come above it (except to the feast)
const DANCE_RADIUS := 2.2          # tiles round the midsummer fire
const DANCE_SPEED := 0.45          # radians per game second round the ring
const RING_RADIUS := 2.0           # midwinter, seated round the fire
const MOURN_RADIUS := 1.7          # standing round the shrine
const SEAT_GAP := 0.55             # tiles between places at the harvest table
const FEAST_MEAL := 0.5            # most one person eats at the feast
const MAX_REMEMBERED := 8
const MORALE_ON_LEAVING := 0.5     # share of the lift for those who leave early

## Agent.festival_pose: how the renderer draws them.
const POSE_STAND := 0
const POSE_SIT := 1
const POSE_DANCE := 2

## Festivals held round a fire: those there count as at the fire (stories
## carry twice as far there, Agent._try_socialise).
const BY_THE_FIRE := ["midwinter"]

## kind -> season, day (0-based within the season), start/end hour, what the
## camp must know (all of `all`, and one of `any` if given), the morale lift
## (game seconds of Agent.ritual_morale) and the album moment.
const KINDS := {
	"planting":  {"name": "Spring sowing", "season": "Spring", "day": 1, "start": 7.0, "end": 10.5,
		"all": ["agriculture"], "any": [], "morale": 30.0, "pose": POSE_STAND, "moment": "fest_planting"},
	"midsummer": {"name": "Midsummer fire", "season": "Summer", "day": 3, "start": 19.0, "end": 23.5,
		"all": ["fire"], "any": ["animism", "ritual", "art", "music", "mythology"], "morale": 60.0,
		"pose": POSE_DANCE, "moment": "fest_midsummer"},
	"harvest":   {"name": "Harvest feast", "season": "Autumn", "day": 2, "start": 17.0, "end": 21.0,
		"all": ["agriculture"], "any": [], "morale": 50.0, "pose": POSE_SIT, "moment": "fest_harvest"},
	"mourning":  {"name": "Day of remembering", "season": "Autumn", "day": 5, "start": 16.0, "end": 19.0,
		"all": ["animism"], "any": [], "morale": 40.0, "pose": POSE_STAND, "moment": "fest_mourning"},
	"midwinter": {"name": "Midwinter lights", "season": "Winter", "day": 3, "start": 17.0, "end": 22.0,
		"all": ["fire"], "any": ["oral_tradition", "mythology"], "morale": 60.0, "pose": POSE_SIT,
		"moment": "fest_midwinter"},
}
const ORDER := ["planting", "midsummer", "harvest", "mourning", "midwinter"]

## Festivals under way: {id, kind, sid, place, centre, focus, yaw, start, end,
## people (Agent), slots {agent_id: slot}, n_slots, told, music, calendar,
## remembered (names), year}
var active: Array = []
var held_count := 0                 # festivals ever held (tests, balance)
var held_by_kind: Dictionary = {}   # kind -> times held (tools/balance.gd)
var _held: Dictionary = {}          # "sid:kind:year" -> true
var _dead: Dictionary = {}          # settlement id -> names who died since it last remembered
var _years: Dictionary = {}         # "sid:kind" -> times held
var _life_told: Dictionary = {}     # "agent_id:kind" -> true (once in each life story)
var _events: Array = []
var _timer := 0.0
var _next_id := 1
var _time := 0.0                    # game time now (for the dance)
var _world: World = null

# ── Calendar ─────────────────────────────────────────────────────────────────

## Days a camp without a calendar is off by (-1, 0 or +1, fixed per camp and
## festival, never rolled). With calendar (times_seasons) they keep the day.
static func day_shift(s, kind: String) -> int:
	if s.knowledge_pool.has("calendar"):
		return 0
	return posmod(int(s.id) * 7 + ORDER.find(kind) * 3, 3) - 1

## The day (1-based world day) this camp keeps `kind` in year `year` (0-based).
static func day_of(s, kind: String, year: int) -> int:
	var r: Dictionary = KINDS[kind]
	var si := TimeSystem.SEASONS.find(str(r["season"]))
	return year * TimeSystem.SEASON_DAYS * 4 + si * TimeSystem.SEASON_DAYS + int(r["day"]) + 1 + day_shift(s, kind)

static func year_of(day: int) -> int:
	return int((day - 1) / (TimeSystem.SEASON_DAYS * 4))

## Does this camp know enough to keep `kind`?
static func knows_for(s, kind: String) -> bool:
	var r: Dictionary = KINDS[kind]
	for id in r["all"]:
		if not s.knowledge_pool.has(id):
			return false
	var any: Array = r["any"]
	if any.is_empty():
		return true
	for id in any:
		if s.knowledge_pool.has(id):
			return true
	return false

## Is `kind` open for this camp now (right day, right hours, knows enough,
## not held yet this year)? Mourning also needs someone to remember.
func opens(s, kind: String, day: int, hour: float) -> bool:
	var r: Dictionary = KINDS[kind]
	if hour < float(r["start"]) or hour >= float(r["end"]) - 0.5:
		return false
	var year := year_of(day - day_shift(s, kind))
	if day != day_of(s, kind, year):
		return false
	if _held.has("%d:%s:%d" % [s.id, kind, year]):
		return false
	if not knows_for(s, kind):
		return false
	if kind == "mourning" and (_dead.get(s.id, []) as Array).is_empty():
		return false
	return true

# ── Tick ─────────────────────────────────────────────────────────────────────

func tick(delta: float, agents: Array, settlement_system, time_system: TimeSystem, world: World) -> void:
	_time = time_system.game_time
	_world = world
	for f in active:
		_drive(f)
	_timer += delta
	if _timer < CHECK_INTERVAL:
		return
	_timer = 0.0
	var by_id: Dictionary = {}
	if not active.is_empty():
		for a in agents:
			by_id[a.agent_id] = a
	var day := time_system.day
	var hour := time_system.hour
	for f in active.duplicate():
		var s = _settlement(settlement_system, int(f["sid"]))
		if s == null or _time >= float(f["end"]):
			_finish(f)
			continue
		_recruit(f, s, by_id)
		var there := _arrived(f)
		if not f["told"] and there >= maxi(GATHERED_MIN, int(ceil(s.member_ids.size() * GATHERED_SHARE))):
			_gathered(f, s)
		elif not f["told"] and there >= GATHERED_MIN and _time - float(f["start"]) > TimeSystem.DAY_LENGTH / 24.0 * 1.5:
			_gathered(f, s)
		if f["told"]:
			var r: Dictionary = KINDS[f["kind"]]
			_events.append({"kind": "ongoing", "festival": f["kind"], "pos": f["focus"], "ids": _ids(f),
				"moment": r["moment"], "note": "%s, %s, day %d" % [r["name"], f["place"], day]})
	for s in settlement_system.get_settlements():
		if s.member_ids.size() < MIN_MEMBERS or _running(s.id):
			continue
		for kind in ORDER:
			if opens(s, kind, day, hour):
				_start(kind, s, day, time_system)
				break

## Festivals coming up within `hours` (for the HUD's hints): [{kind, name, place, pos, hours}].
func upcoming(settlement_system, time_system: TimeSystem, hours: float = 2.0) -> Array:
	var out: Array = []
	var day := time_system.day
	var hour := time_system.hour
	for s in settlement_system.get_settlements():
		if s.member_ids.size() < MIN_MEMBERS or _running(s.id):
			continue
		for kind in ORDER:
			var r: Dictionary = KINDS[kind]
			var lead := float(r["start"]) - hour
			if lead <= 0.0 or lead > hours:
				continue
			if day != day_of(s, kind, year_of(day - day_shift(s, kind))) or not knows_for(s, kind):
				continue
			if _held.has("%d:%s:%d" % [s.id, kind, year_of(day - day_shift(s, kind))]):
				continue
			if kind == "mourning" and (_dead.get(s.id, []) as Array).is_empty():
				continue
			out.append({"kind": kind, "name": r["name"], "place": _place(s), "pos": _focus_for(kind, s), "hours": lead})
	return out

## Someone died: their camp will remember them on its next day of remembering.
func note_death(a, settlement_system) -> void:
	if settlement_system == null:
		return
	var s = settlement_system.get_settlement_for_agent(a.agent_id)
	if s == null:
		return
	var names: Array = _dead.get(s.id, [])
	if names.size() < MAX_REMEMBERED:
		names.append(a.agent_name)
	_dead[s.id] = names
	for f in active:
		var i: int = (f["people"] as Array).find(a)
		if i >= 0:
			(f["people"] as Array).remove_at(i)

func drain_events() -> Array:
	var out := _events
	_events = []
	return out

func festival_of(settlement_id: int) -> Dictionary:
	for f in active:
		if int(f["sid"]) == settlement_id:
			return f
	return {}

static func _settlement(settlement_system, sid: int):
	for s in settlement_system.get_settlements():
		if int(s.id) == sid:
			return s
	return null

func _running(sid: int) -> bool:
	return not festival_of(sid).is_empty()

# ── A festival's life ────────────────────────────────────────────────────────

func _start(kind: String, s, day: int, time_system: TimeSystem) -> void:
	var r: Dictionary = KINDS[kind]
	var year := year_of(day - day_shift(s, kind))
	_held["%d:%s:%d" % [s.id, kind, year]] = true
	held_count += 1
	held_by_kind[kind] = int(held_by_kind.get(kind, 0)) + 1
	var key := "%d:%s" % [s.id, kind]
	_years[key] = int(_years.get(key, 0)) + 1
	var end_time := time_system.game_time + (float(r["end"]) - time_system.hour) / 24.0 * TimeSystem.DAY_LENGTH
	var f := {"id": _next_id, "kind": kind, "sid": int(s.id), "place": _place(s), "centre": s.centre,
		"focus": _focus_for(kind, s), "yaw": _yaw(s), "start": time_system.game_time, "end": end_time,
		"people": [], "slots": {}, "n_slots": clampi(s.member_ids.size(), 4, 40), "told": false,
		"music": s.knowledge_pool.has("music"), "calendar": s.knowledge_pool.has("calendar"),
		"remembered": (_dead.get(s.id, []) as Array).duplicate(), "year": int(_years[key])}
	_next_id += 1
	active.append(f)
	festival_started.emit(kind, world_pos(f["focus"]))
	_events.append({"kind": "began", "festival": kind, "pos": f["focus"], "ids": []})

func _recruit(f: Dictionary, s, by_id: Dictionary) -> void:
	var people: Array = f["people"]
	for id in s.member_ids:
		var a = by_id.get(int(id))
		if a == null or people.has(a) or not _can_join(a, f):
			continue
		var slots: Dictionary = f["slots"]
		if not slots.has(a.agent_id):
			slots[a.agent_id] = slots.size()
		people.append(a)
		a.state = Agent.State.FESTIVAL
		a.festival = f["kind"]
		a.festival_pose = int(KINDS[f["kind"]]["pose"])
		a.festival_focus = f["focus"]
		a.target = _spot(f, int(slots[a.agent_id]))

func _can_join(a, f: Dictionary) -> bool:
	if a.is_dead or a.health <= 0.0 or a.state == Agent.State.SLEEPING or a.state == Agent.State.FESTIVAL:
		return false
	if a.trader_state != "" or a.afloat != "" or a.voyage:
		return false
	var hungry_ok: bool = a.needs["hunger"] > (0.05 if f["kind"] == "harvest" else JOIN_HUNGER)
	if not hungry_ok or a.needs["energy"] < 0.15:
		return false
	return a.pos.distance_to(f["centre"]) < GATHER_RADIUS

## How many are there yet (not just on their way).
static func _arrived(f: Dictionary) -> int:
	var r := maxf(4.0, float(f["n_slots"]) * 0.5 + 3.0)
	var focus: Vector2 = f["focus"]
	var n := 0
	for a in (f["people"] as Array):
		if a.pos.distance_to(focus) < r:
			n += 1
	return n

## Each frame, for those at the festival only: keep the dance going, let the
## hungry and the tired go, drop anyone something else has taken away.
func _drive(f: Dictionary) -> void:
	var people: Array = f["people"]
	var i := people.size() - 1
	while i >= 0:
		var a = people[i]
		if a.is_dead or a.state != Agent.State.FESTIVAL or a.festival != f["kind"]:
			if not a.is_dead and a.festival == f["kind"] and a.state != Agent.State.FESTIVAL:
				a.festival = ""
				a.festival_pose = POSE_STAND
			people.remove_at(i)
		elif a.needs["hunger"] < LEAVE_HUNGER or a.needs["energy"] < LEAVE_ENERGY:
			_release(a, f, MORALE_ON_LEAVING)
			people.remove_at(i)
		else:
			var kind: String = f["kind"]
			if kind == "midsummer" or kind == "planting":
				a.target = _spot(f, int(f["slots"].get(a.agent_id, 0)))
		i -= 1

## Where person `slot` belongs now.
func _spot(f: Dictionary, slot: int) -> Vector2:
	var focus: Vector2 = f["focus"]
	var n := maxi(1, int(f["n_slots"]))
	match str(f["kind"]):
		"midsummer":
			# Round the fire, the whole ring turning; the inner ring the other way.
			var ring := slot % 2
			var r := DANCE_RADIUS + 0.9 * ring
			var turn := (_time - float(f["start"])) * DANCE_SPEED * (1.0 if ring == 0 else -0.8)
			return focus + Vector2.from_angle(TAU * float(slot / 2) / ceilf(n / 2.0) + turn + 0.6 + 0.4 * ring) * r
		"midwinter":
			return focus + Vector2.from_angle(TAU * float(slot) / n + 0.3) * (RING_RADIUS + 0.5 * float(slot % 2))
		"mourning":
			# A crescent facing the shrine from the hearth side.
			var face := (f["centre"] - focus) as Vector2
			var base := face.angle() if face.length() > 0.01 else 0.0
			var spread := minf(PI * 1.2, 0.5 * n)
			return focus + Vector2.from_angle(base - spread * 0.5 + spread * (float(slot) + 0.5) / n) * (MOURN_RADIUS + 0.6 * float(slot % 2))
		"harvest":
			# Both sides of one long table.
			var along := Vector2.from_angle(float(f["yaw"]))
			var across := along.orthogonal()
			var per_side := int(ceil(n / 2.0))
			var k := slot / 2
			var x := (float(k) - (per_side - 1) * 0.5) * SEAT_GAP
			return focus + along * x + across * (0.55 if slot % 2 == 0 else -0.55)
		"planting":
			# In a line across the meadow, walking slowly up and down the rows.
			var along := Vector2.from_angle(float(f["yaw"]))
			var across := along.orthogonal()
			var sweep := sin((_time - float(f["start"])) * 0.12 + float(slot) * 0.3) * 2.4
			return focus + across * ((float(slot) - (n - 1) * 0.5) * 0.9) + along * sweep
	return focus

## The table's length in tiles (the renderer draws the same table).
static func table_length(f: Dictionary) -> float:
	return maxf(2.0, ceil(int(f["n_slots"]) / 2.0) * SEAT_GAP + 0.6)

## The camp has gathered: tell it, and (harvest) share out the larder.
func _gathered(f: Dictionary, s) -> void:
	f["told"] = true
	var kind: String = f["kind"]
	var r: Dictionary = KINDS[kind]
	if kind == "harvest":
		_feast(f, s)
	# The first of its kind each year is news everywhere; the rest go in the
	# chronicle for those who follow someone there.
	var told_key := "told:%s:%d" % [kind, year_of(_world.day if _world else 1)]
	var first := not _held.has(told_key)
	_held[told_key] = true
	_events.append({"kind": "gathered", "festival": kind, "pos": f["focus"], "ids": _ids(f),
		"text": _tell(f), "major": first, "moment": r["moment"],
		"note": "%s, %s, day %d" % [r["name"], f["place"], (_world.day if _world else 0)],
		"life": _life_line(f), "people": _new_in_story(f)})

## Everyone at the table eats from the camp's store, the hungriest first.
func _feast(f: Dictionary, s) -> void:
	var people: Array = (f["people"] as Array).duplicate()
	people.sort_custom(func(x, y): return x.needs["hunger"] < y.needs["hunger"])
	for a in people:
		if s.food_store <= 0.01:
			break
		var take := minf(minf(FEAST_MEAL, 1.0 - a.needs["hunger"]), s.food_store)
		if take <= 0.0:
			continue
		s.food_store -= take
		a.needs["hunger"] = minf(1.0, a.needs["hunger"] + take)
	f["fed"] = people.size()

func _finish(f: Dictionary) -> void:
	for a in (f["people"] as Array):
		if not a.is_dead:
			_release(a, f, 1.0)
	if f["kind"] == "mourning" and f["told"]:
		_dead.erase(int(f["sid"]))
	active.erase(f)
	festival_ended.emit(f["kind"], world_pos(f["focus"]))
	_events.append({"kind": "ended", "festival": f["kind"], "pos": f["focus"], "ids": []})

func _release(a, f: Dictionary, share: float) -> void:
	var lift: float = float(KINDS[f["kind"]]["morale"]) * share
	if f["kind"] == "midsummer" and f["music"]:
		lift *= 1.3
	if f["told"]:
		a.ritual_morale = maxf(a.ritual_morale, lift * (1.0 + a.fxf("settlement_morale_bonus") * 4.0))
		if f["kind"] == "mourning" and a.mourning > 0.0:
			a.mourning *= 0.5   # remembering together eases grief
	a.festival = ""
	a.festival_pose = POSE_STAND
	a.festival_focus = Vector2(-1, -1)
	if a.state == Agent.State.FESTIVAL:
		a.state = Agent.State.WANDERING
		a.target = a.pos
		a.needs_check_timer = 0.0

# ── Places and words ─────────────────────────────────────────────────────────

func _focus_for(kind: String, s) -> Vector2:
	match kind:
		"mourning":
			return s.temple_pos if s.has_temple else s.centre + SettlementRenderer.SHRINE_AT
		"harvest", "planting":
			return _meadow(s, 0.0 if kind == "planting" else 0.8)
	return s.centre

static func _yaw(s) -> float:
	return fmod(float(s.id) * 2.39996 + 0.7, TAU)

## Open meadow just past the camp's houses (it sows there, and the harvest
## table stands there): further out the bigger the place.
func _meadow(s, turn: float = 0.0) -> Vector2:
	var out := clampf(4.0 + 0.4 * s.member_ids.size(), 6.0, 16.0)
	if _world == null:
		return s.centre + Vector2.from_angle(_yaw(s) + turn) * out
	for ring in [out, out + 1.5, out + 3.0]:
		for k in 12:
			var p: Vector2 = s.centre + Vector2.from_angle(_yaw(s) + turn + TAU * k / 12.0) * ring
			if _open(p):
				return p
	return s.centre + Vector2.from_angle(_yaw(s) + turn) * out

## Grass all round (a table or a line of sowers fits).
func _open(p: Vector2) -> bool:
	for o in [Vector2.ZERO, Vector2(1.5, 0), Vector2(-1.5, 0), Vector2(0, 1.5), Vector2(0, -1.5)]:
		var t := _world.get_tile_f(p.x + o.x, p.y + o.y)
		if t.is_empty() or int(t["type"]) != World.TileType.GRASS or bool(t.get("flooded", false)):
			return false
	return true

func world_pos(tile: Vector2) -> Vector3:
	var y := _world.surface_y(tile.x, tile.y) if _world else 0.0
	return Vector3(tile.x * World.TILE_SIZE, y, tile.y * World.TILE_SIZE)

static func _place(s) -> String:
	return str(s.name) if str(s.name) != "" else "a camp"

func _tell(f: Dictionary) -> String:
	var place: String = f["place"]
	var again: String = (" for the %s year" % _nth(int(f["year"]))) if int(f["year"]) > 1 else ""
	match str(f["kind"]):
		"midsummer":
			return "On midsummer night the people of %s lit a great fire and danced round it%s%s." % [
				place, " to music" if f["music"] else "", again]
		"harvest":
			return "%s brought the harvest in and ate together at one long table%s." % [_cap(place), again]
		"midwinter":
			return "On the longest night %s hung out lights and told the old stories%s." % [place, again]
		"mourning":
			var names: Array = f["remembered"]
			var who := ", ".join(names.slice(0, 3)) + (" and others" if names.size() > 3 else "")
			return "%s gathered at the shrine to remember their dead: %s." % [_cap(place), who]
		"planting":
			return "%s went out together to sow the first seed of spring%s." % [_cap(place), again]
	return ""

func _life_line(f: Dictionary) -> String:
	match str(f["kind"]):
		"midsummer": return "Danced round the midsummer fire at %s." % f["place"]
		"harvest": return "Ate at the harvest table in %s." % f["place"]
		"midwinter": return "Sat out the longest night under the lights of %s." % f["place"]
		"mourning": return "Remembered the dead at the shrine of %s." % f["place"]
		"planting": return "Sowed the spring seed at %s." % f["place"]
	return ""

## Those whose story doesn't yet tell of this festival (once a life per kind).
func _new_in_story(f: Dictionary) -> Array:
	var out: Array = []
	for a in (f["people"] as Array):
		var key := "%d:%s" % [a.agent_id, f["kind"]]
		if not _life_told.has(key):
			_life_told[key] = true
			out.append(a)
	return out

static func _ids(f: Dictionary) -> Array:
	return (f["people"] as Array).map(func(a): return a.agent_id)

static func _nth(n: int) -> String:
	var words := ["", "first", "second", "third", "fourth", "fifth", "sixth", "seventh"]
	return words[n] if n < words.size() else "%dth" % n

static func _cap(s: String) -> String:
	return s.left(1).to_upper() + s.substr(1)

# ── For people's thoughts and the inspector ─────────────────────────────────

static func doing(kind: String) -> String:
	return {"midsummer": "dancing round the midsummer fire", "harvest": "at the harvest feast",
		"midwinter": "under the midwinter lights", "mourning": "remembering the dead",
		"planting": "sowing the spring seed"}.get(kind, "at a festival")

static func thought(a) -> String:
	match str(a.festival):
		"midsummer": return "Round and round! The fire's taller than the huts." if a.knowledge.has("music") or a.life_stage == "child" else "The shortest night. Nobody's sleeping."
		"harvest": return "All of us at one table. It was a good year."
		"midwinter": return "The lights keep the long dark back. Tell the one about the first fire."
		"mourning": return ("I'm thinking of %s." % a.mourning_for) if a.mourning_for != "" else "We say their names so they stay with us."
		"planting": return "One for the birds, one for the ground, one for us."
	return "Everyone's here."
