class_name Agent

enum State {
	WANDERING,
	GATHERING,
	SLEEPING,
	SOCIALIZING,
	DISCOVERING,
	FISHING,
	PERFORMING,
	TRADING,
	RITUAL,
}

const AGENT_SPEED    := 1.8   # tiles/sec
## Evening at the hearth: settled people sit in a ring round the fire from
## dusk until they sleep, and ideas pass faster in the stories told there.
const FIRE_RING_MIN := 1.6
const FIRE_RING_MAX := 3.2
const FIRE_STORY_MULT := 2.0
## Children keep within this many tiles of a parent.
const CHILD_TETHER := 3.0
## A parent with food to spare feeds a hungry child this much at a time.
const FEED_CHILD_AMOUNT := 0.2
const LIFESPAN_DAYS_MIN := 6.0
const LIFESPAN_DAYS_SPREAD := 4.0
const HUNGER_DRAIN   := 1.0 / 90.0
const MAX_CARRY      := 0.6       # food one person can carry home
const ENERGY_DRAIN   := 1.0 / 200.0
const ENERGY_RECOVER := 1.0 / 20.0
const SOCIAL_COOLDOWN := 4.0
const MEMORY_FOOD_CAP := 10
const MEMORY_DANGER_CAP := 5
const DANGER_AVOID_RADIUS := 3.0

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
var selected: bool = false  # picked in the observer view (Main sets it)
var at_fire: bool = false   # sitting at the evening hearth
var chore: String = ""             # set by ForestSystem: "felling a tree", "planting a tree"
var carrying_food: float = 0.0   # surplus gathered once full, carried home to the camp store
var fed_children: int = 0   # times they fed a hungry child (the story reads it)
## Grief: after a partner, child or parent dies, for MOURNING_DAYS they move
## slowly, don't pair or have children, and think of who they lost.
var mourning: float = 0.0
var mourning_for: String = ""
const MOURNING_DAYS := 0.5

# An agent holds ONE vocation, stored here. Tier 1 vocations unlock with
# "organisation"; tier 2 are specialisations gated on a settlement knowing the
# relevant concept. See get_tasks(). The field keeps its original name because
# the HUD and renderers already read it.
var task: String = ""
var home_id: String = ""
var bonded_partner_id: int = -1
var social_history: Dictionary = {}

# Spatial memory. Agents remember where food was and where they were hurt,
# so foraging stops being a blind radial search and danger is avoided.
var memory: Dictionary = {
	"food_sources": [],  # [{x, z, type, last_visited}] capped at MEMORY_FOOD_CAP
	"dangers":      [],  # [{x, z, type, day}]          capped at MEMORY_DANGER_CAP
}

# Rituals: periodic gatherings that lift morale once a group shares beliefs.
var ritual_timer: float = 0.0
var ritual_cooldown: float = 0.0
var ritual_morale: float = 0.0

# Trader journeys between settlements.
var trader_state: String = ""        # "" | "outbound" | "returning"
var trader_target_settlement: int = -1
var trader_home_settlement: int = -1
var trader_cargo: Array = []
var trader_cooldown: float = 0.0

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
var _current_day: int = 0
var _tile_items = null          # TileItems, optional
var _settlement_system = null   # SettlementSystem, optional
var _spatial_grid_ref: WeakRef = null   # SpatialGrid — weak, see _grid()

