class_name Agent

enum State {
	WANDERING,
	GATHERING,
	SLEEPING,
	SOCIALIZING,
	DISCOVERING,
	FISHING,
	PERFORMING,
}

const AGENT_SPEED    := 1.8   # tiles/sec
const HUNGER_DRAIN   := 1.0 / 90.0
const ENERGY_DRAIN   := 1.0 / 200.0
const ENERGY_RECOVER := 1.0 / 20.0
const SOCIAL_COOLDOWN := 4.0

static var _next_id: int = 1

var agent_id: int
var agent_name: String

var pos: Vector2    # tile-space (fractional), x and z stored as x,y
var target: Vector2

var needs: Dictionary = {"hunger": 0.9, "energy": 0.9}
var state: State = State.WANDERING
var knowledge: Dictionary = {}  # id → true

var personality: Dictionary = {
	"curiosity":       0.0,
	"sociability":     0.0,
	"industriousness": 0.0,
	"courage":         0.0,
	"creativity":      0.0,
	"caution":         0.0,
}

var age: float = 0.0
var health: float = 1.0
var max_age: float = 0.0
var life_stage: String = "infant"
var is_adult: bool = false

var reproduction_cooldown: float = 0.0
var social_timer: float = 0.0
var rest_timer: float = 0.0
var discovery_flash: float = 0.0
var starvation_timer: float = 0.0
var fire_cooldown: float = 0.0
var needs_check_timer: float = 0.0
var speech_bubble_timer: float = 0.0
var speech_bubble: String = ""
var night_sleeping: bool = false

var task: String = ""  # "gatherer" | "teacher" | "scout" | "carer" | ""
var home_id: String = ""
var bonded_partner_id: int = -1
var social_history: Dictionary = {}

var parents: Array = []
var children: Array = []

var infected: bool = false
var infection_timer: float = 0.0
var immune_timer: float = 0.0

var is_dead: bool = false
var death_cause: String = ""

var facing: Vector2 = Vector2(0, 1)

var inventory: Inventory
var _last_weather_mult: float = 1.0
var _item_defs: Dictionary = {}
var _season: String = ""

# ── TASKS ─────────────────────────────────────────────────────────────────────
static func get_tasks() -> Dictionary:
	return {
		"gatherer": {"icon": "🌾", "name": "Gatherer", "gather_threshold": 0.5, "gather_bonus": 1.05},
		"teacher":  {"icon": "📢", "name": "Teacher",  "seek_social": true, "spread_bonus": 1.1},
		"scout":    {"icon": "🔭", "name": "Scout",    "wander_radius_bonus": 3, "discovery_bonus": 1.15},
		"carer":    {"icon": "💚", "name": "Carer",    "rest_threshold": 0.35, "rest_bonus": 1.1},
	}

func _init(x: float, z: float) -> void:
	agent_id = _next_id
	_next_id += 1
	agent_name = _random_name()
	pos = Vector2(x, z)
	target = pos

	needs["hunger"] = 0.8 + randf() * 0.2
	needs["energy"] = 0.8 + randf() * 0.2

	personality["curiosity"]       = 0.3 + randf() * 0.5
	personality["sociability"]     = 0.2 + randf() * 0.6
	personality["industriousness"] = 0.3 + randf() * 0.5
	personality["courage"]         = 0.2 + randf() * 0.6
	personality["creativity"]      = 0.2 + randf() * 0.6
	personality["caution"]         = 0.2 + randf() * 0.6

	max_age = 180.0 + randf() * 180.0
	reproduction_cooldown = 24.0 + randf() * 36.0
	social_timer = randf() * SOCIAL_COOLDOWN
	fire_cooldown = 20.0 + randf() * 20.0
	needs_check_timer = 2.0 + randf() * 3.0

	inventory = Inventory.new()

# ── Accessors ──────────────────────────────────────────────────────────────

var curiosity: float:
	get: return personality["curiosity"]

