class_name AnimalMinds
extends RefCounted
## Where animals and people meet. AnimalSim moves the animals; this decides
## what passes between them and the people:
## - wolves and bears, rarely, go for someone weak or alone (a child out of
##   sight of the adults, the sick, someone far from camp at night); the
##   living remember the place and keep away from predators after;
## - a person who knows animal_domestication can tame a wolf into a dog that
##   follows them (and guards them); horse_taming lets someone gentle a wild
##   horse that is theirs, and they ride it (Agent.riding_horse_id);
## - camps that know herding / animal_domestication keep a few sheep, cows or
##   pigs near the hearth, and a camp with a coop has hens from its nests;
## - wild rabbits breed in warrens (World nesting sites), and someone who
##   knows conservation brings back a species that died out.
## tick() returns story events for Main to tell. See docs/features/animals.md.

# ── Attacks ──
const ATTACK_FIRST := 240.0        # no attack in the first two days
const ATTACK_GAP_MIN := 240.0      # at least two days between attempts island-wide
const ATTACK_GAP_MAX := 480.0
const ATTACK_RATE := 0.05          # per second, per vulnerable person with a hungry predator near
const ATTACK_REACH := 12.0         # tiles a predator will come for someone
const STALK_GIVE_UP := 18.0        # seconds of chase before it loses interest
const ALONE_RADIUS := 6.0          # nobody else this close: alone
const FAR_FROM_CAMP := 10.0
const RESCUE_RADIUS := 4.0         # two adults (or a dog) this close drive it off
const KILL_ODDS := {"young": 0.65, "weak": 0.55, "adult": 0.3}
const WITNESS_RADIUS := 10.0
const AVOID_RADIUS := 6.0          # someone who remembers danger keeps this far from a predator

# ── Taming and riding ──
const TAME_WOLF_RATE := 0.06       # per second beside a wild wolf (6 tiles)
const TAME_WOLF_REACH := 6.0
const TAME_HORSE_RATE := 0.08      # per second beside a wild horse (5 tiles)
const TAME_HORSE_REACH := 5.0
const SEEK_HORSE_RATE := 0.04      # a horse-tamer without a horse goes out to a herd
const SEEK_HORSE_REACH := 22.0
const MAX_DOGS := 10
const MAX_HORSES := 12
const MOUNT_REACH := 1.5
const RIDE_MIN_TRIP := 4.0         # tiles to go before it's worth getting on
## How much faster a rider goes, by ground: open land is where a horse earns it.
const RIDE_MULT := {
	World.TileType.GRASS: 1.8, World.TileType.BEACH: 1.7, World.TileType.DESERT: 1.6,
	World.TileType.WOODLAND: 1.3, World.TileType.FOREST: 1.05, World.TileType.STONE: 1.2,
}

# ── Flocks at camp ──
const RECRUIT_RATE := 0.03         # per second, per camp short of its flock
const RECRUIT_REACH := 30.0
const HERD_RADIUS := 4.5
const COOP_HENS := 6
const WARRENS := 8

var sim: AnimalSim
var world: World
var population = null    # PopulationManager
var skills = null        # AnimalSkillSystem

# Measured (tests and tools/animals_probe.gd read these).
var attacks := 0
var killed := 0
var driven_off := 0
var tamed_dogs := 0
var tamed_horses := 0
var rides := 0
var kept_animals := 0

var _attack_cooldown := ATTACK_FIRST
var _acc := 0.0
var _events: Array = []
var _dog_of: Dictionary = {}      # agent_id -> anim_id
var _horse_of: Dictionary = {}    # agent_id -> anim_id
var _still: Dictionary = {}       # rider agent_id -> seconds stood still
var _coop_nest: Dictionary = {}   # settlement id -> Vector2i nest tile
var _mourned: Dictionary = {}     # anim_id -> true once its person's death was told
var _first := {}                  # "dog" / "horse" / "ride" / "flock" -> true once told
var _last_day := -1

func setup(p_world: World, p_sim: AnimalSim, p_population = null, p_skills = null) -> void:
	world = p_world
	sim = p_sim
	population = p_population
	skills = p_skills
	sim.skills = skills
	_init_warrens()