# ── TASKS ─────────────────────────────────────────────────────────────────────
# One table, two tiers. Tier 1 is the early division of labour that appears
# with "organisation"; tier 2 are specialisations a settlement can only support
# once it knows the gating concept. An agent occupies exactly one at a time and
# is promoted from tier 1 to tier 2 when their settlement's knowledge allows.
static func get_tasks() -> Dictionary:
	return {
		# ── Tier 1 ──
		"gatherer": {"tier": 1, "icon": "🌾", "name": "Gatherer", "gather_threshold": 0.5, "gather_bonus": 1.05},
		"teacher":  {"tier": 1, "icon": "📢", "name": "Teacher",  "seek_social": true, "spread_bonus": 1.1},
		"scout":    {"tier": 1, "icon": "🔭", "name": "Scout",    "wander_radius_bonus": 3, "discovery_bonus": 1.15},
		"carer":    {"tier": 1, "icon": "💚", "name": "Carer",    "rest_threshold": 0.35, "rest_bonus": 1.1},
		# ── Tier 2: gated on "requires", weighted by "trait" ──
		"farmer":   {"tier": 2, "icon": "🌱", "name": "Farmer",   "requires": "agriculture",
					 "trait": "industriousness", "min_trait": 0.5, "gather_bonus": 1.25, "gather_threshold": 0.5},
		"herder":   {"tier": 2, "icon": "🐑", "name": "Herder",   "requires": "animal_domestication",
					 "trait": "caution", "gather_bonus": 1.1},
		"builder":  {"tier": 2, "icon": "🔨", "name": "Builder",  "requires": "construction",
					 "trait": "industriousness", "build_bonus": 1.3},
		"healer":   {"tier": 2, "icon": "⚕", "name": "Healer",   "requires": "medicine",
					 "trait": "caution", "rest_threshold": 0.35, "heal_bonus": 1.4},
		"musician": {"tier": 2, "icon": "🎵", "name": "Musician", "requires": "music",
					 "trait": "creativity", "min_trait": 0.5, "morale_bonus": 1.3, "seek_social": true},
		"trader":   {"tier": 2, "icon": "⚖", "name": "Trader",   "requires": "trade",
					 "trait": "sociability", "trade_bonus": 1.3},
		"guard":    {"tier": 2, "icon": "🛡", "name": "Guard",    "requires": "governance",
					 "trait": "courage", "defence_bonus": 1.35},
	}

# Promote to a tier-2 specialisation when the surrounding group knows the
# gating concept. Knowledge is pooled from nearby agents as a proxy for
# "the settlement knows this".
func maybe_promote_vocation(all_agents: Array) -> bool:
	if not knowledge.has("organisation"):
		return false
	var defs := get_tasks()
	# Already specialised.
	if not task.is_empty() and int(defs.get(task, {}).get("tier", 1)) == 2:
		return false

	var pooled: Dictionary = knowledge.duplicate()
	var considered := 0
	for other in _neighbours(all_agents, 10.0):
		if other == self or other.is_dead or other.health <= 0.0:
			continue
		for k in other.knowledge:
			pooled[k] = true
		considered += 1
		if considered >= 20:
			break

	var candidates: Array = []
	var total_weight := 0.0
	for id in defs:
		var d: Dictionary = defs[id]
		if int(d.get("tier", 1)) != 2:
			continue
		if not pooled.has(str(d.get("requires", ""))):
			continue
		var trait_name := str(d.get("trait", "curiosity"))
		var trait_val: float = float(personality.get(trait_name, 0.0))
		if trait_val < float(d.get("min_trait", 0.0)):
			continue
		var w := 0.4 + trait_val
		candidates.append({"id": id, "w": w})
		total_weight += w

	if candidates.is_empty():
		return false

	var roll := randf() * total_weight
	for c in candidates:
		roll -= float(c["w"])
		if roll <= 0.0:
			_set_vocation(str(c["id"]))
			return true
	_set_vocation(str(candidates[candidates.size() - 1]["id"]))
	return true

# Taking a vocation nudges the personality trait it draws on — people are
# shaped by the work they do.
func _set_vocation(id: String) -> void:
	task = id
	var d: Dictionary = get_tasks().get(id, {})
	var trait_name := str(d.get("trait", ""))
	if trait_name.is_empty() or not personality.has(trait_name):
		return
	personality[trait_name] = minf(1.0, float(personality[trait_name]) + 0.05)

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

	# A life is LIFESPAN_DAYS in-game days (12-20 min at 1x): long enough to
	# follow someone from childhood to old age in one sitting. It was 1.5-3 days,
	# and every world died out of old age by day 4-7 (tools/balance.gd).
	max_age = TimeSystem.DAY_LENGTH * (LIFESPAN_DAYS_MIN + randf() * LIFESPAN_DAYS_SPREAD)
	reproduction_cooldown = 24.0 + randf() * 36.0
	social_timer = randf() * SOCIAL_COOLDOWN
	fire_cooldown = 20.0 + randf() * 20.0
	needs_check_timer = 2.0 + randf() * 3.0
	ritual_cooldown = 30.0 + randf() * 60.0
	trader_cooldown = 60.0 + randf() * 60.0

	# Dictionaries and arrays are reference types in GDScript, so each agent
	# needs its own memory rather than sharing the initialiser's instance.
	memory = {"food_sources": [], "dangers": []}

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
		if mourning > 0.0:
			return _base_speed_mult() * 0.75 * ride_mult
		return _base_speed_mult() * ride_mult