var social_mult: float:
	get: return 0.7 + personality["sociability"] * 0.6

var discovery_mult: float:
	get: return 0.8 + personality["curiosity"] * 0.4

var age_bonus: float:
	get:
		var b := 0.0
		if knowledge.has("fire"):         b += 0.10
		if knowledge.has("shelter"):      b += 0.10
		if knowledge.has("cooking"):      b += 0.15
		if knowledge.has("medicine"):     b += 0.20
		if knowledge.has("clothing"):     b += 0.08
		if knowledge.has("housing"):      b += 0.12
		if knowledge.has("community"):    b += 0.10
		if knowledge.has("agriculture"):  b += 0.15
		if knowledge.has("preservation"): b += 0.10
		return b

var life_expectancy: float:
	get: return max_age * (1.0 + age_bonus)

var is_elderly: bool:
	get: return age >= life_expectancy * 0.75

var speed_mult: float:
	get:
		match life_stage:
			"infant": return 0.5
			"child":  return 0.8
			"elder":  return 0.65
		return 1.0

var gather_mult: float:
	get:
		match life_stage:
			"infant": return 0.3
			"child":  return 0.6
			"elder":  return 0.75
		return 1.0

var is_immune: bool:
	get: return immune_timer > 0.0

# ── Tick ─────────────────────────────────────────────────────────────────────

