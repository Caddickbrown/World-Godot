class_name AnimalSim
extends RefCounted
## The island's animals and how they move. Each species has a mind of its own:
## wolves run in packs and hunt together; horses, deer, sheep and cattle drift
## in loose herds and bolt together; herbivores keep their distance from
## people (more from hunters); eagles ride thermals over high ground and stoop
## on rabbits. What animals do *to and with people* (attacks, taming, riding,
## flocks kept at camp) lives in AnimalMinds, which sets the fields below
## (owner_id, home, leash, ridden, person_target_id) and lets this file move
## them. See docs/features/animals.md.

enum AnimalType {
	DEER   = 0,
	WOLF   = 1,
	SHEEP  = 2,
	HORSE  = 3,
	COW    = 4,
	RABBIT = 5,
	EAGLE  = 6,
	FOX    = 7,
	PIG    = 8,
	BEAR   = 9,
	CHICKEN = 10,   # only ever kept: hatched from coop nests at a camp
}

enum AnimalState {
	IDLE = 0,
	WALK = 1,
	RUN  = 2,
	EAT  = 3,
	FLEE = 4,
	HUNT = 5,   # predators chasing; an eagle in its dive
	DEAD = 6,
	SOAR = 7,
}

class Animal extends RefCounted:
	var anim_id: int = 0
	var animal_type: int = AnimalSim.AnimalType.DEER
	var pos: Vector2 = Vector2.ZERO
	var target: Vector2 = Vector2.ZERO
	var state: int = AnimalSim.AnimalState.IDLE
	var health: float = 1.0
	var speed: float = 1.5
	var wander_timer: float = 0.0
	var flee_timer: float = 0.0
	var facing: float = 0.0  # yaw radians, used by renderer
	# Minds
	var group_id: int = -1        # pack (wolves) or herd (horses, deer, sheep, cows)
	var fear: float = 0.0         # 0..1, rises while people are close (CAD-195)
	var stamina: float = 1.0      # spent while fleeing; a tired animal slows
	var fed_timer: float = 0.0    # predators: seconds until hungry again
	var hunt_timer: float = 0.0   # predators: how long this chase has run
	var prey_id: int = -1
	var sense_timer: float = 0.0
	var threat_pos: Vector2 = Vector2(-1, -1)   # last sensed danger (person or predator)
	var threat_is_predator: bool = false
	var threat_is_hunter: bool = false
	var fled_from_danger: bool = false
	var escapes: int = 0
	# People (set by AnimalMinds)
	var owner_id: int = -1        # a tame dog or horse: whose it is
	var home: Vector2 = Vector2(-1, -1)   # a kept animal's camp centre
	var home_settlement: int = -1
	var leash: Vector2 = Vector2(-1, -1)  # point a tame/kept animal stays near
	var leash_r: float = 3.0
	var ridden: bool = false      # AnimalMinds moves a ridden horse with its rider
	var person_target_id: int = -1  # a predator stalking a person (AnimalMinds aims it)
	# Eagles
	var alt: float = 0.0          # metres above the ground
	var thermal: Vector2 = Vector2(-1, -1)
	var circle_r: float = 5.0
	var circle_dir: float = 1.0
	var circle_ang: float = 0.0
	var soar_timer: float = 0.0
	var turn_rate: float = 0.0    # yaw radians/s (renderer banks on it)
	# Death
	var dead_time: float = 0.0
	var cause: String = ""

	func _init(id: int, t: int, x: float, z: float) -> void:
		anim_id = id
		animal_type = t
		pos = Vector2(x, z)
		target = pos
		state = AnimalSim.AnimalState.IDLE
		health = 1.0
		speed = AnimalSim.type_base_speed(t)
		wander_timer = randf() * 5.0
		flee_timer = 0.0
		facing = randf() * TAU
		sense_timer = randf() * AnimalSim.SENSE_INTERVAL

	var is_tame: bool:
		get: return owner_id >= 0
	var is_kept: bool:
		get: return owner_id >= 0 or home.x >= 0.0
	var alive: bool:
		get: return state != AnimalSim.AnimalState.DEAD

const SENSE_INTERVAL := 0.35   # seconds between an animal looking around
const CORPSE_SECONDS := 60.0   # half a day lying where it fell, then gone
const CELL := 8.0              # bucket size (tiles) for neighbour queries