func _base_speed_mult() -> float:
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
		  time_system: TimeSystem = null, current_day: int = 0,
		  tile_items = null, settlement_system = null, spatial_grid = null) -> void:

	_item_defs = item_defs
	_season = season
	_current_day = current_day
	_tile_items = tile_items
	_settlement_system = settlement_system
	_spatial_grid_ref = weakref(spatial_grid) if spatial_grid != null else null
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
	if mourning > 0.0:         mourning -= delta
	if fire_cooldown > 0.0:    fire_cooldown -= delta
	if ritual_cooldown > 0.0:  ritual_cooldown -= delta
	if ritual_morale > 0.0:    ritual_morale -= delta
	if trader_cooldown > 0.0:  trader_cooldown -= delta
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

	if state != State.SOCIALIZING:
		at_fire = false

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
				var fish_yield := 0.5 * AmbientLife.fish_catch(world, pos)
				if knowledge.has("stone_tools"): fish_yield *= 1.2
				if knowledge.has("cooking"):     fish_yield *= 1.5
				needs["hunger"] = minf(1.0, needs["hunger"] + fish_yield)
				state = State.WANDERING
				_pick_wander_target(world, all_agents)
			_try_socialise(delta, all_agents, concept_graph)
			return

		State.SOCIALIZING:
			# Sitting round the hearth until night (or the timer) ends it.
			rest_timer -= delta
			at_fire = true
			var hearth := _home_position(world)
			if hearth.x >= 0.0 and (hearth - pos).length() > 0.01:
				facing = (hearth - pos).normalized()
			if rest_timer <= 0.0 or (time_system != null and time_system.is_night()):
				at_fire = false
				state = State.WANDERING
				needs_check_timer = 0.0
			else:
				_try_socialise(delta, all_agents, concept_graph)
				return

		State.PERFORMING:
			rest_timer -= delta
			if rest_timer <= 0.0:
				state = State.WANDERING
				_pick_wander_target(world, all_agents)
			_try_socialise(delta, all_agents, concept_graph)
			return

		State.RITUAL:
			# Standing together at a shared site. Energy drains slower and the
			# gathering leaves a lasting morale boost.
			ritual_timer -= delta
			needs["energy"] = minf(1.0, needs["energy"] + ENERGY_RECOVER * delta * 0.4)
			if ritual_timer <= 0.0:
				# Boost scales with how many others shared the ritual.
				var companions := 0
				for other in _neighbours(all_agents, 6.0):
					if other != self and not other.is_dead and other.state == State.RITUAL:
						companions += 1
				ritual_morale = 40.0 + float(companions) * 12.0
				ritual_cooldown = 90.0 + randf() * 90.0
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
			var gained: float = 0.60 * tool_mult * cook_mult * yield_val
			# What they can't eat they carry home (SettlementSystem puts it by).
			carrying_food = minf(MAX_CARRY, carrying_food + maxf(0.0, needs["hunger"] + gained - 1.0))
			needs["hunger"] = minf(1.0, needs["hunger"] + gained)
			tile["resource"] = maxf(0.0, tile["resource"] - 0.28 / tool_mult)
			if tile.get("depletion_level", -1.0) >= 0.0:
				tile["depletion_level"] = minf(1.0, tile.get("depletion_level", 0.0) + 0.1 / tool_mult)
			# Worth coming back to — remember it.
			if yield_val > 0.3:
				_remember_food_source(int(tile["x"]), int(tile["z"]), int(tile["type"]))

	_pick_up_ground_items(world)

	if not trader_state.is_empty() and _settlement_system != null:
		_advance_trader_journey(world)
		return

	_decide_action(world, all_agents, concept_graph, null)