## Wild rabbits breed in warrens: grass beside woodland, spread out.
func _init_warrens() -> void:
	if world == null:
		return
	var picked: Array = []
	var tries := 0
	while picked.size() < WARRENS and tries < 4000:
		tries += 1
		var x := randi_range(4, world.width - 5)
		var z := randi_range(4, world.height - 5)
		var t: Dictionary = world.get_tile(x, z)
		if t.is_empty() or int(t["type"]) != World.TileType.GRASS:
			continue
		if not (world._has_adj_type(x, z, World.TileType.WOODLAND) or world._has_adj_type(x, z, World.TileType.FOREST)):
			continue
		var ok := true
		for p in picked:
			if Vector2(p).distance_to(Vector2(x, z)) < 14.0:
				ok = false
				break
		if ok:
			picked.append(Vector2i(x, z))
	world.init_nesting_sites(picked, "rabbit", 4)

# ── Tick ─────────────────────────────────────────────────────────────────────

func tick(delta: float, agents: Array, settlement_system = null, time_system: TimeSystem = null, history_log: HistoryLog = null) -> Array:
	_events = []
	if sim == null:
		return _events
	sim.people = agents
	sim.is_night = time_system != null and time_system.is_night()
	var by_id := {}
	for a in agents:
		by_id[a.agent_id] = a
	_tick_companions(delta, by_id, settlement_system)
	_tick_stalks(delta, by_id, settlement_system)
	_acc += delta
	if _acc >= 1.0:
		var dt := _acc
		_acc = 0.0
		_try_taming(dt, agents, time_system)
		_tick_flocks(dt, agents, settlement_system)
		_try_attack(dt, agents, settlement_system, time_system)
		_avoid_danger(agents)
	_tick_coops(settlement_system)
	if time_system != null and time_system.day != _last_day:
		_last_day = time_system.day
		_reintroduce(agents, time_system.day, history_log)
	return _events

func _say(kind: String, text: String, who, major: bool = false, life_text: String = "") -> void:
	_events.append({"kind": kind, "text": text, "pos": who.pos if who != null else Vector2(-1, -1),
		"ids": [who.agent_id] if who != null else [], "major": major, "who": who, "life": life_text})

static func _alive(a) -> bool:
	return a != null and not a.is_dead and a.health > 0.0

static func _her(a) -> String:
	# People have no recorded sex; the chronicle alternates by id.
	return "her" if a.agent_id % 2 == 0 else "him"

func dog_of(a) -> AnimalSim.Animal:
	return sim.get_animal(int(_dog_of.get(a.agent_id, -1)))

func horse_of(a) -> AnimalSim.Animal:
	return sim.get_animal(int(_horse_of.get(a.agent_id, -1)))

# ── Dogs and horses ──────────────────────────────────────────────────────────

func _tick_companions(delta: float, by_id: Dictionary, settlement_system) -> void:
	for an in sim.animals:
		if an.owner_id < 0 or an.state == AnimalSim.AnimalState.DEAD:
			continue
		var owner = by_id.get(an.owner_id)
		if not _alive(owner):
			_orphan(an, owner, settlement_system)
			continue
		if an.animal_type == AnimalSim.AnimalType.HORSE:
			_tick_ride(delta, an, owner)
		else:
			an.leash = owner.pos
			an.leash_r = 2.5 if owner.riding_horse_id >= 0 else 1.6
			# Keep the camp a dog belongs to, for when its person is gone.
			if settlement_system != null:
				var st = settlement_system.get_settlement_for_agent(owner.agent_id)
				an.home_settlement = int(st.id) if st != null else -1
	# A dead horse leaves its rider on foot.
	for id in _horse_of.keys():
		var h := sim.get_animal(int(_horse_of[id]))
		if h == null or h.state == AnimalSim.AnimalState.DEAD:
			var rider = by_id.get(id)
			if rider != null:
				rider.riding_horse_id = -1
				rider.ride_mult = 1.0
			_horse_of.erase(id)
	for id in _dog_of.keys():
		var d := sim.get_animal(int(_dog_of[id]))
		if d == null or d.state == AnimalSim.AnimalState.DEAD:
			_dog_of.erase(id)