func tick(delta: float, world: World, all_agents: Array, concept_graph: ConceptGraph,
		  weather_mult: float = 1.0, item_defs: Dictionary = {}, season: String = "spring",
		  time_system: TimeSystem = null) -> void:

	_item_defs = item_defs
	_season = season
	age += delta

	# Starvation
	if needs["hunger"] <= 0.0:
		starvation_timer += delta
		if starvation_timer >= 15.0:
			_drop_all_items(world)
			is_dead = true
			death_cause = "starvation"
			health = 0.0
			return
	else:
		starvation_timer = 0.0

	# Disease
	if immune_timer > 0.0: immune_timer -= delta
	if infected:
		infection_timer += delta
		health = maxf(0.0, health - 0.0005 * delta)
		needs["energy"] = maxf(0.0, needs["energy"] - 0.001 * delta)
		if infection_timer >= 60.0:
			infected = false
			infection_timer = 0.0
			immune_timer = 120.0

	# Old age
	if age > life_expectancy:
		_drop_all_items(world)
		is_dead = true
		death_cause = "old_age"
		health = 0.0
		return

	_update_life_stage()
	is_adult = (life_stage == "adult" or life_stage == "elder")
	if reproduction_cooldown > 0.0: reproduction_cooldown -= delta
	if not _life_stage_can_reproduce(): reproduction_cooldown = maxf(reproduction_cooldown, 5.0)

	# Weather protection
	var env_mult := weather_mult
	if knowledge.has("fire"):     env_mult = maxf(1.0, env_mult - 0.25)
	if knowledge.has("shelter"):  env_mult = maxf(1.0, env_mult - 0.35)
	if knowledge.has("clothing"): env_mult = maxf(1.0, env_mult - 0.20)
	if knowledge.has("housing"):  env_mult = maxf(1.0, env_mult - 0.20)

	# Drain needs
	needs["hunger"] = maxf(0.0, needs["hunger"] - HUNGER_DRAIN * delta)
	var sleeping := state == State.SLEEPING
	if not sleeping:
		needs["energy"] = maxf(0.0, needs["energy"] - ENERGY_DRAIN * delta * env_mult)

	if discovery_flash > 0.0:  discovery_flash -= delta
	if fire_cooldown > 0.0:    fire_cooldown -= delta
	if speech_bubble_timer > 0.0:
		speech_bubble_timer -= delta
		if speech_bubble_timer <= 0.0: speech_bubble = ""

	# Inventory max weight from knowledge
	inventory.max_weight = 10.0 + (2.0 if knowledge.has("weaving") else 0.0) + \
							(4.0 if knowledge.has("animal_domestication") else 0.0)

	_last_weather_mult = env_mult

	# Fire lighting
	if knowledge.has("fire") and env_mult >= 1.2 and fire_cooldown <= 0.0:
		var tile := world.get_tile_f(pos.x, pos.y)
		if not tile.is_empty() and tile["type"] in [World.TileType.FOREST, World.TileType.WOODLAND, World.TileType.GRASS]:
			fire_cooldown = 45.0 + randf() * 30.0
			world.campfire_events.append({"tx": tile["x"], "tz": tile["z"], "agent_name": agent_name})

	# State machine
	match state:
		State.SLEEPING:
			var sleep_mult := 1.6 if knowledge.has("shelter") else 1.0
			if knowledge.has("housing"): sleep_mult *= 1.15
			if night_sleeping: sleep_mult *= 1.5
			var task_bonus: float = float(get_tasks().get(task, {}).get("rest_bonus", 1.0))
			sleep_mult *= task_bonus
			needs["energy"] = minf(1.0, needs["energy"] + ENERGY_RECOVER * delta * 1.4 * sleep_mult)
			rest_timer -= delta
			if rest_timer <= 0.0:
				state = State.WANDERING
				_pick_wander_target(world, all_agents)
			_try_socialise(delta, all_agents, concept_graph)
			return

		State.FISHING:
			rest_timer -= delta
			if rest_timer <= 0.0:
				var fish_yield := 0.5
				if knowledge.has("stone_tools"): fish_yield *= 1.2
				if knowledge.has("cooking"):     fish_yield *= 1.5
				needs["hunger"] = minf(1.0, needs["hunger"] + fish_yield)
				state = State.WANDERING
				_pick_wander_target(world, all_agents)
			_try_socialise(delta, all_agents, concept_graph)
			return

		State.PERFORMING:
			rest_timer -= delta
			if rest_timer <= 0.0:
				state = State.WANDERING
				_pick_wander_target(world, all_agents)
			_try_socialise(delta, all_agents, concept_graph)
			return

	# Periodic re-evaluation
	needs_check_timer -= delta
	if needs_check_timer <= 0.0:
		needs_check_timer = 3.0 + randf() * 4.0
		if state == State.WANDERING or state == State.DISCOVERING:
			_decide_action(world, all_agents, concept_graph, time_system)

	# Movement
	var dx := target.x - pos.x
	var dz := target.y - pos.y
	var dist := sqrt(dx * dx + dz * dz)
	if dist > 0.04:
		var move := minf(AGENT_SPEED * speed_mult * delta, dist)
		var new_x := pos.x + (dx / dist) * move
		var new_z := pos.y + (dz / dist) * move
		if world.can_traverse(new_x, new_z, knowledge):
			pos = Vector2(new_x, new_z)
			facing = Vector2(dx / dist, dz / dist)
		else:
			_pick_wander_target(world, all_agents)
	else:
		pos = target
		_on_arrival(world, all_agents, concept_graph)

	_try_discover(delta, world, concept_graph, all_agents)
	_try_socialise(delta, all_agents, concept_graph)

# ── Arrival ─────────────────────────────────────────────────────────────────

func _on_arrival(world: World, all_agents: Array, concept_graph: ConceptGraph) -> void:
	if state == State.GATHERING:
		var tile := world.get_tile_f(pos.x, pos.y)
		if not tile.is_empty() and tile["type"] in [World.TileType.GRASS, World.TileType.FOREST, World.TileType.WOODLAND]:
			var tool_mult := 1.25 if knowledge.has("stone_tools") else 1.0
			if knowledge.has("metal_tools"):    tool_mult *= 1.25
			if knowledge.has("agriculture") and tile["type"] == World.TileType.GRASS: tool_mult *= 1.35
			var cook_mult := 1.6 if knowledge.has("cooking") else 1.0
			var yield_val: float = maxf(0.15, float(tile["resource"]))
			needs["hunger"] = minf(1.0, needs["hunger"] + 0.60 * tool_mult * cook_mult * yield_val)
			tile["resource"] = maxf(0.0, tile["resource"] - 0.28 / tool_mult)
			if tile.get("depletion_level", -1.0) >= 0.0:
				tile["depletion_level"] = minf(1.0, tile.get("depletion_level", 0.0) + 0.1 / tool_mult)

	_decide_action(world, all_agents, concept_graph, null)