## Most of each species the island holds at once (spawns past it are refused).
const SPECIES_CAP := {
	AnimalType.DEER: 60, AnimalType.WOLF: 18, AnimalType.SHEEP: 50, AnimalType.HORSE: 24,
	AnimalType.COW: 40, AnimalType.RABBIT: 70, AnimalType.EAGLE: 16, AnimalType.FOX: 20,
	AnimalType.PIG: 40, AnimalType.BEAR: 6, AnimalType.CHICKEN: 40,
}
## How close a person may come before fear starts to rise (tiles). Hunters
## are noticed from further (x HUNTER_REACH) and frighten faster.
const FEAR_RADIUS := {
	AnimalType.DEER: 7.0, AnimalType.RABBIT: 4.5, AnimalType.FOX: 6.0, AnimalType.HORSE: 5.5,
	AnimalType.SHEEP: 3.5, AnimalType.COW: 3.0, AnimalType.PIG: 3.5,
}
const HUNTER_REACH := 1.4
const FEAR_ALERT := 0.25       # head up, watching
const FEAR_BOLT := 0.6         # runs
## Herd / pack size range and how far a member strays from its leader.
const GROUPS := {
	AnimalType.WOLF: [3, 4, 3.0], AnimalType.HORSE: [3, 6, 4.0], AnimalType.DEER: [2, 5, 5.0],
	AnimalType.SHEEP: [3, 6, 3.0], AnimalType.COW: [2, 4, 4.0],
}
const PREY := {
	AnimalType.WOLF: [AnimalType.DEER, AnimalType.SHEEP, AnimalType.RABBIT],
	AnimalType.BEAR: [AnimalType.DEER, AnimalType.SHEEP, AnimalType.PIG],
	AnimalType.FOX:  [AnimalType.RABBIT, AnimalType.CHICKEN],
}
const FED_SECONDS := {AnimalType.WOLF: 90.0, AnimalType.BEAR: 140.0, AnimalType.FOX: 70.0, AnimalType.EAGLE: 100.0}
const PREDATORS := [AnimalType.WOLF, AnimalType.BEAR]

var animals: Array = []
var _next_id: int = 0
## The world they live on. Targets used to be clamped to (31, 31), a leftover
## of the 32x32 map, so every animal drifted into one corner (now open sea).
var _world: World = null
## People, for fear (AnimalMinds sets it; empty in unit tests).
var people: Array = []
var is_night: bool = false
## Optional: escapes make an animal warier and faster (AnimalSkillSystem).
var skills = null
## Where warm air rises: high stone and mountain ground. Eagles circle here.
var thermals: Array = []
var _by_id: Dictionary = {}
var _groups: Dictionary = {}      # group_id -> Array[Animal] (living)
var _next_group: int = 0
var _cells: Dictionary = {}       # Vector2i -> Array[Animal]
var _people_cells: Dictionary = {}
## Kills this sim made (predators, eagles); tests and the probe read it.
var kills_by: Dictionary = {}

static func type_base_speed(t: int) -> float:
	match t:
		AnimalType.DEER:   return 1.8
		AnimalType.WOLF:   return 2.2
		AnimalType.SHEEP:  return 1.2
		AnimalType.HORSE:  return 2.8
		AnimalType.COW:    return 1.0
		AnimalType.RABBIT: return 2.4
		AnimalType.EAGLE:  return 3.5
		AnimalType.FOX:    return 1.9
		AnimalType.PIG:    return 1.3
		AnimalType.BEAR:   return 1.5
		AnimalType.CHICKEN: return 0.9
	return 1.5

func spawn_wildlife(world: World) -> void:
	_world = world
	animals.clear()
	_by_id.clear()
	_groups.clear()
	_next_id = 0

	# Wildlife density scales with the map. 35 animals was tuned for a 32x32
	# world; on 128x128 that leaves the map empty.
	var area_scale: float = float(world.width * world.height) / (32.0 * 32.0)
	var land_count: int = clampi(int(35.0 * sqrt(area_scale) * 1.6), 35, 220)
	var land_pts: Array = world.get_land_spawn_points(land_count)
	for i in range(land_pts.size()):
		var pt: Dictionary = land_pts[i]
		var x: float = float(pt["x"]) + randf() * 0.6 - 0.3
		var z: float = float(pt["z"]) + randf() * 0.6 - 0.3
		var tile: Dictionary = world.get_tile(int(pt["x"]), int(pt["z"]))
		var tile_type: int = int(tile.get("type", 0))
		var t: int = _pick_type_for_biome(tile_type, i)
		# One wolf in four forest animals filled the island with ~30 lone
		# wolves; a few packs are wilder and easier to watch.
		if _count_type(t) >= int(_initial_cap(t)):
			t = AnimalType.DEER if t == AnimalType.WOLF else AnimalType.RABBIT
			if _count_type(t) >= int(_initial_cap(t)):
				continue
		_add(Animal.new(_next_id, t, x, z))

	_form_groups()
	_find_thermals()

	# Eagles always soar regardless of biome. Spread them over the whole map —
	# the old fixed 4..28 range put every eagle in one corner of a large world.
	var eagle_count: int = clampi(int(4.0 * sqrt(area_scale)), 4, 16)
	for _i in range(eagle_count):
		var ex: float = randf() * float(world.width)
		var ez: float = randf() * float(world.height)
		_add_eagle(ex, ez)

func _initial_cap(t: int) -> int:
	match t:
		AnimalType.WOLF: return 12
		AnimalType.BEAR: return 4
	return int(SPECIES_CAP.get(t, 50))

func _add(a: Animal) -> Animal:
	_next_id = maxi(_next_id, a.anim_id + 1)
	animals.append(a)
	_by_id[a.anim_id] = a
	return a