## Their person died: a dog waits by the body until it's buried, then stays
## on at the camp (or goes back to the wild); a horse does the same.
func _orphan(an: AnimalSim.Animal, owner, settlement_system) -> void:
	if owner != null and owner.is_dead:
		owner.riding_horse_id = -1
		an.ridden = false
		an.leash = owner.pos
		an.leash_r = 1.2
		if not _mourned.has(an.anim_id):
			_mourned[an.anim_id] = true
			var what := "dog" if an.animal_type == AnimalSim.AnimalType.WOLF else "horse"
			_say("people", "%s's %s would not leave %s side." % [owner.agent_name, what, _her(owner).replace("him", "his")], owner, false)
		return
	_dog_of.erase(an.owner_id)
	_horse_of.erase(an.owner_id)
	an.owner_id = -1
	an.leash = Vector2(-1, -1)
	an.ridden = false
	var st = null
	if settlement_system != null and an.home_settlement >= 0:
		for s in settlement_system.get_settlements():
			if int(s.id) == an.home_settlement:
				st = s
	if st != null:
		an.home = st.centre
		an.leash_r = HERD_RADIUS
	else:
		an.home = Vector2(-1, -1)
		an.home_settlement = -1

func _tick_ride(delta: float, h: AnimalSim.Animal, a) -> void:
	var riding: bool = a.riding_horse_id == h.anim_id
	var resting: bool = a.state in [Agent.State.SLEEPING, Agent.State.SOCIALIZING, Agent.State.FISHING,
		Agent.State.RITUAL, Agent.State.PERFORMING] or a.at_fire or not a.is_adult
	var trip: float = a.pos.distance_to(a.target)
	if riding:
		var still: float = float(_still.get(a.agent_id, 0.0))
		still = still + delta if trip < 0.3 else 0.0
		_still[a.agent_id] = still
		if resting or still > 4.0 or not world.is_walkable(a.pos.x, a.pos.y):
			_dismount(h, a)
			return
		var before := h.pos
		h.pos = a.pos
		if a.facing.length() > 0.01:
			h.facing = atan2(a.facing.x, a.facing.y)
		var moved := before.distance_to(h.pos) / maxf(delta, 0.0001)
		h.state = AnimalSim.AnimalState.RUN if moved > 2.2 else (AnimalSim.AnimalState.WALK if moved > 0.05 else AnimalSim.AnimalState.IDLE)
		var t: Dictionary = world.get_tile_f(a.pos.x, a.pos.y)
		a.ride_mult = float(RIDE_MULT.get(int(t.get("type", -1)), 1.1)) if not t.is_empty() else 1.0
		return
	a.ride_mult = 1.0
	h.ridden = false
	h.leash = a.pos
	h.leash_r = 2.5
	if not resting and trip > RIDE_MIN_TRIP and h.pos.distance_to(a.pos) < MOUNT_REACH:
		a.riding_horse_id = h.anim_id
		h.ridden = true
		_still[a.agent_id] = 0.0
		rides += 1
		if not _first.has("ride"):
			_first["ride"] = true
			_say("people", "%s rode a horse across the grass: the first rider." % a.agent_name, a, true, "Rode a horse for the first time.")

func _dismount(h: AnimalSim.Animal, a) -> void:
	a.riding_horse_id = -1
	a.ride_mult = 1.0
	h.ridden = false
	h.state = AnimalSim.AnimalState.IDLE
	h.wander_timer = 2.0
	# Step off to one side.
	var side := Vector2(cos(h.facing), -sin(h.facing)) * 0.7
	if world.is_walkable(h.pos.x + side.x, h.pos.y + side.y):
		h.pos += side
	h.target = h.pos

# ── Taming ───────────────────────────────────────────────────────────────────