func _decide_action(world: World, all_agents: Array, concept_graph: ConceptGraph, time_system: TimeSystem) -> void:
	var task_def: Dictionary = get_tasks().get(task, {})
	var gather_threshold: float = float(task_def.get("gather_threshold", 0.25))
	var rest_threshold: float = float(task_def.get("rest_threshold", 0.2))
	var env_mult := _last_weather_mult

	if health < 0.40: _try_use_medicine()

	# Time-of-day behaviour
	if time_system != null:
		if time_system.is_night():
			if needs["energy"] < 0.9:
				state = State.SLEEPING
				rest_timer = 14.0 + randf() * 10.0
				night_sleeping = true
				return
		else:
			night_sleeping = false

		if time_system.is_dawn() and needs["hunger"] < 0.75:
			state = State.GATHERING
			_pick_gather_target(world)
			return

	# Critical hunger
	if needs["hunger"] < gather_threshold:
		if _try_eat():
			if needs["hunger"] >= gather_threshold:
				state = State.WANDERING
				_pick_wander_target(world, all_agents)
				return
		state = State.GATHERING
		_pick_gather_target(world)
		return

	# Low energy
	if needs["energy"] < rest_threshold:
		state = State.SLEEPING
		rest_timer = 10.0 + randf() * 8.0
		night_sleeping = false
		return

	# Cold/exposed
	if env_mult >= 1.3 and not knowledge.has("fire") and not knowledge.has("shelter"):
		var warm_tile := world.find_nearest(pos.x, pos.y, [World.TileType.FOREST, World.TileType.WOODLAND], 10.0)
		if not warm_tile.is_empty():
			state = State.WANDERING
			target = Vector2(warm_tile["x"] + 0.5, warm_tile["z"] + 0.5)
			return

	# Moderate hunger (gatherer role)
	if task == "gatherer" and needs["hunger"] < 0.55:
		state = State.GATHERING
		_pick_gather_target(world)
		return

	# Fishing near water
	if knowledge.has("fishing") and needs["hunger"] < 0.7:
		var water_tile := world.find_nearest(pos.x, pos.y, [World.TileType.WATER, World.TileType.BEACH], 4.0)
		if not water_tile.is_empty():
			state = State.FISHING
			rest_timer = 6.0 + randf() * 4.0
			target = Vector2(water_tile["x"] + 0.5, water_tile["z"] + 0.5)
			return

	state = State.WANDERING
	_pick_wander_target(world, all_agents)

# ── Target selection ─────────────────────────────────────────────────────────

func _pick_wander_target(world: World, all_agents: Array = []) -> void:
	var task_def: Dictionary = get_tasks().get(task, {})
	var radius_bonus: int = int(task_def.get("wander_radius_bonus", 0))
	var radius := 4 + int(curiosity * 4) + radius_bonus

	# Bonded partner bias
	if bonded_partner_id >= 0 and not all_agents.is_empty() and randf() < 0.4:
		for other in all_agents:
			if other.agent_id == bonded_partner_id and other.health > 0.0:
				var dx: float = other.pos.x - pos.x
				var dz: float = other.pos.y - pos.y
				var dist := sqrt(dx * dx + dz * dz)
				if dist > 2.0:
					var step := minf(float(radius), dist * 0.7)
					var tx := floori(pos.x + (dx / dist) * step)
					var tz := floori(pos.y + (dz / dist) * step)
					if world.can_traverse(float(tx), float(tz), knowledge):
						target = Vector2(tx + 0.5, tz + 0.5)
						return
				break

	# Random candidates with seasonal scoring
	for _attempt in range(25):
		var tx := floori(pos.x) + randi_range(-radius, radius)
		var tz := floori(pos.y) + randi_range(-radius, radius)
		if world.can_traverse(float(tx), float(tz), knowledge):
			target = Vector2(tx + 0.5, tz + 0.5)
			return

	target = pos