func _add_eagle(x: float, z: float) -> Animal:
	var eagle := _add(Animal.new(_next_id, AnimalType.EAGLE, x, z))
	eagle.state = AnimalState.SOAR
	eagle.alt = 9.0 + randf() * 5.0
	eagle.circle_dir = 1.0 if eagle.anim_id % 2 == 0 else -1.0
	eagle.circle_r = 4.0 + randf() * 3.0
	_pick_thermal(eagle)
	return eagle

func _count_type(t: int) -> int:
	var n := 0
	for a in animals:
		if a.animal_type == t and a.state != AnimalState.DEAD:
			n += 1
	return n

# Spawns a single animal of the given type. Used by nesting sites hatching a
# clutch and by PopulationManager reintroducing a locally extinct species.
# Returns null when the island already holds as many as it can.
func spawn_one(t: int, x: float, z: float) -> Animal:
	if _count_type(t) >= int(SPECIES_CAP.get(t, 60)):
		return null
	if t == AnimalType.EAGLE:
		return _add_eagle(x, z)
	var a := _add(Animal.new(_next_id, t, x, z))
	# A newcomer joins the nearest herd of its kind, if it has one near.
	if GROUPS.has(t):
		var best_g := -1
		var best_d := 12.0
		for gid in _groups:
			var members: Array = _groups[gid]
			if members.is_empty() or members[0].animal_type != t or members.size() >= int(GROUPS[t][1]) + 1:
				continue
			var d: float = members[0].pos.distance_to(a.pos)
			if d < best_d:
				best_d = d
				best_g = gid
		if best_g >= 0:
			_join(a, best_g)
	return a

func get_animal(id: int) -> Animal:
	return _by_id.get(id) as Animal

func _pick_type_for_biome(tile_type: int, idx: int) -> int:
	var r: int = idx % 7
	match tile_type:
		World.TileType.FOREST, World.TileType.WOODLAND:
			match r % 4:
				0: return AnimalType.DEER
				1: return AnimalType.WOLF
				2: return AnimalType.FOX
				_: return AnimalType.RABBIT
		World.TileType.GRASS:
			match r % 4:
				0: return AnimalType.SHEEP
				1: return AnimalType.HORSE
				2: return AnimalType.COW
				_: return AnimalType.PIG
		World.TileType.STONE, World.TileType.MOUNTAIN:
			match r % 3:
				0: return AnimalType.BEAR
				1: return AnimalType.FOX
				_: return AnimalType.RABBIT
		_:
			return AnimalType.DEER

# ── Packs and herds ──────────────────────────────────────────────────────────

## Gathers each herding species into groups: the first unassigned animal is a
## leader, and the nearest others of its kind are walked in beside it.
func _form_groups() -> void:
	for t in GROUPS:
		var spec: Array = GROUPS[t]
		var pool: Array = animals.filter(func(a): return a.animal_type == t and a.group_id < 0)
		while pool.size() >= 2:
			var leader: Animal = pool.pop_front()
			var size: int = randi_range(int(spec[0]), int(spec[1]))
			pool.sort_custom(func(p, q): return p.pos.distance_squared_to(leader.pos) < q.pos.distance_squared_to(leader.pos))
			var gid := _new_group(leader)
			for i in mini(size - 1, pool.size()):
				var m: Animal = pool.pop_front()
				_join(m, gid)
				# Move it in beside its leader, on ground it can stand on.
				for attempt in 8:
					var off := Vector2.from_angle(randf() * TAU) * (0.8 + randf() * float(spec[2]) * 0.6)
					var p: Vector2 = leader.pos + off
					if _world == null or _world.is_walkable(p.x, p.y):
						m.pos = p
						m.target = p
						break

func _new_group(leader: Animal) -> int:
	var gid := _next_group
	_next_group += 1
	_groups[gid] = []
	_join(leader, gid)
	return gid

func _join(a: Animal, gid: int) -> void:
	_leave_group(a)
	a.group_id = gid
	if not _groups.has(gid):
		_groups[gid] = []
	(_groups[gid] as Array).append(a)

func _leave_group(a: Animal) -> void:
	if a.group_id >= 0 and _groups.has(a.group_id):
		var members: Array = _groups[a.group_id]
		members.erase(a)
		if members.is_empty():
			_groups.erase(a.group_id)
	a.group_id = -1

## Removes an animal from its pack or herd (it was tamed, or kept at camp).
func leave_group(a: Animal) -> void:
	_leave_group(a)

func group_of(a: Animal) -> Array:
	return _groups.get(a.group_id, []) if a.group_id >= 0 else []

## The group's leader is its first living member.
func leader_of(a: Animal) -> Animal:
	var members := group_of(a)
	return members[0] if not members.is_empty() else null

func group_count(t: int) -> int:
	var n := 0
	for gid in _groups:
		var m: Array = _groups[gid]
		if not m.is_empty() and m[0].animal_type == t and m.size() >= 2:
			n += 1
	return n