func _try_taming(dt: float, agents: Array, time_system) -> void:
	var night: bool = time_system != null and time_system.is_night()
	for a in agents:
		if not _alive(a) or not a.is_adult or a.state == Agent.State.SLEEPING:
			continue
		if a.knowledge.has("animal_domestication") and not _dog_of.has(a.agent_id) and _dog_of.size() < MAX_DOGS:
			var w := _nearest_wild(a.pos, AnimalSim.AnimalType.WOLF, TAME_WOLF_REACH)
			if w != null and w.person_target_id < 0 and randf() < TAME_WOLF_RATE * dt:
				_tame(w, a)
				tamed_dogs += 1
				var first := not _first.has("dog")
				_first["dog"] = true
				_say("people", "%s tamed a wolf%s. It follows %s everywhere now." % [a.agent_name, ": the first dog" if first else "", _her(a)],
					a, first, "Tamed a wolf, which followed %s after." % _her(a))
		if a.knowledge.has("horse_taming") and not _horse_of.has(a.agent_id) and _horse_of.size() < MAX_HORSES:
			var h := _nearest_wild(a.pos, AnimalSim.AnimalType.HORSE, TAME_HORSE_REACH)
			if h != null and randf() < TAME_HORSE_RATE * dt:
				_tame(h, a)
				tamed_horses += 1
				var first := not _first.has("horse")
				_first["horse"] = true
				_say("people", "%s gentled a wild horse%s." % [a.agent_name, ", the first anyone has" if first else ""],
					a, first, "Gentled a wild horse of %s own." % _her(a).replace("him", "his"))
			elif h == null and not night and a.state == Agent.State.WANDERING and a.needs["hunger"] > 0.5 \
					and a.needs["energy"] > 0.4 and randf() < SEEK_HORSE_RATE * dt:
				# Go out to a herd: walk up slowly to the nearest wild horse.
				var far := _nearest_wild(a.pos, AnimalSim.AnimalType.HORSE, SEEK_HORSE_REACH)
				if far != null:
					var to: Vector2 = far.pos + (a.pos - far.pos).normalized() * 2.0
					if world.can_traverse(to.x, to.y, a.knowledge):
						a.target = to
						a.needs_check_timer = maxf(a.needs_check_timer, 8.0)

func _tame(an: AnimalSim.Animal, a) -> void:
	sim.leave_group(an)
	an.owner_id = a.agent_id
	an.prey_id = -1
	an.fear = 0.0
	an.flee_timer = 0.0
	an.home = Vector2(-1, -1)
	an.leash = a.pos
	if an.animal_type == AnimalSim.AnimalType.HORSE:
		_horse_of[a.agent_id] = an.anim_id
	else:
		_dog_of[a.agent_id] = an.anim_id

func _nearest_wild(pos: Vector2, t: int, r: float) -> AnimalSim.Animal:
	var best: AnimalSim.Animal = null
	var bd := r
	for an in sim.animals:
		if an.animal_type != t or an.state == AnimalSim.AnimalState.DEAD or an.is_kept:
			continue
		var d: float = an.pos.distance_to(pos)
		if d < bd:
			bd = d
			best = an
	return best

# ── Flocks at camp ───────────────────────────────────────────────────────────

func _kinds_for(st) -> Array:
	var kinds: Array = []
	if st.knowledge_pool.has("herding"):
		kinds.append_array([AnimalSim.AnimalType.SHEEP, AnimalSim.AnimalType.COW])
	if st.knowledge_pool.has("animal_domestication"):
		kinds.append(AnimalSim.AnimalType.PIG)
	return kinds