func _decide_action(world: World, all_agents: Array, concept_graph: ConceptGraph, time_system: TimeSystem) -> void:
	var task_def: Dictionary = get_tasks().get(task, {})
	var gather_threshold: float = float(task_def.get("gather_threshold", 0.25))
	var rest_threshold: float = float(task_def.get("rest_threshold", 0.2))
	var env_mult := _last_weather_mult

	if health < 0.40: _try_use_medicine()

	# A journey in progress overrides ordinary decision-making.
	if not trader_state.is_empty():
		return

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

		# At dusk, head home. Settled people sit round their hearth until
		# night; others shelter wherever home is.
		if time_system.is_dusk():
			var home := _home_position(world)
			var settled := _settlement_system != null and _settlement_system.get_settlement_for_agent(agent_id) != null
			if settled and needs["hunger"] > 0.2:
				var seat := home + Vector2.from_angle(float(agent_id) * 2.39996) * lerpf(FIRE_RING_MIN, FIRE_RING_MAX, fmod(agent_id * 0.618, 1.0))
				if pos.distance_to(seat) > 0.6:
					state = State.WANDERING
					target = seat
				else:
					state = State.SOCIALIZING
					rest_timer = maxf(5.0, (20.0 - time_system.hour) / 24.0 * TimeSystem.DAY_LENGTH)
				return
			if home.x >= 0.0 and pos.distance_to(home) > 2.0:
				state = State.WANDERING
				target = home
				return

	# Rituals: a shared gathering once the idea exists and others are near.
	if knowledge.has("ritual") and ritual_cooldown <= 0.0 and needs["hunger"] > 0.35 \
	   and needs["energy"] > 0.25:
		if _try_start_ritual(world, all_agents):
			return

	# Trade journeys between settlements.
	if knowledge.has("trade") and trader_cooldown <= 0.0 and _settlement_system != null:
		if _try_start_trader_journey(world):
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

	# Children stay close to a parent.
	if (life_stage == "infant" or life_stage == "child") and not parents.is_empty():
		var parent := _nearest_parent(all_agents)
		if parent and pos.distance_to(parent.pos) > CHILD_TETHER:
			state = State.WANDERING
			target = parent.pos + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
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
	if bonded_partner_id >= 0 and randf() < 0.4:
		var partner: Agent = null
		var grid = _grid()
		if grid != null:
			partner = grid.get_agent(bonded_partner_id)
		else:
			for other in all_agents:
				if other.agent_id == bonded_partner_id:
					partner = other
					break
		if partner != null and partner.health > 0.0:
			var dx: float = partner.pos.x - pos.x
			var dz: float = partner.pos.y - pos.y
			var dist := sqrt(dx * dx + dz * dz)
			if dist > 2.0:
				var step := minf(float(radius), dist * 0.7)
				var tx := floori(pos.x + (dx / dist) * step)
				var tz := floori(pos.y + (dz / dist) * step)
				if world.can_traverse(float(tx), float(tz), knowledge):
					target = Vector2(tx + 0.5, tz + 0.5)
					return

	# Sample candidates and take the best rather than the first traversable one,
	# so season and remembered danger actually steer where agents go.
	var best := Vector2(-1, -1)
	var best_score := -INF
	for _attempt in range(25):
		var tx := floori(pos.x) + randi_range(-radius, radius)
		var tz := floori(pos.y) + randi_range(-radius, radius)
		if not world.can_traverse(float(tx), float(tz), knowledge):
			continue
		var tile := world.get_tile(tx, tz)
		if tile.is_empty():
			continue
		var score := _seasonal_tile_score(tile, _season)
		score -= _danger_penalty(float(tx), float(tz))
		# Mild preference for somewhere with food still on it.
		score += float(tile.get("resource", 0.0)) * 0.25
		# Small random jitter so agents do not all converge on one tile.
		score += randf() * 0.2
		if score > best_score:
			best_score = score
			best = Vector2(tx + 0.5, tz + 0.5)

	if best.x >= 0.0:
		target = best
		return

	target = pos