# ── Thermals ─────────────────────────────────────────────────────────────────

func _find_thermals() -> void:
	thermals.clear()
	if _world == null:
		return
	var cands: Array = []
	for z in range(2, _world.height - 2, 3):
		for x in range(2, _world.width - 2, 3):
			var t: Dictionary = _world.get_tile(x, z)
			var tt := int(t.get("type", -1))
			if tt == World.TileType.MOUNTAIN or tt == World.TileType.STONE or float(t.get("elevation", 0.0)) > 0.62:
				cands.append([float(t.get("elevation", 0.0)) + (0.3 if tt == World.TileType.MOUNTAIN else 0.0), Vector2(x + 0.5, z + 0.5)])
	cands.sort_custom(func(p, q): return p[0] > q[0])
	for c in cands:
		var p: Vector2 = c[1]
		var ok := true
		for q in thermals:
			if p.distance_to(q) < 14.0:
				ok = false
				break
		if ok:
			thermals.append(p)
		if thermals.size() >= 10:
			break
	if thermals.is_empty():
		thermals.append(Vector2(_world.width * 0.5, _world.height * 0.5))

func _pick_thermal(e: Animal) -> void:
	if thermals.is_empty():
		e.thermal = e.pos
		return
	# Mostly a near thermal, sometimes a far one, so eagles cross the island.
	var best: Vector2 = thermals[randi() % thermals.size()]
	if randf() < 0.65:
		var bd := INF
		for t in thermals:
			var d: float = t.distance_to(e.pos)
			if d > 3.0 and d < bd:
				bd = d
				best = t
	e.thermal = best
	e.soar_timer = 25.0 + randf() * 30.0

# ── Death ────────────────────────────────────────────────────────────────────

## The one way an animal dies: it lies where it fell for half a day, then is
## gone from the list (and the renderer drops it).
func kill(a: Animal, why: String = "") -> void:
	if a == null or a.state == AnimalState.DEAD:
		return
	a.state = AnimalState.DEAD
	a.health = 0.0
	a.dead_time = 0.0
	a.cause = why
	a.ridden = false
	a.person_target_id = -1
	a.alt = 0.0
	_leave_group(a)
	kills_by[why] = int(kills_by.get(why, 0)) + 1

# ── Tick ─────────────────────────────────────────────────────────────────────

func tick(delta: float, world: World) -> void:
	if world != null:
		_world = world
	if thermals.is_empty() and _world != null:
		_find_thermals()
	_bucket()
	var gone := false
	for a in animals:
		var animal: Animal = a as Animal
		if animal == null: continue
		if animal.state == AnimalState.DEAD:
			animal.dead_time += delta
			if animal.dead_time > CORPSE_SECONDS:
				gone = true
			continue
		if animal.health <= 0.0:
			# Something outside set health to 0 (PopulationManager's cull):
			# a kept animal is spared; anything else dies properly.
			if animal.is_kept:
				animal.health = 1.0
			else:
				kill(animal, "culled")
				continue
		if animal.fed_timer > 0.0:
			animal.fed_timer -= delta
		_tick_animal(animal, delta)
	if gone:
		_prune()

func _prune() -> void:
	var keep: Array = []
	for a in animals:
		if a.state == AnimalState.DEAD and a.dead_time > CORPSE_SECONDS:
			_by_id.erase(a.anim_id)
			if skills != null:
				skills.clear_animal(a.animal_type, a.anim_id)
		else:
			keep.append(a)
	animals = keep

func _tick_animal(animal: Animal, delta: float) -> void:
	if animal.ridden:
		return   # AnimalMinds carries it with its rider
	if animal.animal_type == AnimalType.EAGLE:
		_tick_eagle(animal, delta)
		return
	animal.sense_timer -= delta
	var sensed := animal.sense_timer <= 0.0
	if sensed:
		animal.sense_timer = SENSE_INTERVAL
	if animal.is_kept:
		_tick_kept(animal, delta, sensed)
		return
	match animal.animal_type:
		AnimalType.WOLF, AnimalType.BEAR:
			_tick_predator(animal, delta, sensed)
		AnimalType.FOX:
			# A fox hunts rabbits but is shy of people like any small beast.
			if not _tick_wary(animal, delta, sensed):
				_tick_predator(animal, delta, sensed)
		_:
			if not _tick_wary(animal, delta, sensed):
				_herd_wander(animal, delta)

# ── Neighbours (bucketed, rebuilt each tick) ─────────────────────────────────

func _bucket() -> void:
	_cells.clear()
	for a in animals:
		if a.state == AnimalState.DEAD: continue
		var c := Vector2i(floori(a.pos.x / CELL), floori(a.pos.y / CELL))
		if not _cells.has(c): _cells[c] = []
		(_cells[c] as Array).append(a)
	_people_cells.clear()
	for p in people:
		if p.is_dead or p.health <= 0.0: continue
		var c := Vector2i(floori(p.pos.x / CELL), floori(p.pos.y / CELL))
		if not _people_cells.has(c): _people_cells[c] = []
		(_people_cells[c] as Array).append(p)

