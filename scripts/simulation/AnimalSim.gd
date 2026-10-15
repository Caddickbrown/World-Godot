class_name AnimalSim
extends RefCounted

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
}

enum AnimalState {
	IDLE = 0,
	WALK = 1,
	RUN  = 2,
	EAT  = 3,
	FLEE = 4,
	HUNT = 5,
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

var animals: Array = []
var _next_id: int = 0
## The world they live on. Targets used to be clamped to (31, 31), a leftover
## of the 32x32 map, so every animal drifted into one corner (now open sea).
var _world: World = null

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
	return 1.5

func spawn_wildlife(world: World) -> void:
	_world = world
	animals.clear()
	_next_id = 0

	# Wildlife density scales with the map. 35 animals was tuned for a 32x32
	# world; on 128x128 that leaves the map empty.
	var area_scale: float = float(world.width * world.height) / (32.0 * 32.0)
	var land_count: int = clampi(int(35.0 * sqrt(area_scale) * 1.6), 35, 220)
	var land_pts: Array = world.get_land_spawn_points(land_count)
	for i in range(land_pts.size()):
		var pt: Dictionary = land_pts[i]
		var x: float = float(pt["x"]) + randf() * 0.6 + 0.2
		var z: float = float(pt["z"]) + randf() * 0.6 + 0.2
		var tile: Dictionary = world.get_tile(int(pt["x"]), int(pt["z"]))
		var tile_type: int = int(tile.get("type", 0))
		var t: int = _pick_type_for_biome(tile_type, i)
		var a := Animal.new(_next_id, t, x, z)
		_next_id += 1
		animals.append(a)

	# Eagles always soar regardless of biome. Spread them over the whole map —
	# the old fixed 4..28 range put every eagle in one corner of a large world.
	var eagle_count: int = clampi(int(4.0 * sqrt(area_scale)), 4, 16)
	for _i in range(eagle_count):
		var ex: float = randf() * float(world.width)
		var ez: float = randf() * float(world.height)
		var eagle := Animal.new(_next_id, AnimalType.EAGLE, ex, ez)
		_next_id += 1
		eagle.state = AnimalState.SOAR
		animals.append(eagle)

# Spawns a single animal of the given type. Used by nesting sites hatching a
# clutch and by PopulationManager reintroducing a locally extinct species.
func spawn_one(t: int, x: float, z: float) -> Animal:
	var a := Animal.new(_next_id, t, x, z)
	_next_id += 1
	if t == AnimalType.EAGLE:
		a.state = AnimalState.SOAR
	animals.append(a)
	return a

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

# ── Tick ─────────────────────────────────────────────────────────────────────

func tick(delta: float, world: World) -> void:
	if world != null:
		_world = world
	for a in animals:
		var animal: Animal = a as Animal
		if animal == null: continue
		if animal.state == AnimalState.DEAD: continue
		_tick_animal(animal, delta)

func _tick_animal(animal: Animal, delta: float) -> void:
	match animal.animal_type:
		AnimalType.WOLF, AnimalType.BEAR:
			_tick_predator(animal, delta)
		AnimalType.EAGLE:
			_tick_eagle(animal, delta)
		_:
			_tick_herbivore(animal, delta)

func _tick_predator(animal: Animal, delta: float) -> void:
	var prey_types: Array
	if animal.animal_type == AnimalType.WOLF:
		prey_types = [AnimalType.DEER, AnimalType.SHEEP, AnimalType.RABBIT]
	else:
		prey_types = [AnimalType.DEER, AnimalType.SHEEP, AnimalType.PIG]

	var prey: Animal = _find_nearest_of_types(animal, prey_types, 10.0)
	if prey:
		var dist: float = animal.pos.distance_to(prey.pos)
		if dist < 0.4:
			prey.health = 0.0
			prey.state = AnimalState.DEAD
			animal.state = AnimalState.EAT
			animal.wander_timer = 4.0
		else:
			animal.state = AnimalState.HUNT
			animal.target = prey.pos
			_move_toward(animal, delta, 1.8)
	else:
		_wander(animal, delta)

func _tick_eagle(animal: Animal, delta: float) -> void:
	animal.state = AnimalState.SOAR
	animal.wander_timer -= delta
	if animal.wander_timer <= 0.0:
		var w := float(_world.width) if _world else 32.0
		var h := float(_world.height) if _world else 32.0
		animal.target = Vector2(3.0 + randf() * (w - 6.0), 3.0 + randf() * (h - 6.0))
		animal.wander_timer = 4.0 + randf() * 6.0
	_move_toward(animal, delta, 1.0)

func _tick_herbivore(animal: Animal, delta: float) -> void:
	var threats: Array = [AnimalType.WOLF, AnimalType.BEAR]
	var threat: Animal = _find_nearest_of_types(animal, threats, 5.0)
	if threat:
		animal.state = AnimalState.FLEE
		animal.flee_timer = 3.5
		var flee_dir: Vector2 = (animal.pos - threat.pos).normalized()
		animal.target = _land_target(animal, animal.pos + flee_dir * 10.0)

	animal.flee_timer -= delta
	if animal.flee_timer > 0.0:
		_move_toward(animal, delta, 1.7)
		return

	if animal.state == AnimalState.FLEE:
		animal.state = AnimalState.IDLE
	_wander(animal, delta)

func _wander(animal: Animal, delta: float) -> void:
	animal.wander_timer -= delta
	if animal.wander_timer > 0.0:
		if animal.state == AnimalState.WALK:
			_move_toward(animal, delta, 1.0)
		return

	var roll: float = randf()
	if roll < 0.25:
		animal.state = AnimalState.IDLE
		animal.wander_timer = 1.5 + randf() * 3.0
	elif roll < 0.45:
		animal.state = AnimalState.EAT
		animal.wander_timer = 2.0 + randf() * 4.0
	else:
		animal.state = AnimalState.WALK
		var dx: float = (randf() - 0.5) * 8.0
		var dz: float = (randf() - 0.5) * 8.0
		animal.target = _land_target(animal, animal.pos + Vector2(dx, dz))
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

func _move_toward(animal: Animal, delta: float, speed_mult: float) -> void:
	var diff: Vector2 = animal.target - animal.pos
	var len: float = diff.length()
	if len < 0.1:
		animal.state = AnimalState.IDLE
		animal.wander_timer = 1.0 + randf() * 2.0
		return
	var dir: Vector2 = diff / len
	var next: Vector2 = animal.pos + dir * animal.speed * speed_mult * delta
	# Land animals stop at the water's edge; eagles fly over anything.
	if animal.animal_type != AnimalType.EAGLE and _world and not _world.is_walkable(next.x, next.y):
		animal.state = AnimalState.IDLE
		animal.wander_timer = 0.5
		return
	animal.pos = next
	animal.facing = atan2(dir.x, dir.y)

func _find_nearest_of_types(animal: Animal, types: Array, max_dist: float) -> Animal:
	var best: Animal = null
	var best_dist: float = max_dist
	for a in animals:
		var other: Animal = a as Animal
		if other == null or other == animal: continue
		if other.state == AnimalState.DEAD: continue
		var found: bool = false
		for t in types:
			if other.animal_type == int(t):
				found = true
				break
		if not found: continue
		var d: float = animal.pos.distance_to(other.pos)
		if d < best_dist:
			best_dist = d
			best = other
	return best