func _pick_gather_target(world: World) -> void:
	var tile := world.find_nearest(pos.x, pos.y, [World.TileType.GRASS, World.TileType.FOREST, World.TileType.WOODLAND], 8.0)
	if not tile.is_empty():
		target = Vector2(tile["x"] + 0.5, tile["z"] + 0.5)
	else:
		_pick_wander_target(world)

# ── Discovery ────────────────────────────────────────────────────────────────

func _try_discover(delta: float, world: World, concept_graph: ConceptGraph, all_agents: Array) -> void:
	var tile := world.get_tile_f(pos.x, pos.y)
	if tile.is_empty(): return
	var discovered := concept_graph.check_discovery(self, tile, delta, world, all_agents)
	if not discovered.is_empty():
		state = State.DISCOVERING
		discovery_flash = 1.5

# ── Social / spreading ───────────────────────────────────────────────────────

func _try_socialise(delta: float, all_agents: Array, concept_graph: ConceptGraph) -> void:
	social_timer -= delta
	if social_timer > 0.0: return
	social_timer = (SOCIAL_COOLDOWN + randf() * 2.0) / social_mult

	for other in all_agents:
		if other == self or other.health <= 0.0: continue
		var dist := pos.distance_to(other.pos)
		if dist < 5.0:
			concept_graph.try_spread(self, other, SOCIAL_COOLDOWN)
			_try_spread_infection(other)
			_track_social_and_bond(other)
			if dist < 3.5: _try_reproduce(other, concept_graph)

func _track_social_and_bond(other: Agent) -> void:
	if not is_adult or not other.is_adult: return
	if bonded_partner_id >= 0 or other.bonded_partner_id >= 0: return
	social_history[other.agent_id] = social_history.get(other.agent_id, 0) + 1
	other.social_history[agent_id] = other.social_history.get(agent_id, 0) + 1
	if social_history[other.agent_id] >= 3 and randf() < 0.05:
		bonded_partner_id = other.agent_id
		other.bonded_partner_id = agent_id

func _try_reproduce(other: Agent, concept_graph: ConceptGraph) -> void:
	if not is_adult or not other.is_adult: return
	if reproduction_cooldown > 0.0 or other.reproduction_cooldown > 0.0: return
	if needs["hunger"] < 0.40 or other.needs["hunger"] < 0.40: return
	if needs["energy"] < 0.20 or other.needs["energy"] < 0.20: return

	var is_bonded := bonded_partner_id == other.agent_id
	var repro_chance := 1.0 if is_bonded else 0.15
	if randf() > repro_chance: return

	var base_cooldown := 45.0 + randf() * 45.0
	var comm_mult := 0.82 if (knowledge.has("community") or other.knowledge.has("community")) else 1.0
	var cooldown := base_cooldown * comm_mult
	reproduction_cooldown = cooldown
	other.reproduction_cooldown = cooldown

	var cx := (pos.x + other.pos.x) / 2.0 + (randf() - 0.5) * 1.5
	var cz := (pos.y + other.pos.y) / 2.0 + (randf() - 0.5) * 1.5
	concept_graph.birth_events.append({
		"x": cx, "z": cz,
		"parent_name": agent_name,
		"parent_a_id": agent_id,
		"parent_b_id": other.agent_id,
		"parent_a_personality": personality.duplicate(),
		"parent_b_personality": other.personality.duplicate(),
	})