func _near(cells: Dictionary, pos: Vector2, r: float) -> Array:
	var out: Array = []
	var x0 := floori((pos.x - r) / CELL)
	var x1 := floori((pos.x + r) / CELL)
	var z0 := floori((pos.y - r) / CELL)
	var z1 := floori((pos.y + r) / CELL)
	for cz in range(z0, z1 + 1):
		for cx in range(x0, x1 + 1):
			var c := Vector2i(cx, cz)
			if cells.has(c):
				out.append_array(cells[c])
	return out

func people_near(pos: Vector2, r: float) -> Array:
	return _near(_people_cells, pos, r).filter(func(p): return p.pos.distance_to(pos) <= r)

func _nearest_animal(from: Animal, types: Array, max_dist: float, wild_only: bool = true) -> Animal:
	var best: Animal = null
	var best_d := max_dist
	for other in _near(_cells, from.pos, max_dist):
		if other == from or other.state == AnimalState.DEAD: continue
		if not (other.animal_type in types): continue
		if wild_only and other.is_kept: continue
		var d: float = from.pos.distance_to(other.pos)
		if d < best_d:
			best_d = d
			best = other
	return best

## Kept for callers (and tests) of the old API.
func _find_nearest_of_types(animal: Animal, types: Array, max_dist: float) -> Animal:
	return _nearest_animal(animal, types, max_dist, false)

# ── Fear (herbivores and foxes) ──────────────────────────────────────────────

## Looks for danger and reacts. Returns true when fear is driving the animal
## this tick (fleeing or standing alert), so normal wandering is skipped.
func _tick_wary(animal: Animal, delta: float, sensed: bool) -> bool:
	var wary := _wariness(animal)
	if sensed:
		animal.threat_pos = Vector2(-1, -1)
		animal.threat_is_predator = false
		animal.threat_is_hunter = false
		# Predators: run at once.
		var pred_types: Array = PREDATORS.duplicate()
		if animal.animal_type == AnimalType.RABBIT:
			pred_types.append(AnimalType.FOX)
		var pred := _nearest_animal(animal, pred_types, 5.0 * wary, true)
		if pred != null and (pred.animal_type != AnimalType.FOX or animal.animal_type == AnimalType.RABBIT):
			animal.threat_pos = pred.pos
			animal.threat_is_predator = true
		# A diving eagle overhead.
		if animal.threat_pos.x < 0.0 and animal.animal_type == AnimalType.RABBIT:
			for e in _near(_cells, animal.pos, 4.0):
				if e.animal_type == AnimalType.EAGLE and e.state == AnimalState.HUNT and e.alt < 6.0:
					animal.threat_pos = e.pos
					animal.threat_is_predator = true
		# People.
		if animal.threat_pos.x < 0.0 and FEAR_RADIUS.has(animal.animal_type):
			var r: float = float(FEAR_RADIUS[animal.animal_type]) * wary
			var best_d := INF
			for p in _near(_people_cells, animal.pos, r * HUNTER_REACH):
				if _calms(p, animal):
					continue
				var hunter: bool = p.is_adult and p.knowledge.has("hunting")
				var reach := r * (HUNTER_REACH if hunter else 1.0)
				var d: float = p.pos.distance_to(animal.pos)
				if d < reach and d / reach < best_d:
					best_d = d / reach
					animal.threat_pos = p.pos
					animal.threat_is_hunter = hunter
	# Fear rises while danger is near and fades when it's gone.
	if animal.threat_pos.x >= 0.0:
		if animal.threat_is_predator:
			animal.fear = 1.0
		else:
			var close := 1.0 - clampf(animal.pos.distance_to(animal.threat_pos) / (float(FEAR_RADIUS.get(animal.animal_type, 4.0)) * wary * HUNTER_REACH), 0.0, 1.0)
			animal.fear = minf(1.0, animal.fear + (0.9 if animal.threat_is_hunter else 0.45) * (0.3 + close) * delta)
	else:
		animal.fear = maxf(0.0, animal.fear - 0.12 * delta)

	# Stamina: running spends it, resting earns it back.
	if animal.flee_timer > 0.0:
		animal.stamina = maxf(0.0, animal.stamina - 0.15 * delta)
	else:
		animal.stamina = minf(1.0, animal.stamina + 0.1 * delta)

	if animal.threat_pos.x >= 0.0 and animal.fear >= FEAR_BOLT and animal.flee_timer <= 0.5:
		_bolt(animal, animal.threat_pos)
		_alarm_group(animal, animal.threat_pos)

	if animal.flee_timer > 0.0:
		animal.flee_timer -= delta
		var mult := 1.7 * _escape_mult(animal)
		if animal.stamina < 0.12:
			mult = 0.75   # spent: a hunter on foot can close in now
		_move_toward(animal, delta, mult, AnimalState.FLEE)
		if animal.flee_timer <= 0.0:
			animal.state = AnimalState.IDLE
			animal.wander_timer = 0.5 + randf()
			if animal.fled_from_danger:
				animal.fled_from_danger = false
				animal.escapes += 1
				if skills != null:
					skills.on_successful_escape(animal.animal_type, animal.anim_id)
		return true

	# Alert: head up, watching the person, not grazing.
	if animal.threat_pos.x >= 0.0 and animal.fear >= FEAR_ALERT:
		animal.state = AnimalState.IDLE
		var to := animal.threat_pos - animal.pos
		if to.length() > 0.01:
			animal.facing = atan2(to.x, to.y)
		return true
	return false