func _tick_flocks(dt: float, _agents: Array, settlement_system) -> void:
	var camps := {}
	if settlement_system != null:
		for st in settlement_system.get_settlements():
			camps[int(st.id)] = st
	var flock := {}   # settlement id -> count
	kept_animals = 0
	for an in sim.animals:
		if an.owner_id >= 0 or an.home.x < 0.0 or an.state == AnimalSim.AnimalState.DEAD:
			continue
		var st = camps.get(an.home_settlement)
		if st == null:
			# The camp is gone: back to the wild.
			an.home = Vector2(-1, -1)
			an.home_settlement = -1
			continue
		an.home = st.centre if an.animal_type != AnimalSim.AnimalType.CHICKEN else an.home
		if an.animal_type != AnimalSim.AnimalType.WOLF and an.animal_type != AnimalSim.AnimalType.HORSE:
			flock[st.id] = int(flock.get(st.id, 0)) + (0 if an.animal_type == AnimalSim.AnimalType.CHICKEN else 1)
		kept_animals += 1
	for id in camps:
		var st = camps[id]
		var kinds := _kinds_for(st)
		if kinds.is_empty():
			continue
		var cap := clampi(2 + st.member_ids.size() / 3, 2, 8)
		if int(flock.get(id, 0)) >= cap or randf() >= RECRUIT_RATE * dt:
			continue
		# Bring in the nearest wild one of a kind they keep.
		var best: AnimalSim.Animal = null
		var bd := RECRUIT_REACH
		for an in sim.animals:
			if an.state == AnimalSim.AnimalState.DEAD or an.is_kept or not (an.animal_type in kinds):
				continue
			var d: float = an.pos.distance_to(st.centre)
			if d < bd:
				bd = d
				best = an
		if best == null:
			continue
		_keep(best, st)
		var kind := str(AnimalSim.AnimalType.keys()[best.animal_type]).to_lower()
		if not _first.has("flock"):
			_first["flock"] = true
			_events.append({"kind": "people", "text": "The people of %s brought a wild %s in to graze by the hearth." % [st.name, kind],
				"pos": st.centre, "ids": [], "major": true, "who": null, "life": ""})

func _keep(an: AnimalSim.Animal, st) -> void:
	sim.leave_group(an)
	an.home = st.centre
	an.home_settlement = int(st.id)
	an.leash = Vector2(-1, -1)
	an.leash_r = HERD_RADIUS
	an.fear = 0.0
	an.flee_timer = 0.0

## A camp that knows the coop keeps a nest by the hearth; its eggs hatch hens.
func _tick_coops(settlement_system) -> void:
	if settlement_system == null:
		return
	for st in settlement_system.get_settlements():
		if not st.knowledge_pool.has("coop"):
			continue
		var tile: Vector2i = _coop_nest.get(int(st.id), Vector2i(-1, -1))
		if tile.x >= 0 and Vector2(tile).distance_to(st.centre) > 6.0:
			world.nesting_sites.erase("%d,%d" % [tile.x, tile.y])   # the camp moved on
			tile = Vector2i(-1, -1)
		if tile.x < 0:
			for k in 8:
				var p: Vector2 = st.centre + Vector2.from_angle(float(st.id) + float(k) * 0.8) * 2.5
				if world.is_walkable(p.x, p.y):
					tile = Vector2i(floori(p.x), floori(p.y))
					break
			if tile.x < 0:
				continue
			_coop_nest[int(st.id)] = tile
			world.init_nesting_sites([tile], "chicken", 3)
	# Hatch whatever is ready (Main's nest handler leaves chickens to us).
	for key in world.nesting_sites:
		var nest: Dictionary = world.nesting_sites[key]
		if str(nest["species"]) != "chicken" or not bool(nest["spawn_ready"]):
			continue
		var owner_st = null
		for st in settlement_system.get_settlements():
			if _coop_nest.get(int(st.id), Vector2i(-1, -1)) == Vector2i(int(nest["x"]), int(nest["z"])):
				owner_st = st
		var hens := 0
		for an in sim.animals:
			if an.animal_type == AnimalSim.AnimalType.CHICKEN and an.alive and owner_st != null and an.home_settlement == int(owner_st.id):
				hens += 1
		if owner_st != null and hens < COOP_HENS:
			var hen := sim.spawn_one(AnimalSim.AnimalType.CHICKEN, float(nest["x"]) + 0.5, float(nest["z"]) + 0.5)
			if hen != null:
				hen.home = Vector2(float(nest["x"]) + 0.5, float(nest["z"]) + 0.5)
				hen.home_settlement = int(owner_st.id)
				hen.leash_r = 3.0
				if not _first.has("hen"):
					_first["hen"] = true
					_events.append({"kind": "people", "text": "The first hens hatched in the coop at %s." % owner_st.name,
						"pos": hen.pos, "ids": [], "major": false, "who": null, "life": ""})
		world.consume_nest_spawn(int(nest["x"]), int(nest["z"]))