func _pick_gather_target(world: World) -> void:
	# Head for a remembered food source before falling back to a blind search.
	var best_mem: Dictionary = {}
	var best_score := -INF
	var food: Array = memory["food_sources"]
	for entry_v in food:
		var entry: Dictionary = entry_v
		var ex := float(entry["x"])
		var ez := float(entry["z"])
		if not world.can_traverse(ex, ez, knowledge):
			continue
		var tile := world.get_tile(int(ex), int(ez))
		if tile.is_empty():
			continue
		# Skip somewhere we have already stripped bare.
		if float(tile.get("resource", 0.0)) < 0.2:
			continue
		var dist := pos.distance_to(Vector2(ex, ez))
		# Nearer is better; staler memories are trusted a little less.
		var staleness := float(_current_day - int(entry.get("last_visited", 0)))
		var score := -dist - staleness * 0.4
		if score > best_score:
			best_score = score
			best_mem = entry
	if not best_mem.is_empty():
		target = Vector2(float(best_mem["x"]) + 0.5, float(best_mem["z"]) + 0.5)
		return

	var tile2 := world.find_nearest(pos.x, pos.y, [World.TileType.GRASS, World.TileType.FOREST, World.TileType.WOODLAND], 8.0)
	if not tile2.is_empty():
		target = Vector2(tile2["x"] + 0.5, tile2["z"] + 0.5)
	else:
		_pick_wander_target(world)

# Agents within `radius`. Uses the spatial grid when one is available, which
# turns what would be an O(population) scan per agent per tick into a lookup
# over a handful of cells. Falls back to the linear scan when there is no grid
# (the harness and any caller that does not maintain one).
func _grid():
	if _spatial_grid_ref == null:
		return null
	return _spatial_grid_ref.get_ref()

func _neighbours(all_agents: Array, radius: float) -> Array:
	var grid = _grid()
	if grid != null:
		return grid.get_nearby_agents(pos, radius)
	var out: Array = []
	for other in all_agents:
		if other == self or other.is_dead or other.health <= 0.0:
			continue
		if pos.distance_to(other.pos) <= radius:
			out.append(other)
	return out

# ── Rituals, trade journeys and shelter ──────────────────────────────────────

# The settlement centre if the agent belongs to one, otherwise the nearest
# sheltering tile. Returns (-1, -1) when there is nowhere in particular to go.
func _nearest_parent(all_agents: Array) -> Agent:
	var best: Agent = null
	var grid = _grid()
	for pid in parents:
		var p: Agent = grid.get_agent(int(pid)) if grid != null else null
		if p == null:
			for other in all_agents:
				if other.agent_id == int(pid):
					p = other
					break
		if p == null or p.is_dead or p.health <= 0.0:
			continue
		if best == null or pos.distance_to(p.pos) < pos.distance_to(best.pos):
			best = p
	return best

func _home_position(world: World) -> Vector2:
	if _settlement_system != null:
		var st = _settlement_system.get_settlement_for_agent(agent_id)
		if st != null:
			return st.centre
	var cave := world.find_nearest(pos.x, pos.y, [World.TileType.WOODLAND, World.TileType.FOREST], 8.0)
	if not cave.is_empty():
		return Vector2(float(cave["x"]) + 0.5, float(cave["z"]) + 0.5)
	return Vector2(-1, -1)

func _try_start_ritual(world: World, all_agents: Array) -> bool:
	# Prefer a temple if the settlement has raised one.
	var site := Vector2(-1, -1)
	if _settlement_system != null:
		var st = _settlement_system.get_settlement_for_agent(agent_id)
		if st != null and st.has_temple:
			site = st.temple_pos
		elif st != null:
			site = st.centre

	# Otherwise a ritual needs company to be worth holding.
	if site.x < 0.0:
		var near := 0
		for other in _neighbours(all_agents, 6.0):
			if other != self and not other.is_dead and other.knowledge.has("ritual"):
				near += 1
		if near < 2:
			return false
		site = pos

	if not world.can_traverse(site.x, site.y, knowledge):
		return false

	state = State.RITUAL
	ritual_timer = 8.0 + randf() * 6.0
	target = site
	return true