func _bolt(animal: Animal, from: Vector2) -> void:
	animal.state = AnimalState.FLEE
	animal.flee_timer = 3.0 + randf()
	animal.fled_from_danger = true
	var away := (animal.pos - from)
	away = away.normalized() if away.length() > 0.01 else Vector2.from_angle(randf() * TAU)
	away = away.rotated((randf() - 0.5) * 0.6)
	animal.target = _land_target(animal, animal.pos + away * 9.0)

## Sends an animal running from a point (AnimalMinds: a predator driven off).
func bolt(animal: Animal, from: Vector2) -> void:
	_bolt(animal, from)
	animal.fled_from_danger = false

## The herd bolts together: one startled member sets off the rest.
func _alarm_group(animal: Animal, from: Vector2) -> void:
	for m in group_of(animal):
		if m == animal or m.is_kept or m.state == AnimalState.DEAD or m.flee_timer > 0.5:
			continue
		if m.pos.distance_to(animal.pos) < 9.0:
			m.fear = maxf(m.fear, FEAR_BOLT)
			_bolt(m, from)

## Who doesn't frighten this animal: its own people (kept animals) and
## anyone who knows how to read a horse (horse_taming).
func _calms(p, animal: Animal) -> bool:
	if animal.animal_type == AnimalType.HORSE and p.knowledge.has("horse_taming"):
		return true
	return false

func _wariness(animal: Animal) -> float:
	if skills == null:
		return 1.0
	return 1.0 + skills.escape_of(animal.animal_type, animal.anim_id) * 0.5

func _escape_mult(animal: Animal) -> float:
	if skills == null:
		return 1.0
	return 1.0 + skills.escape_of(animal.animal_type, animal.anim_id) * 0.25

# ── Herds wander together ────────────────────────────────────────────────────

func _herd_wander(animal: Animal, delta: float) -> void:
	var leader := leader_of(animal)
	if leader != null and leader != animal:
		var spec: Array = GROUPS.get(animal.animal_type, [0, 0, 4.0])
		var keep: float = float(spec[2])
		var d: float = animal.pos.distance_to(leader.pos)
		if d > keep:
			# Catch up: a trot (RUN) when it's fallen well behind.
			var off := Vector2.from_angle(float(animal.anim_id) * 2.39996) * keep * 0.45
			animal.target = _land_target(animal, leader.pos + off)
			var st := AnimalState.RUN if d > keep * 2.0 else AnimalState.WALK
			_move_toward(animal, delta, 1.5 if st == AnimalState.RUN else 1.0, st)
			animal.wander_timer = 0.5
			return
	_wander(animal, delta, 1.6 if (leader == animal and animal.animal_type == AnimalType.HORSE) else 1.0)

# ── Predators: packs that hunt together ──────────────────────────────────────

func _tick_predator(animal: Animal, delta: float, sensed: bool) -> void:
	# A person it's stalking (AnimalMinds picks and aims; rare).
	if animal.person_target_id >= 0:
		animal.hunt_timer += delta
		_move_toward(animal, delta, 1.5, AnimalState.HUNT)
		return
	# Packs and bears keep clear of groups of people.
	if sensed and animal.animal_type != AnimalType.FOX:
		var crowd := people_near(animal.pos, 6.0).size()
		if crowd >= 3:
			for m in _pack(animal):
				if m.alive and m.person_target_id < 0:
					m.prey_id = -1
					var c := _crowd_centre(m.pos, 6.0)
					_bolt(m, c)
					m.fled_from_danger = false
	if animal.flee_timer > 0.0:
		animal.flee_timer -= delta
		_move_toward(animal, delta, 1.5, AnimalState.FLEE)
		return

	var prey: Animal = get_animal(animal.prey_id) if animal.prey_id >= 0 else null
	if prey != null and (prey.state == AnimalState.DEAD or prey.is_kept):
		prey = null
	if prey == null:
		animal.prey_id = -1
		animal.hunt_timer = 0.0
	if prey == null and sensed and animal.fed_timer <= 0.0:
		var reach := 10.0 if animal.animal_type != AnimalType.FOX else 6.0
		if is_night: reach *= 1.3
		prey = _nearest_animal(animal, PREY.get(animal.animal_type, []), reach)
		if prey != null:
			# The whole pack takes up the chase.
			for m in _pack(animal):
				if m.alive and m.person_target_id < 0 and m.fed_timer <= 0.0:
					m.prey_id = prey.anim_id
					m.hunt_timer = 0.0
	if prey != null:
		animal.hunt_timer += delta
		if animal.hunt_timer > 22.0:
			# It got away: give up and rest a while.
			animal.prey_id = -1
			animal.fed_timer = 20.0
			if prey.alive and skills != null:
				skills.on_successful_escape(prey.animal_type, prey.anim_id)
			_wander(animal, delta)
			return
		var dist: float = animal.pos.distance_to(prey.pos)
		if dist < 0.5:
			kill(prey, AnimalType.keys()[animal.animal_type].to_lower())
			var fed: float = float(FED_SECONDS.get(animal.animal_type, 90.0))
			for m in _pack(animal):
				m.fed_timer = fed * (0.85 + randf() * 0.3)
				m.prey_id = -1
				m.state = AnimalState.EAT
				m.wander_timer = 6.0 + randf() * 4.0
			return
		# Pack members fan out round the prey to cut it off.
		var flank := Vector2.ZERO
		var members := group_of(animal)
		if members.size() > 1 and dist > 1.5:
			var i := members.find(animal)
			flank = Vector2.from_angle(float(i) * TAU / float(members.size()) + prey.facing) * minf(2.0, dist * 0.4)
		animal.target = prey.pos + flank
		_move_toward(animal, delta, 1.6, AnimalState.HUNT)
		return
	_herd_wander(animal, delta)