# ── Predators and people ─────────────────────────────────────────────────────

## How exposed someone is: "young" (a child with no adult near), "weak" (sick
## or old, alone), "adult" (alone, far from camp, at night), or "" (safe).
func vulnerability(a, agents_near: Array, settlement_system, night: bool) -> String:
	if not _alive(a) or a.riding_horse_id >= 0:
		return ""
	var adults_near := 0
	var anyone_near := 0
	for o in agents_near:
		if o == a or not _alive(o) or o.pos.distance_to(a.pos) > ALONE_RADIUS:
			continue
		anyone_near += 1
		if o.is_adult:
			adults_near += 1
	if (a.life_stage == "infant" or a.life_stage == "child") and adults_near == 0:
		return "young"
	if anyone_near > 0:
		return ""
	if a.infected or a.life_stage == "elder":
		return "weak"
	if night:
		var st = settlement_system.get_settlement_for_agent(a.agent_id) if settlement_system != null else null
		if st == null or st.centre.distance_to(a.pos) > FAR_FROM_CAMP:
			return "adult"
	return ""

func _guarded(a) -> bool:
	for an in sim.animals:
		if an.owner_id >= 0 and an.animal_type == AnimalSim.AnimalType.WOLF and an.alive and an.pos.distance_to(a.pos) < RESCUE_RADIUS:
			return true
	return false

func _try_attack(dt: float, agents: Array, settlement_system, time_system) -> void:
	if _attack_cooldown > 0.0:
		_attack_cooldown -= dt
		return
	for an in sim.animals:
		if an.person_target_id >= 0:
			return   # one at a time
	var night: bool = time_system != null and time_system.is_night()
	for a in agents:
		if not _alive(a):
			continue
		var near: Array = sim.people_near(a.pos, ALONE_RADIUS)
		var how := vulnerability(a, near, settlement_system, night)
		if how == "" or _guarded(a):
			continue
		var pred: AnimalSim.Animal = null
		var bd := ATTACK_REACH
		for an in sim.animals:
			if not (an.animal_type in AnimalSim.PREDATORS) or an.is_kept or an.state == AnimalSim.AnimalState.DEAD:
				continue
			if an.fed_timer > 0.0 or an.flee_timer > 0.0:
				continue
			var d: float = an.pos.distance_to(a.pos)
			if d < bd:
				bd = d
				pred = an
		if pred != null and randf() < ATTACK_RATE * dt:
			pred.person_target_id = a.agent_id
			pred.prey_id = -1
			pred.hunt_timer = 0.0
			pred.target = a.pos
			attacks += 1
			_attack_cooldown = randf_range(ATTACK_GAP_MIN, ATTACK_GAP_MAX)
			return