func _try_start_trader_journey(world: World) -> bool:
	var home = _settlement_system.get_settlement_for_agent(agent_id)
	if home == null:
		return false
	var all_settlements: Array = _settlement_system.get_settlements()
	if all_settlements.size() < 2:
		return false

	# Pick the nearest settlement that is not our own.
	var best = null
	var best_dist := INF
	for st in all_settlements:
		if st.id == home.id:
			continue
		var d: float = pos.distance_to(st.centre)
		if d < best_dist:
			best_dist = d
			best = st
	if best == null:
		return false
	if not world.can_traverse(best.centre.x, best.centre.y, knowledge):
		return false

	# Load whatever we can spare.
	trader_cargo = _load_trade_cargo()
	if trader_cargo.is_empty():
		# Nothing to trade — try again later rather than walking empty-handed.
		trader_cooldown = 45.0 + randf() * 45.0
		return false

	trader_home_settlement = home.id
	trader_target_settlement = best.id
	trader_state = "outbound"
	state = State.TRADING
	target = best.centre
	return true

# Takes a portion of any item the agent holds more than a working amount of.
func _load_trade_cargo() -> Array:
	var cargo: Array = []
	for stack_v in inventory.stacks.duplicate():
		var stack: Dictionary = stack_v
		var item_id := str(stack.get("item_id", ""))
		var qty := float(stack.get("quantity", 0.0))
		if item_id.is_empty() or qty <= 1.0:
			continue
		var spare := floorf(qty * 0.5)
		if spare <= 0.0:
			continue
		inventory.remove(item_id, spare)
		cargo.append({"item_id": item_id, "qty": spare})
	return cargo

# Called on arrival while a journey is in progress.
func _advance_trader_journey(world: World) -> void:
	if trader_state == "outbound":
		var dest = _settlement_system.get_settlement_for_id(trader_target_settlement) \
			if _settlement_system.has_method("get_settlement_for_id") else null
		if dest == null:
			for st in _settlement_system.get_settlements():
				if st.id == trader_target_settlement:
					dest = st
					break
		if dest != null:
			# Deliver the cargo into the host settlement's stores.
			for entry_v in trader_cargo:
				var entry: Dictionary = entry_v
				var qty := float(entry["qty"])
				var def: Dictionary = _item_defs.get(str(entry["item_id"]), {})
				if bool(def.get("edible", false)) or str(def.get("category", "")) == "food":
					dest.food_store += qty
				else:
					dest.wood_store += qty
			dest.last_contact_day = _current_day
		trader_cargo.clear()

		# Head home.
		var home = null
		for st in _settlement_system.get_settlements():
			if st.id == trader_home_settlement:
				home = st
				break
		if home == null:
			_finish_trader_journey(world)
			return
		trader_state = "returning"
		target = home.centre
		return

	_finish_trader_journey(world)

func _finish_trader_journey(world: World) -> void:
	trader_state = ""
	trader_target_settlement = -1
	trader_home_settlement = -1
	trader_cargo.clear()
	trader_cooldown = 120.0 + randf() * 120.0
	state = State.WANDERING
	_pick_wander_target(world)

# ── Memory ───────────────────────────────────────────────────────────────────

func _remember_food_source(tx: int, tz: int, tile_type: int) -> void:
	var food: Array = memory["food_sources"]
	for entry_v in food:
		var entry: Dictionary = entry_v
		if int(entry["x"]) == tx and int(entry["z"]) == tz:
			entry["last_visited"] = _current_day
			return
	food.append({"x": tx, "z": tz, "type": tile_type, "last_visited": _current_day})
	if food.size() > MEMORY_FOOD_CAP:
		# Forget the least recently visited.
		food.sort_custom(func(a, b): return int(a["last_visited"]) < int(b["last_visited"]))
		food.remove_at(0)

func remember_danger(dx: int, dz: int, kind: String) -> void:
	var dangers: Array = memory["dangers"]
	dangers.append({"x": dx, "z": dz, "type": kind, "day": _current_day})
	if dangers.size() > MEMORY_DANGER_CAP:
		dangers.remove_at(0)

func _danger_penalty(tx: float, tz: float) -> float:
	var penalty := 0.0
	var dangers: Array = memory["dangers"]
	for d_v in dangers:
		var d: Dictionary = d_v
		var dist := Vector2(float(d["x"]), float(d["z"])).distance_to(Vector2(tx, tz))
		if dist < DANGER_AVOID_RADIUS:
			penalty += (DANGER_AVOID_RADIUS - dist) * 0.6
	return penalty