## The animal's pack (itself included), or just itself.
func _pack(animal: Animal) -> Array:
	var g := group_of(animal)
	return g if not g.is_empty() else [animal]

func _crowd_centre(pos: Vector2, r: float) -> Vector2:
	var near := people_near(pos, r)
	if near.is_empty():
		return pos
	var c := Vector2.ZERO
	for p in near:
		c += p.pos
	return c / float(near.size())

# ── Kept animals: dogs, horses, flocks at camp ───────────────────────────────

func _tick_kept(animal: Animal, delta: float, sensed: bool) -> void:
	# Even kept animals run from a wolf or bear (not dogs: they stand by).
	if animal.animal_type != AnimalType.WOLF and sensed:
		var pred := _nearest_animal(animal, PREDATORS, 4.0, true)
		if pred != null:
			_bolt(animal, pred.pos)
			animal.target = _land_target(animal, animal.leash if animal.leash.x >= 0.0 else animal.target)
	if animal.flee_timer > 0.0:
		animal.flee_timer -= delta
		_move_toward(animal, delta, 1.6, AnimalState.FLEE)
		return
	var anchor := animal.leash if animal.leash.x >= 0.0 else animal.home
	if anchor.x < 0.0:
		_wander(animal, delta)
		return
	var d := animal.pos.distance_to(anchor)
	if d > animal.leash_r:
		var off := Vector2.from_angle(float(animal.anim_id) * 2.39996) * animal.leash_r * 0.5
		animal.target = _land_target(animal, anchor + off)
		var running := d > animal.leash_r * 2.5 + 2.0
		_move_toward(animal, delta, 1.6 if running else 1.0, AnimalState.RUN if running else AnimalState.WALK)
		animal.wander_timer = 0.4
		return
	if is_night and animal.owner_id < 0:
		animal.state = AnimalState.IDLE
		return
	_wander(animal, delta, 0.4, anchor, animal.leash_r)

# ── Eagles: thermals, circling, stooping on rabbits ──────────────────────────