func _try_spread_infection(other: Agent) -> void:
	if infected and not other.infected and not other.is_immune:
		var chance := 0.15
		if other.knowledge.has("medicine"): chance *= 0.5
		if randf() < chance:
			other.infected = true
			other.infection_timer = 0.0
	if other.infected and not infected and not is_immune:
		var chance := 0.15
		if knowledge.has("medicine"): chance *= 0.5
		if randf() < chance:
			infected = true
			infection_timer = 0.0

# ── Inventory helpers ─────────────────────────────────────────────────────────

func _try_eat() -> bool:
	if _item_defs.is_empty(): return false
	var food := inventory.get_best_food(_item_defs)
	if food.is_empty(): return false
	var def: Dictionary = _item_defs.get(food["item_id"], {})
	inventory.remove(food["item_id"], 1.0)
	needs["hunger"] = minf(1.0, needs["hunger"] + def.get("effects", {}).get("hunger", 0.10))
	if def.get("effects", {}).has("health"):
		health = minf(1.0, health + def["effects"]["health"])
	return true

func _try_use_medicine() -> void:
	if _item_defs.is_empty() or not inventory.has("medicine"): return
	var def: Dictionary = _item_defs.get("medicine", {})
	inventory.remove("medicine", 1.0)
	health = minf(1.0, health + def.get("effects", {}).get("health", 0.35))

func _drop_all_items(world: World) -> void:
	var items := inventory.drop_all()
	for item in items:
		var tx := floori(pos.x)
		var tz := floori(pos.y)
		# Just consume - tile item system can be added later
		pass

# ── Life stage ───────────────────────────────────────────────────────────────

func _update_life_stage() -> void:
	var ratio := age / life_expectancy
	if ratio < 0.12:     life_stage = "infant"
	elif ratio < 0.25:   life_stage = "child"
	elif ratio < 0.75:   life_stage = "adult"
	else:                life_stage = "elder"

func _life_stage_can_reproduce() -> bool:
	return life_stage == "adult"

# ── Personality inheritance ──────────────────────────────────────────────────

static func inherit_personality(pa: Dictionary, pb: Dictionary) -> Dictionary:
	var traits := ["curiosity", "sociability", "industriousness", "courage", "creativity", "caution"]
	var child := {}
	for t in traits:
		var parent_val: float = (float(pa.get(t, 0.5)) + float(pb.get(t, 0.5))) / 2.0
		var mutation := (randf() - 0.5) * 0.1
		child[t] = clampf(parent_val + mutation, 0.0, 1.0)
	return child

func adopt_task(all_agents: Array) -> void:
	if not task.is_empty() or not knowledge.has("organisation"): return
	var tasks_def := get_tasks()
	var tasks := tasks_def.keys()
	var taken: Array = []
	for a in all_agents:
		if not a.task.is_empty(): taken.append(a.task)
	var available := tasks.filter(func(t): return not (t in taken))
	var pool := available if not available.is_empty() else tasks

	var weights: Array = []
	for t in pool:
		match t:
			"gatherer": weights.append(0.5 + personality["industriousness"])
			"teacher":  weights.append(0.5 + personality["sociability"])
			"scout":    weights.append(0.5 + personality["curiosity"])
			"carer":    weights.append(0.5 + personality["caution"])
			_:          weights.append(1.0)

	var total_w := 0.0
	for w in weights: total_w += w
	var roll := randf() * total_w
	for i in range(pool.size()):
		roll -= weights[i]
		if roll <= 0.0:
			task = pool[i]
			return
	task = pool[-1]

# ── Name generator ───────────────────────────────────────────────────────────

static func _random_name() -> String:
	var syllables := ["ar","el","or","an","en","am","ul","in","er","om","al","ir","un","ae"]
	var len_ := 2 + randi() % 2
	var name_ := ""
	for _i in range(len_):
		name_ += syllables[randi() % syllables.size()]
	return name_.capitalize()