# ── Seasonal preference ──────────────────────────────────────────────────────

func _seasonal_tile_score(tile: Dictionary, season: String) -> float:
	if season.to_lower() != "winter":
		return 1.0
	# In winter, open low ground is survivable and high stone is not.
	match int(tile.get("type", -1)):
		World.TileType.GRASS, World.TileType.WOODLAND:
			return 1.3
		World.TileType.MOUNTAIN, World.TileType.STONE:
			return 0.4
	return 1.0

# ── Ground items ─────────────────────────────────────────────────────────────

func _pick_up_ground_items(world: World) -> void:
	if _tile_items == null:
		return
	var tx := int(floor(pos.x))
	var tz := int(floor(pos.y))
	if not _tile_items.has_items(tx, tz):
		return
	var here: Array = _tile_items.get_items(tx, tz)
	for stack_v in here.duplicate():
		var stack: Dictionary = stack_v
		var item_id := str(stack.get("item_id", ""))
		if item_id.is_empty():
			continue
		if inventory.is_full(item_id, _item_defs):
			continue
		var want := float(stack.get("quantity", 0.0))
		var taken: float = _tile_items.pickup(tx, tz, item_id, want)
		if taken > 0.0:
			var leftover := inventory.add(item_id, taken, _item_defs)
			# Anything that would not fit goes straight back on the ground.
			if leftover > 0.0:
				_tile_items.drop(tx, tz, item_id, leftover)

# ── Family ───────────────────────────────────────────────────────────────────

func say(line: String, seconds: float = 4.0) -> void:
	speech_bubble = line
	speech_bubble_timer = seconds

func get_family(all_agents: Array) -> Dictionary:
	var out := {"parents": [], "children": [], "partner": null}
	for other in all_agents:
		if other.agent_id in parents:
			out["parents"].append(other)
		elif other.agent_id in children:
			out["children"].append(other)
		elif bonded_partner_id >= 0 and other.agent_id == bonded_partner_id:
			out["partner"] = other
	return out

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

	for other in _neighbours(all_agents, 5.0):
		if other == self or other.health <= 0.0 or other.is_dead: continue
		var dist := pos.distance_to(other.pos)
		# Stories round the fire carry ideas further than chat in the fields.
		var story := FIRE_STORY_MULT if at_fire and other.at_fire else 1.0
		concept_graph.try_spread(self, other, SOCIAL_COOLDOWN * story)
		# Parents feed their hungry children when they have food to spare.
		if is_adult and other.agent_id in children and other.needs["hunger"] < 0.35 and needs["hunger"] > 0.55:
			needs["hunger"] -= FEED_CHILD_AMOUNT * 0.5
			other.needs["hunger"] = minf(1.0, other.needs["hunger"] + FEED_CHILD_AMOUNT)
			fed_children += 1
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

## Someone close to them died.
func grieve(for_name: String) -> void:
	mourning = TimeSystem.DAY_LENGTH * MOURNING_DAYS
	mourning_for = for_name

func _try_reproduce(other: Agent, concept_graph: ConceptGraph) -> void:
	if mourning > 0.0 or other.mourning > 0.0: return
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

## Names already given. Two people called Unir made the story (and the
## hunches) ambiguous; 2-3 syllables give ~2,900 names and a world sees
## hundreds of people, so collisions were routine.
static var _names_given: Dictionary = {}

static func _random_name() -> String:
	var syllables := ["ar","el","or","an","en","am","ul","in","er","om","al","ir","un","ae"]
	for attempt in 60:
		var len_ := 2 + randi() % 2 + (1 if attempt >= 40 else 0)
		var name_ := ""
		for _i in range(len_):
			name_ += syllables[randi() % syllables.size()]
		name_ = name_.capitalize()
		if not _names_given.has(name_):
			_names_given[name_] = true
			return name_
	return "Ael%d" % _names_given.size()

# ── Animals (AnimalMinds sets these; see docs/features/animals.md) ───────────

## The tame horse this person is riding (-1: on foot). AgentRenderer seats
## them on it.
var riding_horse_id: int = -1
## Speed from the horse under them: 1.8 on open grass, about 1.0 in forest.
var ride_mult: float = 1.0