func _tick_eagle(e: Animal, delta: float) -> void:
	var prev_facing := e.facing
	if e.state == AnimalState.EAT:
		# On the ground with its catch.
		e.alt = maxf(0.0, e.alt - 3.0 * delta)
		e.wander_timer -= delta
		if e.wander_timer <= 0.0:
			e.state = AnimalState.SOAR
			_pick_thermal(e)
		e.turn_rate = 0.0
		return
	if e.state == AnimalState.HUNT:
		var prey := get_animal(e.prey_id)
		if prey == null or prey.state == AnimalState.DEAD:
			e.state = AnimalState.SOAR
			e.prey_id = -1
		else:
			var to := prey.pos - e.pos
			var dist := to.length()
			var step := e.speed * 1.6 * delta
			if dist > 0.01:
				e.pos += to / dist * minf(step, dist)
				e.facing = atan2(to.x, to.y)
			# Stoop: drop so as to reach the ground as it arrives.
			var want_alt := clampf(dist * 1.6, 0.25, e.alt)
			e.alt = move_toward(e.alt, want_alt, 9.0 * delta)
			if dist < 0.6 and e.alt < 1.2:
				var odds := 0.45
				if skills != null:
					odds *= 1.0 - 0.5 * skills.escape_of(prey.animal_type, prey.anim_id)
				if randf() < odds:
					kill(prey, "eagle")
					e.state = AnimalState.EAT
					e.wander_timer = 6.0
					e.fed_timer = float(FED_SECONDS[AnimalType.EAGLE]) * (0.8 + randf() * 0.4)
				else:
					# Missed: the rabbit jinks away and learns.
					if skills != null:
						skills.on_successful_escape(prey.animal_type, prey.anim_id)
					prey.escapes += 1
					e.state = AnimalState.SOAR
					e.fed_timer = 25.0
					_pick_thermal(e)
				e.prey_id = -1
			e.turn_rate = 0.0
			return
	# Soaring: circle the thermal, climbing; then glide to another.
	e.state = AnimalState.SOAR
	if e.thermal.x < 0.0:
		_pick_thermal(e)
	var to_t := e.thermal - e.pos
	var dist_t := to_t.length()
	if dist_t > e.circle_r + 1.5:
		# Gliding between thermals: straight, slowly losing height.
		var dir := to_t / dist_t
		e.pos += dir * e.speed * delta
		e.facing = atan2(dir.x, dir.y)
		e.alt = maxf(7.0, e.alt - 0.25 * delta)
		e.circle_ang = (e.pos - e.thermal).angle()
	else:
		# Circling: ride the rising air up.
		e.circle_ang += e.circle_dir * e.speed * 0.7 / e.circle_r * delta
		var want := e.thermal + Vector2.from_angle(e.circle_ang) * e.circle_r
		var mv := want - e.pos
		if mv.length() > 0.001:
			e.facing = atan2(mv.x, mv.y)
		e.pos = e.pos.lerp(want, minf(1.0, delta * 3.0))
		e.alt = minf(16.0, e.alt + 0.6 * delta)
		e.soar_timer -= delta
		if e.soar_timer <= 0.0:
			_pick_thermal(e)
	e.turn_rate = wrapf(e.facing - prev_facing, -PI, PI) / maxf(delta, 0.0001)
	# Looking down for a rabbit in the open.
	e.sense_timer -= delta
	if e.sense_timer <= 0.0:
		e.sense_timer = 1.0
		if e.fed_timer <= 0.0:
			var r := _nearest_animal(e, [AnimalType.RABBIT], 9.0)
			if r != null and randf() < 0.12:
				e.state = AnimalState.HUNT
				e.prey_id = r.anim_id

# ── Movement ─────────────────────────────────────────────────────────────────

func _wander(animal: Animal, delta: float, range_mult: float = 1.0, centre: Vector2 = Vector2(-1, -1), radius: float = -1.0) -> void:
	animal.wander_timer -= delta
	if animal.wander_timer > 0.0:
		if animal.state == AnimalState.WALK:
			_move_toward(animal, delta, 1.0 if centre.x < 0.0 else 0.6, AnimalState.WALK)
		elif animal.state != AnimalState.IDLE and animal.state != AnimalState.EAT:
			animal.state = AnimalState.IDLE
		return

	var roll: float = randf()
	if roll < 0.25:
		animal.state = AnimalState.IDLE
		animal.wander_timer = 1.5 + randf() * 3.0
	elif roll < 0.45 or (centre.x >= 0.0 and roll < 0.6):
		animal.state = AnimalState.EAT
		animal.wander_timer = 2.0 + randf() * 4.0
	else:
		animal.state = AnimalState.WALK
		var want: Vector2
		if centre.x >= 0.0:
			want = centre + Vector2.from_angle(randf() * TAU) * randf() * radius
		else:
			want = animal.pos + Vector2((randf() - 0.5) * 8.0, (randf() - 0.5) * 8.0) * range_mult
		animal.target = _land_target(animal, want)
		animal.wander_timer = 2.0 + randf() * 4.0

## A target inside the world and on land the animal can walk on; falls back
## to standing still rather than wading into the sea.
func _land_target(animal: Animal, want: Vector2) -> Vector2:
	if _world == null:
		return want.clamp(Vector2(1.0, 1.0), Vector2(31.0, 31.0))
	var hi := Vector2(_world.width - 1.5, _world.height - 1.5)
	var t := want.clamp(Vector2(1.5, 1.5), hi)
	for attempt in 4:
		if _world.is_walkable(t.x, t.y):
			return t
		t = (animal.pos + (t - animal.pos) * 0.5).clamp(Vector2(1.5, 1.5), hi)
	return animal.pos

func _move_toward(animal: Animal, delta: float, speed_mult: float, moving_state: int = -1) -> void:
	var diff: Vector2 = animal.target - animal.pos
	var len: float = diff.length()
	if len < 0.1:
		if moving_state != AnimalState.HUNT:
			animal.state = AnimalState.IDLE
			animal.wander_timer = 1.0 + randf() * 2.0
		return
	if moving_state >= 0:
		animal.state = moving_state
	var dir: Vector2 = diff / len
	var next: Vector2 = animal.pos + dir * minf(animal.speed * speed_mult * delta, len)
	# Land animals stop at the water's edge; eagles fly over anything.
	if animal.animal_type != AnimalType.EAGLE and _world and not _world.is_walkable(next.x, next.y):
		animal.state = AnimalState.IDLE
		animal.wander_timer = 0.5
		animal.target = animal.pos
		return
	animal.pos = next
	animal.facing = atan2(dir.x, dir.y)