func _tick_stalks(delta: float, by_id: Dictionary, settlement_system) -> void:
	for pred in sim.animals:
		if pred.person_target_id < 0:
			continue
		if pred.state == AnimalSim.AnimalState.DEAD:
			pred.person_target_id = -1
			continue
		var v = by_id.get(pred.person_target_id)
		if not _alive(v) or pred.hunt_timer > STALK_GIVE_UP or v.riding_horse_id >= 0:
			pred.person_target_id = -1
			pred.fed_timer = 30.0
			continue
		pred.target = v.pos
		var d: float = pred.pos.distance_to(v.pos)
		var kind: String = str(AnimalSim.AnimalType.keys()[pred.animal_type]).to_lower()
		# Help: two grown-ups or a dog close by drive it off.
		var helpers: Array = sim.people_near(v.pos, RESCUE_RADIUS).filter(func(o): return o != v and o.is_adult and _alive(o))
		if helpers.size() >= 2 or _guarded(v):
			pred.person_target_id = -1
			pred.fed_timer = 40.0
			sim.bolt(pred, v.pos)
			driven_off += 1
			var by := "%s's dog" % v.agent_name if _guarded(v) else "%s and %s" % [helpers[0].agent_name, helpers[1].agent_name]
			_say("people", "A %s went for %s, but %s drove it off." % [kind, v.agent_name, by], v, false, "Was chased by a %s and saved." % kind)
			_remember(v, pred, by_id, settlement_system)
			continue
		# The person sees it coming and runs.
		if d < 5.0 and d > 0.6:
			var away: Vector2 = (v.pos - pred.pos).normalized()
			var to: Vector2 = v.pos + away * 6.0
			if world.can_traverse(to.x, to.y, v.knowledge):
				if v.state == Agent.State.SLEEPING or v.state == Agent.State.SOCIALIZING:
					v.state = Agent.State.WANDERING
				v.target = to
				v.needs_check_timer = maxf(v.needs_check_timer, 2.0)
		if d > 0.6:
			continue
		# It strikes.
		var how := vulnerability(v, sim.people_near(v.pos, ALONE_RADIUS), settlement_system, sim.is_night)
		if how == "":
			how = "adult"
		pred.person_target_id = -1
		_remember(v, pred, by_id, settlement_system)
		if randf() < float(KILL_ODDS[how]):
			v.is_dead = true
			v.death_cause = kind
			v.health = 0.0
			v.riding_horse_id = -1
			killed += 1
			pred.fed_timer = float(AnimalSim.FED_SECONDS.get(pred.animal_type, 90.0)) * 1.5
			pred.state = AnimalSim.AnimalState.EAT
			pred.wander_timer = 8.0
		else:
			v.health = maxf(0.05, v.health - 0.35)
			pred.fed_timer = 40.0
			sim.bolt(pred, v.pos)
			_say("people", "%s was mauled by a %s, and lived." % [v.agent_name, kind], v, false, "Survived a %s." % kind)

## The victim, everyone who saw it, and their camp remember where it happened.
func _remember(v, pred: AnimalSim.Animal, by_id: Dictionary, settlement_system) -> void:
	var kind: String = str(AnimalSim.AnimalType.keys()[pred.animal_type]).to_lower()
	var tx := floori(pred.pos.x)
	var tz := floori(pred.pos.y)
	var told := {}
	for o in sim.people_near(v.pos, WITNESS_RADIUS):
		told[o.agent_id] = o
	told[v.agent_id] = v
	if settlement_system != null:
		var st = settlement_system.get_settlement_for_agent(v.agent_id)
		if st != null:
			for id in st.member_ids:
				if by_id.has(id):
					told[id] = by_id[id]
	for id in told:
		var o = told[id]
		if _alive(o) or o == v:
			o.remember_danger(tx, tz, kind)

## Someone who remembers a predator attack keeps clear of wolves and bears.
func _avoid_danger(agents: Array) -> void:
	for a in agents:
		if not _alive(a) or a.memory["dangers"].is_empty() or a.at_fire or a.riding_horse_id >= 0:
			continue
		if a.state != Agent.State.WANDERING and a.state != Agent.State.GATHERING:
			continue
		var pred: AnimalSim.Animal = null
		var bd := AVOID_RADIUS
		for an in sim.animals:
			if (an.animal_type in AnimalSim.PREDATORS) and not an.is_kept and an.alive:
				var d: float = an.pos.distance_to(a.pos)
				if d < bd:
					bd = d
					pred = an
		if pred == null:
			continue
		var away: Vector2 = (a.pos - pred.pos).normalized()
		var to: Vector2 = a.pos + away * 6.0
		if world.can_traverse(to.x, to.y, a.knowledge):
			a.target = to
			a.state = Agent.State.WANDERING
			a.needs_check_timer = maxf(a.needs_check_timer, 3.0)

# ── Conservation ─────────────────────────────────────────────────────────────

func _reintroduce(agents: Array, day: int, history_log) -> void:
	if population == null:
		return
	var knows := false
	for a in agents:
		if _alive(a) and a.knowledge.has("conservation"):
			knows = true
			break
	if not knows:
		return
	for species in population.get_extinct_species():
		if population.reintroduce(str(species), day, history_log):
			_events.append({"kind": "world", "text": "%s are back on the island, brought by those who know conservation." % str(species).capitalize(),
				"pos": Vector2(-1, -1), "ids": [], "major": true, "who": null, "life": ""})
