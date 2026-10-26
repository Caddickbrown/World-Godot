extends Node3D

const AGENT_COUNT := 40
const WORLD_WIDTH := World.WORLD_WIDTH
const WORLD_HEIGHT := World.WORLD_HEIGHT
const TILE_SIZE := World.TILE_SIZE

# Simulation
var world: World
var agents: Array = []
var concept_graph: ConceptGraph
var time_system: TimeSystem
var weather_system: WeatherSystem
var item_defs: Dictionary = {}
var concepts_data: Array = []

# Renderer nodes (children)
var terrain_renderer: TerrainRenderer
var agent_renderer: AgentRenderer
var animal_renderer: AnimalRenderer
var settlement_renderer: SettlementRenderer
var environment_renderer: EnvironmentRenderer

# Wildlife simulation
var animal_sim: AnimalSim
var animal_skill_system   # AnimalSkillSystem

# Simulation systems
var fire_system           # FireSystem
var disaster_system       # DisasterSystem
var ecology_system        # EcologySystem
var conflict_system       # ConflictSystem
var trading_system        # TradingSystem
var crafting_system       # CraftingSystem
var settlement_system     # SettlementSystem
var tile_items            # TileItems
var spatial_grid          # SpatialGrid
var history_log           # HistoryLog
var achievements          # Achievements
var audio_system          # AudioSystem
var lineage_tracker       # LineageTracker
var hunting_system: HuntingSystem
var forest_system: ForestSystem
## The player-facing story (chronicle, lives, ideas, moments, hunches). Reads
## the simulation, never writes to it.
var story: StoryKeeper
## Where the album and glimmers are kept (tests point this elsewhere).
var album_path := "user://world_album.json"
var _history_seen := 0
var _was_storm := false
var disease_system        # DiseaseSystem
var population_manager    # PopulationManager
## Whales, fish, birds, frogs, bees: the small wild things (AmbientLife.gd).
var ambient_life: AmbientLife
var ambient_renderer: AmbientRenderer

# Views: the observer's eye in the sky, and the wanderer on the ground.
enum ViewMode { OBSERVE, WALK }
var view_mode: ViewMode = ViewMode.OBSERVE
var observer: ObserverCamera
var wanderer: Wanderer
var camera: Camera3D  # the observer's camera (used for picking)
## How close (tiles) the wanderer must be to listen in on someone.
const LISTEN_RADIUS := 2.5

# Lighting
var sky: SkyLook
var disaster_view: DisasterView   # a flood's water over the land
var path_system: PathSystem       # footfall on the tiles (a picture only)
var path_renderer: PathRenderer
var island_history: IslandHistory  # samples for the Island screen's graphs

# Game state
var game_over: bool = false
var selected_agent: Agent = null
var birth_times: Array = []

# ── Ready ────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_setup_scene()
	_load_data()
	_begin.call_deferred()

## A real game (Main is the scene the game launched, not a test or a capture)
## opens on the look picker with the clock held until you begin.
func _begin() -> void:
	if not is_inside_tree() or get_tree().current_scene != self:
		return
	var hud := get_node_or_null("HUD")
	if hud and hud.has_method("open_look"):
		_set_speed(0.0)
		hud.open_look(true)

func _setup_scene() -> void:
	# Audio (needs to be in scene tree)
	audio_system = AudioSystem.new()
	add_child(audio_system)

	observer = ObserverCamera.new()
	observer.bounds = Vector2(WORLD_WIDTH * TILE_SIZE, WORLD_HEIGHT * TILE_SIZE)
	observer.target = Vector3(observer.bounds.x / 2.0, 0, observer.bounds.y / 2.0)
	observer.ground_fn = func(x: float, z: float) -> float:
		return world.surface_y(x / TILE_SIZE, z / TILE_SIZE) if world else 0.0
	add_child(observer)
	camera = observer.camera
	observer.clicked.connect(_handle_click)

	wanderer = Wanderer.new()
	add_child(wanderer)

	# Sky, sun, moon and haze (follows the look style).
	sky = SkyLook.new()
	add_child(sky)
	disaster_view = DisasterView.new()
	add_child(disaster_view)

func _load_data() -> void:
	# Load concepts
	var f := FileAccess.open("res://data/concepts.json", FileAccess.READ)
	if f:
		var json := JSON.new()
		var err := json.parse(f.get_as_text())
		f.close()
		if err == OK:
			concepts_data = json.data
		else:
			push_error("Failed to parse concepts.json: " + json.get_error_message())
	else:
		push_error("Could not open data/concepts.json")

	# Load items
	f = FileAccess.open("res://data/items.json", FileAccess.READ)
	if f:
		var json := JSON.new()
		var err := json.parse(f.get_as_text())
		f.close()
		if err == OK:
			for item in json.data:
				item_defs[item["id"]] = item
	else:
		push_warning("Could not open data/items.json — inventory disabled")

	_init_world()

## Fixed seed for reproducible worlds (capture tool, tests); -1 = random.
var world_seed: int = -1

func _init_world() -> void:
	# Simulation
	world = World.new(world_seed)
	world.heightfield = Heightfield.new().build(world)
	time_system = TimeSystem.new()
	weather_system = WeatherSystem.new()
	concept_graph = ConceptGraph.new(concepts_data)

	# Agents
	agents.clear()
	var spawn_pts := world.get_spawn_points(AGENT_COUNT)
	for p in spawn_pts:
		var a := Agent.new(float(p["x"]), float(p["z"]))
		# Founders arrive as young adults; born at age 0 they spent their first
		# day as infants and nobody could pair up or teach.
		a.age = a.max_age * (0.26 + randf() * 0.2)
		agents.append(a)

	# Terrain renderer
	if terrain_renderer:
		terrain_renderer.queue_free()
	terrain_renderer = TerrainRenderer.new()
	add_child(terrain_renderer)
	terrain_renderer.setup(world)

	# Agent renderer
	if agent_renderer:
		agent_renderer.queue_free()
	agent_renderer = AgentRenderer.new()
	agent_renderer.world = world
	add_child(agent_renderer)
	agent_renderer.setup(agents)

	# Wildlife
	if animal_renderer:
		animal_renderer.clear()
		animal_renderer.queue_free()
	animal_sim = AnimalSim.new()
	animal_sim.spawn_wildlife(world)
	animal_renderer = AnimalRenderer.new()
	animal_renderer.world = world
	add_child(animal_renderer)
	animal_renderer.setup(animal_sim)

	# Settlement renderer (houses appear once organisation is discovered)
	if settlement_renderer:
		settlement_renderer.clear()
		settlement_renderer.queue_free()
	settlement_renderer = SettlementRenderer.new()
	settlement_renderer.world = world
	add_child(settlement_renderer)

	# Environment props (trees, bushes, rocks) — placed once at world init
	if environment_renderer:
		environment_renderer.queue_free()
	environment_renderer = EnvironmentRenderer.new()
	add_child(environment_renderer)
	environment_renderer.setup(world)

	# Worn earth where people walk, and the island's history for the graphs.
	path_system = PathSystem.new()
	if path_renderer:
		path_renderer.queue_free()
	path_renderer = PathRenderer.new()
	path_renderer.world = world
	add_child(path_renderer)
	island_history = IslandHistory.new()

	# Small wild things, with their own dice (never the simulation's).
	if ambient_renderer:
		ambient_renderer.queue_free()
	ambient_life = AmbientLife.new().setup(world)
	ambient_renderer = AmbientRenderer.new()
	add_child(ambient_renderer)
	ambient_renderer.setup(ambient_life, world)

	# Simulation systems
	history_log = HistoryLog.new()
	achievements = Achievements.new()
	fire_system = FireSystem.new()
	disaster_system = DisasterSystem.new()
	ecology_system = EcologySystem.new()
	conflict_system = ConflictSystem.new()
	trading_system = TradingSystem.new()
	crafting_system = CraftingSystem.new()
	settlement_system = SettlementSystem.new()
	conflict_system.settlement_system = settlement_system
	settlement_system.world = world
	hunting_system = HuntingSystem.new()
	forest_system = ForestSystem.new()
	agent_renderer.settlement_system = settlement_system
	tile_items = TileItems.new()
	spatial_grid = SpatialGrid.new()
	animal_skill_system = AnimalSkillSystem.new()
	lineage_tracker = LineageTracker.new()
	disease_system = DiseaseSystem.new()
	population_manager = PopulationManager.new()

	story = StoryKeeper.new()
	story.witness_fn = _is_witnessed
	story.setup(concept_graph, agents, album_path)
	story.chronicle_added.connect(_on_chronicle)
	story.moment_unlocked.connect(_on_moment)
	_history_seen = 0
	_was_storm = false

	game_over = false
	_select(null)
	if view_mode == ViewMode.WALK:
		set_view_mode(ViewMode.OBSERVE)
	wanderer.world = world
	birth_times.clear()

	# Founders spawn as a cluster somewhere in the world, so open the camera on
	# them rather than on the geometric centre of an empty map.
	_centre_on_agents()

	# Wire HUD speed buttons back to Main
	var hud := get_node_or_null("HUD")
	if hud and hud.has_method("set_main"):
		hud.set_main(self)

	_update_hud()

# ── Process (game loop) ───────────────────────────────────────────────────────

## Opt-in timing of each stage of a simulated frame (tools/profile.gd).
var profiling := false
var profile: Dictionary = {}       # stage -> microseconds, summed
var _prof_t := 0

## This frame's stages alone (tools/profile.gd keeps the worst frames).
var frame_profile: Dictionary = {}

func _prof_start() -> void:
	if profiling:
		_prof_t = Time.get_ticks_usec()
		frame_profile = {}

func _prof(stage: String) -> void:
	if not profiling:
		return
	var now := Time.get_ticks_usec()
	profile[stage] = int(profile.get(stage, 0)) + now - _prof_t
	frame_profile[stage] = int(frame_profile.get(stage, 0)) + now - _prof_t
	_prof_t = now

func _process(delta: float) -> void:
	_update_view_overlays()
	if game_over: return

	var game_delta := time_system.update(delta)
	if game_delta <= 0.0:
		# Paused: the world stands still, but what you see (labels, pins, the
		# inspector) still follows the camera and selection.
		agent_renderer.update()
		_update_hud()
		return

	_prof_start()
	var season := time_system.season.to_lower()
	weather_system.update(game_delta, time_system.season, world, time_system.hour)
	_prof("~weather")
	world.day = time_system.day
	world.update_resources(game_delta, season)
	_prof("~world.update_resources")
	world.update_depletion(game_delta)
	world.update_cut_trees(game_delta)
	world.update_glaciers(game_delta, weather_system.temperature)
	world.decay_trade_traffic(time_system.day)
	_prof("~world depletion/cut/glaciers/traffic")

	# Ground-nesting fauna: nests that filled their clutch this tick become
	# new animals.
	for evt in world.update_nests(game_delta):
		_spawn_from_nest(evt)

	# Buildings nearby speed a nest's lay rate — the domestication feedback.
	world.update_domestication(game_delta, _building_positions())
	_prof("~nests, domestication")

	# Flora slow tick
	world.flora_slow_timer += game_delta
	if world.flora_slow_timer >= 10.0:
		world.flora_slow_tick(world.flora_slow_timer, season)
		world.flora_slow_timer = 0.0
	_prof("~flora slow tick")

	# Fire system (spreading fires + lightning)
	fire_system.tick(game_delta, world, time_system.game_time, weather_system.is_storm, time_system.day, history_log)
	if fire_system.lightning_fire_pos != Vector2(-1, -1):
		_push_notification("Lightning strikes the forest!")
	_prof("~fire")

	# Disaster system
	var prev_disaster: int = disaster_system.current
	disaster_system.tick(game_delta, time_system.day, history_log, world, agents)
	if disaster_system.current != prev_disaster:
		if disaster_system.current != 0:
			_push_notification(disaster_system.label + " has begun!")
			audio_system.play_disaster()
		else:
			_push_notification("The disaster has passed.")

	# Legacy lightning storms (now handled by FireSystem but keep for safety)
	if weather_system.is_storm:
		_maybe_lightning(game_delta)

	_prof("world, weather, fire, disasters")
	# Spatial grid update (before agent ticks so proximity queries are fresh)
	spatial_grid.update(agents)

	# Tick agents
	for a in agents:
		if a.health > 0.0 and not a.is_dead:
			var w_mult := weather_system.energy_drain_mult_at(a.pos.x, a.pos.y)
			a.tick(game_delta, world, agents, concept_graph, w_mult, item_defs, season,
				   time_system, time_system.day, tile_items, settlement_system, spatial_grid)
			if a.fxb("unlocks_tasks") and a.task.is_empty():
				a.adopt_task(agents)

	_prof("people (Agent ticks)")
	# Handle births
	_handle_births()

	# Handle concept events
	_handle_events()

	# Handle campfires
	_handle_campfires(game_delta)

	_prof("births, idea events, campfires")
	# Ecology, conflict, trading, crafting, settlements
	ecology_system.tick(game_delta, world, agents, time_system.day, history_log)
	_prof("~ecology")
	conflict_system.tick(game_delta, agents, time_system.day, history_log, spatial_grid)
	_prof("~conflict")
	var was_outbreak: bool = disease_system.outbreak_active
	disease_system.tick(game_delta, agents, time_system.day, history_log, settlement_system)
	if disease_system.outbreak_active != was_outbreak:
		if disease_system.outbreak_active:
			_push_notification("A sickness is spreading!")
		else:
			_push_notification("The sickness has passed.")
	_prof("ecology, conflict, disease")
	trading_system.tick(game_delta, agents, item_defs, time_system.day, history_log, spatial_grid)
	for kill in hunting_system.tick(game_delta, agents, animal_sim, spatial_grid):
		story.on_hunt(kill["hunter"], int(kill["prey_type"]), int(kill["shared"]))
	_prof("trading, hunting")
	# Firsts people did (the first boat, climb, cooked meal...): told once.
	for d in concept_graph.drain_deeds():
		story.add("people", str(d["text"]), d["pos"], [int(d["id"])], true)
		var who: Agent = _find_agent(int(d["id"]))
		if who:
			story.life_of(who).events.append({"day": time_system.day, "text": str(d["text"]), "kind": "people"})
	for evt in forest_system.tick(game_delta, world, agents, settlement_system, season, time_system.day):
		story.on_forest(evt)
	_prof("forest")
	crafting_system.tick(game_delta, agents, item_defs, time_system.day, history_log)
	settlement_system.tick(game_delta, agents, concept_graph, time_system.day, history_log, spatial_grid)
	_prof("crafting, settlements")
	tile_items.tick_spoilage(game_delta, item_defs, disaster_system.get_spoilage_mult())
	animal_skill_system.tick_passive(game_delta)

	# Vocations: agents specialise as their settlement's knowledge allows.
	# Checked on a slow cadence — it pools nearby agents' knowledge and is far
	# too expensive to run for every agent every frame.
	_vocation_timer += game_delta
	if _vocation_timer >= VOCATION_INTERVAL:
		_vocation_timer = 0.0
		for a in agents:
			if not a.is_dead and a.health > 0.0:
				a.maybe_promote_vocation(agents)

	# Achievements
	var new_achievements: Array = achievements.tick(agents, concept_graph, time_system.day)
	for ach in new_achievements:
		var aname: String = str(ach.get("name", ""))
		_push_notification("Achievement: " + aname + "!")
		audio_system.play_achievement()
		history_log.add("achievement", "Achievement unlocked: " + aname, time_system.day)

	# Drop items on death
	for a in agents:
		if a.is_dead and not bool(a.get_meta("items_dropped", false)):
			tile_items.drop_agent_items(a, world)
			a.set_meta("items_dropped", true)

	# Prune expired fires
	for key in world.natural_fires.keys():
		if time_system.game_time >= world.natural_fires[key]["end_time"]:
			world.natural_fires.erase(key)

	# Log deaths
	for a in agents:
		if a.is_dead and not bool(a.get_meta("death_logged", false)):
			a.set_meta("death_logged", true)
			a.set_meta("died_at", time_system.game_time)
			history_log.add("death", history_log.format_death(a.agent_name, a.death_cause), time_system.day)
			var camp = settlement_system.get_settlement_for_agent(a.agent_id)
			concept_graph.note_death(a, agents, time_system.day, camp.centre if camp else Vector2(-1, -1))
			story.on_death(a)
			_grieve_for(a)
			audio_system.play_death()

	# Game over detection
	var alive_count := agents.filter(func(a): return a.health > 0.0 and not a.is_dead).size()
	if not game_over and agents.size() > 0 and alive_count == 0:
		game_over = true
		_show_game_over()
	elif alive_count > 0:
		_bury_the_dead()

	# Sun position (day/night)
	_update_sun()

	_prof("vocations, achievements, deaths, sun")
	# Tick wildlife
	animal_sim.tick(game_delta, world)
	ambient_life.tick(game_delta, time_system.hour, time_system.season, agents, weather_system.is_raining)
	for evt in ambient_life.drain_events():
		story.on_wild(evt, agents)
	_tick_population(game_delta)
	_tick_animal_minds(game_delta)

	_prof("animals, animal minds, ambient life")
	# Push any tile changes this frame into the chunked terrain mesh.
	_flush_tile_changes()
	_prof("tile redraws (terrain, flora)")
	path_system.tick(game_delta, agents, world, settlement_system.get_settlements(), time_system.day)
	_prof("path footfall")
	path_renderer.sync(path_system, delta)
	_prof("path drawing")
	island_history.observe(self)
	_prof("island history")

	_feed_story(game_delta, alive_count)

	_prof("story")
	# Rendering
	agent_renderer.update()
	_prof("draw people")
	animal_renderer.update()
	_prof("draw animals")
	_update_settlements()
	_prof("draw settlements")
	_update_hud()
	_prof("HUD")

## The dead lie where they fell for a while (mourners gather), then are
## buried: their figure goes and they stop being ticked. Their story stays in
## StoryKeeper. The last bodies stay if no one is left to bury them.
func _bury_the_dead() -> void:
	var now := time_system.game_time
	var buried: Array = []
	for a in agents:
		if a.is_dead and a.has_meta("died_at") and now - float(a.get_meta("died_at")) > BURY_AFTER:
			buried.append(a)
	for a in buried:
		agents.erase(a)
		agent_renderer.remove_agent(a)
		if selected_agent == a:
			follow(null)

# ── Event handlers ─────────────────────────────────────────────────────────────

func _handle_births() -> void:
	var alive := agents.filter(func(a): return a.health > 0.0 and not a.is_dead)
	var capacity := world.get_carrying_capacity()
	for evt in concept_graph.drain_birth_events():
		if alive.size() >= capacity: break
		var bx: float = float(evt["x"])
		var bz: float = float(evt["z"])
		if not world.is_walkable(bx, bz):
			var tile := world.find_nearest(bx, bz, [World.TileType.GRASS, World.TileType.FOREST, World.TileType.WOODLAND], 4.0)
			if tile.is_empty(): continue
			bx = float(tile["x"]) + 0.5
			bz = float(tile["z"]) + 0.5
		var child := Agent.new(bx, bz)

		if evt.has("parent_a_id"):
			child.parents.append(evt["parent_a_id"])
			var pa: Agent = _find_agent(int(evt["parent_a_id"]))
			if pa: pa.children.append(child.agent_id)
		if evt.has("parent_b_id"):
			child.parents.append(evt["parent_b_id"])
			var pb: Agent = _find_agent(int(evt["parent_b_id"]))
			if pb: pb.children.append(child.agent_id)

		if evt.has("parent_a_personality") and evt.has("parent_b_personality"):
			child.personality = Agent.inherit_personality(
				evt["parent_a_personality"] as Dictionary, evt["parent_b_personality"] as Dictionary)

		agents.append(child)
		agent_renderer.add_agent(child)
		birth_times.append(time_system.game_time)
		alive.append(child)
		story.on_birth(child, _find_agent(int(evt.get("parent_a_id", -1))), _find_agent(int(evt.get("parent_b_id", -1))))
		var birth_msg: String = str(evt.get("parent_name", "Someone")) + " has a child — " + child.agent_name
		_push_notification(birth_msg)
		history_log.add("birth", birth_msg, time_system.day)
		audio_system.play_birth()

func _handle_events() -> void:
	for evt in concept_graph.drain_events():
		if evt["type"] == "spread":
			story.on_spread(_find_agent(int(evt["agent_id"])), _find_agent(int(evt.get("teacher_id", -1))), str(evt["concept_id"]))
		elif evt["type"] == "discovery":
			var concept: Dictionary = concept_graph.concepts.get(str(evt["concept_id"]), {})
			var cname: String = concept.get("name", str(evt["concept_id"]))
			_push_notification(str(evt["agent_name"]) + " discovered " + cname + "!")
			history_log.add("discovery", str(evt["agent_name"]) + " discovered " + cname, time_system.day)
			audio_system.play_discovery()
			var agent: Agent = _find_agent(int(evt["agent_id"]))
			if agent:
				agent.discovery_flash = 1.5
				agent.say(cname + "!", 4.0)
				lineage_tracker.record(str(evt["concept_id"]), agent, time_system.day)
				story.on_discovery(agent, str(evt["concept_id"]))
				if agent.fxb("unlocks_tasks") and agent.task.is_empty():
					agent.adopt_task(agents)

# ── Story ────────────────────────────────────────────────────────────────────

## Settlement, weather and other world news, forwarded from the history log
## (the systems already write it) into the story, with the moment it unlocks.
const WORLD_NEWS := {
	"settlement": [["New camp founded", "first_camp"], ["grown into hamlet", "hamlet"],
		["elevated to named", "hamlet"], ["made contact", "contact"], ["packed up and moved", "camp_moves"],
		["the first larder", "larder"]],
	"ecology": [["where the woods burned", "woods_return"]],
	"fire": [["Lightning", "lightning"]],
	"disease": [], "disaster": [], "trade": [], "war": [], "craft": [],
}

func _feed_story(game_delta: float, alive_count: int) -> void:
	var fresh: int = history_log.total_added - _history_seen
	_history_seen = history_log.total_added
	if fresh > 0:
		for e in history_log.entries.slice(maxi(0, history_log.entries.size() - fresh)):
			var t := str(e.get("type", ""))
			if not WORLD_NEWS.has(t):
				continue
			var moment := ""
			for rule in WORLD_NEWS[t]:
				if str(e["msg"]).contains(rule[0]):
					moment = rule[1]
			story.on_world(_reword(str(e["msg"])), _news_pos(t), moment)
	var storm: bool = weather_system.is_storm
	if storm != _was_storm:
		_was_storm = storm
		story.on_world("A storm rolls in." if storm else "The storm has blown through.",
			Vector2(-1, -1), "" if storm else "storm_passed")
	if observer.distance > 280.0 and view_mode == ViewMode.OBSERVE:
		story.on_player("whole_island")
	story.tick(game_delta, agents, time_system.day, time_system.hour, alive_count)

## The systems log in a terse voice; the chronicle speaks more warmly.
static func _reword(msg: String) -> String:
	var m := msg.trim_suffix(".")
	var camp := RegEx.create_from_string("New camp founded at \\(.*\\) with (\\d+) members: '(.*)'").search(m)
	if camp:
		return "%s people settled down together and called the place %s." % [camp.get_string(1), camp.get_string(2)]
	var grew := RegEx.create_from_string("Camp has grown into hamlet '(.*)'").search(m)
	if grew:
		return "%s has grown from a camp into a hamlet." % grew.get_string(1)
	var town := RegEx.create_from_string("Hamlet elevated to named settlement '(.*)'").search(m)
	if town:
		return "%s has writing now, and has become a town." % town.get_string(1)
	var moved := RegEx.create_from_string("The people of '(.*)' packed up and moved (.*), to better land").search(m)
	if moved:
		return "The land round %s was stripped bare, so its people packed up and walked %s to better ground." % [moved.get_string(1), moved.get_string(2)]
	var larder := RegEx.create_from_string("Food put by in '(.*)' fed someone hungry").search(m)
	if larder:
		return "At %s, food put by on good days fed someone on a lean one." % larder.get_string(1)
	var met := RegEx.create_from_string("Settlements '(.*)' and '(.*)' made contact").search(m)
	if met:
		return "The people of %s and %s have met." % [met.get_string(1), met.get_string(2)]
	if m.begins_with("Lightning struck a forest"):
		return "Lightning set the forest alight."
	return m + "."

func _news_pos(t: String) -> Vector2:
	if t == "fire" and fire_system.lightning_fire_pos != Vector2(-1, -1):
		return fire_system.lightning_fire_pos
	if t == "ecology" and ecology_system.return_pos != Vector2(-1, -1):
		return ecology_system.return_pos
	if t == "settlement":
		var all: Array = settlement_system.get_settlements()
		if not all.is_empty():
			return all[-1].centre
	return Vector2(-1, -1)

## Could the player see this? Following someone involved always counts; an
## unknown place counts; otherwise it has to be on screen and close enough to
## make out (or near the wisp).
func _is_witnessed(tile_pos: Vector2, agent_ids: Array) -> bool:
	if selected_agent and selected_agent.agent_id in agent_ids:
		return true
	if tile_pos.x < 0.0:
		return true
	var p := Vector3(tile_pos.x * TILE_SIZE, world.surface_y(tile_pos.x, tile_pos.y) + 1.0, tile_pos.y * TILE_SIZE)
	if view_mode == ViewMode.WALK:
		return p.distance_to(wanderer.world_position()) < WITNESS_WALK_RANGE
	return observer.distance < WITNESS_SKY_RANGE and camera.is_position_in_frustum(p)

const BURY_AFTER := TimeSystem.DAY_LENGTH * 0.5   # game-seconds a body lies before burial
const WITNESS_SKY_RANGE := 200.0
const WITNESS_WALK_RANGE := 40.0

func _on_chronicle(entry: Dictionary) -> void:
	var hud := get_node_or_null("HUD")
	if hud and hud.has_method("on_chronicle"):
		hud.on_chronicle(entry)

func _on_moment(_id: String, title: String) -> void:
	_push_notification("Witnessed: " + title)

func _handle_campfires(delta: float) -> void:
	for evt in world.campfire_events:
		var key := "%d,%d" % [evt["tx"], evt["tz"]]
		if not world.natural_fires.has(key):
			world.natural_fires[key] = {"end_time": time_system.game_time + 40.0 + randf() * 20.0}
	world.campfire_events.clear()

## In a storm, now and then lightning sets a wood alight. A per-second chance
## (it was rolled per frame, so it depended on the frame rate).
const LIGHTNING_FIRE_PER_SECOND := 0.02

func _maybe_lightning(delta: float) -> void:
	if randf() > LIGHTNING_FIRE_PER_SECOND * delta: return
	var forest_tiles := world.get_tiles_of_type([World.TileType.FOREST])
	if forest_tiles.is_empty(): return
	var tile: Dictionary = forest_tiles[randi() % forest_tiles.size()]
	var key := "%d,%d" % [tile["x"], tile["z"]]
	world.natural_fires[key] = {"end_time": time_system.game_time + 28.0 + randf() * 18.0}
	if sky and sky.weather_view:
		var tx := float(tile["x"]) + 0.5
		var tz := float(tile["z"]) + 0.5
		sky.weather_view.strike_at(Vector3(tx * TILE_SIZE, world.surface_y(tx, tz), tz * TILE_SIZE))
	_push_notification("Lightning strikes the forest!")

# ── Notifications ─────────────────────────────────────────────────────────────

var _notifications: Array = []  # Array of {msg, timer}

func _set_speed(s: float) -> void:
	time_system.set_speed(s)

func _push_notification(msg: String) -> void:
	_notifications.append({"msg": msg, "timer": 4.0})
	var hud := get_node_or_null("HUD")
	if hud and hud.has_method("show_notification"):
		hud.show_notification(msg)
	else:
		print("[World] ", msg)

# ── HUD ───────────────────────────────────────────────────────────────────────

func _update_hud() -> void:
	var hud := get_node_or_null("HUD")
	if not hud: return
	var alive := agents.filter(func(a): return a.health > 0.0 and not a.is_dead).size()
	var capacity := world.get_carrying_capacity()
	var discovered := concept_graph.get_discovered_concepts()
	if hud.has_method("update"):
		hud.update({
			"population": alive,
			"capacity": capacity,
			"day": time_system.day,
			"season": time_system.season,
			"hour": time_system.hour,
			# Where you're looking, as the sky shows it (not the worst zone anywhere).
			"weather": weather_system.label_at(_focus_tile().x, _focus_tile().y),
			"temp": "%.0f°C" % weather_system.temperature_at(_focus_tile().x, _focus_tile().y),
			"era": _get_era(discovered.size()),
			"concepts": discovered,
			"selected_agent": selected_agent,
			"selected_family": _family_line(selected_agent),
			"selected_home": _home_line(selected_agent),
			"disaster": disaster_system.label if disaster_system.current != 0 else "",
			"history": history_log.get_recent(8),
			"settlements": settlement_system.get_settlements().size(),
			"speed": time_system.speed,
			"unlocked_achievements": achievements.get_unlocked_list(),
		})

func _family_line(a: Agent) -> String:
	if a == null:
		return ""
	var fam: Dictionary = a.get_family(agents)
	var parts: Array = []
	if fam["partner"]:
		parts.append("Partner: " + (fam["partner"] as Agent).agent_name)
	var kids: Array = (fam["children"] as Array).map(func(c): return c.agent_name)
	if not kids.is_empty():
		parts.append("Children: " + ", ".join(kids.slice(0, 4)) + (" +%d" % (kids.size() - 4) if kids.size() > 4 else ""))
	var ps: Array = (fam["parents"] as Array).map(func(c): return c.agent_name)
	if not ps.is_empty():
		parts.append("Child of " + " and ".join(ps))
	return "\n".join(parts) if not parts.is_empty() else "No family yet"

func _home_line(a: Agent) -> String:
	if a == null or settlement_system == null:
		return ""
	var st = settlement_system.get_settlement_for_agent(a.agent_id)
	if st == null:
		return "No settled home"
	return "Lives at " + (st.name if not str(st.name).is_empty() else "a camp")

func _get_era(n: int) -> String:
	if n == 0:  return "Stone Age"
	if n < 5:   return "Early Stone Age"
	if n < 10:  return "Late Stone Age"
	if n < 16:  return "Bronze Age"
	if n < 22:  return "Iron Age"
	if n < 30:  return "Classical Age"
	return "Advanced Age"

func _get_era_index(n: int) -> int:
	if n == 0:  return 0
	if n < 5:   return 1
	if n < 10:  return 2
	if n < 16:  return 3
	if n < 22:  return 4
	return 5

func _show_game_over() -> void:
	var hud := get_node_or_null("HUD")
	if hud and hud.has_method("show_game_over"):
		hud.show_game_over(time_system.day, concept_graph.get_discovered_concepts().size())
	else:
		print("[World] GAME OVER — Day ", time_system.day)

# ── Sun ──────────────────────────────────────────────────────────────────────

## The tile the eye is on: the wisp when walking, else the observer's target.
func _focus_tile() -> Vector2:
	var f: Vector3 = wanderer.world_position() if view_mode == ViewMode.WALK else observer.target
	return Vector2(f.x, f.z) / TILE_SIZE

func _update_sun() -> void:
	var focus: Vector3 = wanderer.world_position() if view_mode == ViewMode.WALK else observer.target
	# What you see is the weather where you're looking (and clouds, rain and
	# rainbows over the rest of the island), not the worst zone anywhere.
	sky.watch_weather(weather_system, focus, get_process_delta_time() * time_system.speed)
	var season_look := SeasonLook.blend(time_system.game_time / TimeSystem.DAY_LENGTH)
	terrain_renderer.set_season(season_look)
	environment_renderer.set_season(season_look)
	disaster_view.update(disaster_system, world)
	sky.set_time(time_system.time_of_day)

# ── Views and input ──────────────────────────────────────────────────────────

func set_view_mode(mode: ViewMode) -> void:
	view_mode = mode
	var walking := mode == ViewMode.WALK
	if walking:
		# Land where the observer was looking, or beside the person followed.
		var p := observer.target / TILE_SIZE
		wanderer.place_at(Vector2(p.x, p.z))
		wanderer.cam_yaw = observer.angle_h
		if story: story.on_player("walk")
	else:
		observer.look_at_point(wanderer.world_position())
	observer.release_keys()
	if agent_renderer:
		agent_renderer.listening_id = -1
	observer.active = not walking
	wanderer.active = walking
	observer.camera.current = not walking
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if walking else Input.MOUSE_MODE_VISIBLE

func _view_distance() -> float:
	return wanderer.cam_distance if view_mode == ViewMode.WALK else observer.distance

func _update_view_overlays() -> void:
	if agent_renderer == null:
		return
	agent_renderer.view_distance = _view_distance()
	agent_renderer.walker_pos = wanderer.world_position() if view_mode == ViewMode.WALK else Vector3.INF
	agent_renderer.look_point = wanderer.world_position() if view_mode == ViewMode.WALK else observer.target
	if view_mode == ViewMode.WALK and time_system:
		wanderer.set_lantern(1.0 - clampf(sin(time_system.time_of_day * PI) * 2.0 - 0.4, 0.0, 1.0))
	var hud := get_node_or_null("HUD")
	if hud and hud.has_method("set_prompt"):
		var near := nearest_agent_to_wanderer() if view_mode == ViewMode.WALK else null
		hud.set_prompt("E — listen in on " + near.agent_name if near else "")
		hud.set_view_hint(view_mode == ViewMode.WALK, observer.is_following())

## The living person closest to the wanderer within LISTEN_RADIUS, or null.
func nearest_agent_to_wanderer() -> Agent:
	var best: Agent = null
	var best_d := LISTEN_RADIUS
	for a in agents:
		if a.is_dead or a.health <= 0.0:
			continue
		var d: float = a.pos.distance_to(wanderer.tile_pos)
		if d < best_d:
			best_d = d
			best = a
	return best

## Listen in on someone: the inspector opens on them and their thought shows
## over their head. The wanderer is unseen, so nothing in the world changes.
func listen_to_nearest() -> Agent:
	var a := nearest_agent_to_wanderer()
	_select(a)
	agent_renderer.listening_id = a.agent_id if a else -1
	if a: story.on_player("listen", a.agent_name)
	return a

## Partner, children and parents grieve when someone dies.
func _grieve_for(dead: Agent) -> void:
	for a in agents:
		if a.is_dead or a == dead:
			continue
		var relation := ""
		if a.bonded_partner_id == dead.agent_id: relation = "partner"
		elif a.agent_id in dead.children: relation = "parent"
		elif a.agent_id in dead.parents: relation = "child"
		if relation != "":
			a.grieve(dead.agent_name)
			story.on_grief(a, dead, relation)

## Point the sky camera at a tile (chronicle entries are clickable).
func look_at_tile(tile_pos: Vector2) -> void:
	if view_mode == ViewMode.WALK:
		set_view_mode(ViewMode.OBSERVE)
	observer.stop_following()
	observer.look_at_point(Vector3(tile_pos.x * TILE_SIZE, 0.0, tile_pos.y * TILE_SIZE))
	observer.distance = minf(observer.distance, 45.0)
	observer.apply()

## The UI look changed (T); the world's look follows it once it has two.
func apply_style() -> void:
	sky.apply_style()
	terrain_renderer.rebuild()
	environment_renderer.setup(world)
	agent_renderer.restyle()
	animal_renderer.restyle()
	settlement_renderer.restyle()
	disaster_view.apply_style()
	path_renderer.restyle()
	ambient_renderer.restyle()

func follow(agent: Agent) -> void:
	_select(agent)
	if agent == null:
		observer.stop_following()
		return
	observer.follow_target_fn = func() -> Vector3:
		if agent.is_dead or agent.health <= 0.0:
			return Vector3.INF
		return Vector3(agent.pos.x * TILE_SIZE, 0.0, agent.pos.y * TILE_SIZE)

func _select(agent: Agent) -> void:
	if selected_agent:
		selected_agent.selected = false
	selected_agent = agent
	if selected_agent:
		selected_agent.selected = true

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_TAB:
			set_view_mode(ViewMode.OBSERVE if view_mode == ViewMode.WALK else ViewMode.WALK)
		KEY_ESCAPE:
			if view_mode == ViewMode.WALK and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				follow(null)
		KEY_E:
			if view_mode == ViewMode.WALK: listen_to_nearest()
		KEY_F:
			if view_mode == ViewMode.OBSERVE:
				if observer.is_following(): observer.stop_following()
				elif selected_agent: follow(selected_agent)
		KEY_R:
			_init_world()
		KEY_H:
			if view_mode == ViewMode.OBSERVE: _centre_on_agents()
		KEY_SPACE:
			time_system.set_speed(0.0 if time_system.speed > 0.0 else 1.0)
		KEY_1: time_system.set_speed(1.0)
		KEY_2: time_system.set_speed(5.0)
		KEY_3: time_system.set_speed(20.0)

func _centre_on_agents() -> void:
	var alive := agents.filter(func(a): return a.health > 0.0 and not a.is_dead)
	if alive.is_empty(): return
	var cx := 0.0
	var cz := 0.0
	for a in alive:
		cx += a.pos.x * TILE_SIZE
		cz += a.pos.y * TILE_SIZE
	observer.stop_following()
	observer.look_at_point(Vector3(cx / alive.size(), 0, cz / alive.size()))

func _handle_click(screen_pos: Vector2) -> void:
	var from := camera.project_ray_origin(screen_pos)
	var dir  := camera.project_ray_normal(screen_pos)
	if dir.y >= 0.0: return  # Ray going up, ignore
	var world_pos := ground_hit(from, dir)

	# Find nearest agent to click
	var best: Agent = null
	var best_dist := 3.0  # tiles radius
	for a in agents:
		if a.health <= 0.0 or a.is_dead: continue
		var ax: float = a.pos.x * TILE_SIZE
		var az: float = a.pos.y * TILE_SIZE
		var dist := Vector2(world_pos.x - ax, world_pos.z - az).length()
		if dist < best_dist:
			best_dist = dist
			best = a

	# Picking someone follows them; clicking anything else lets go and says
	# what's there (an animal, a building, the ground).
	follow(best)
	if best == null:
		var hud := get_node_or_null("HUD")
		if hud and hud.has_method("show_inspect"):
			hud.show_inspect(Inspect.describe(self, world_pos))

## Where a ray from the camera meets the ground (the heightfield, not y = 0,
## which put clicks on a hillside metres away from what was under the cursor).
func ground_hit(from: Vector3, dir: Vector3) -> Vector3:
	var t := 0.0
	var step := 1.0
	for i in 600:
		var p := from + dir * t
		var gy := maxf(world.surface_y(p.x / TILE_SIZE, p.z / TILE_SIZE), 0.0)
		if p.y <= gy:
			# Back up and close in on the crossing.
			var lo := t - step
			var hi := t
			for k in 8:
				var mid := (lo + hi) * 0.5
				var q := from + dir * mid
				if q.y <= maxf(world.surface_y(q.x / TILE_SIZE, q.z / TILE_SIZE), 0.0):
					hi = mid
				else:
					lo = mid
			return from + dir * hi
		t += step
	return from + dir * ((0.0 - from.y) / dir.y)

# ── Settlements ───────────────────────────────────────────────────────────────

func _update_settlements() -> void:
	var all: Array = settlement_system.get_settlements()
	settlement_renderer.darkness = sky.darkness(time_system.time_of_day)
	settlement_renderer.sync(all, world.natural_fires)
	environment_renderer.set_clearings(settlement_renderer.clearings())
	terrain_renderer.set_camps(all.map(func(st): return st.centre * TILE_SIZE))

# ── New system helpers ────────────────────────────────────────────────────────

const VOCATION_INTERVAL := 12.0
var _vocation_timer: float = 0.0

# Maps PopulationManager's species ids onto AnimalSim's type enum.
const SPECIES_TO_TYPE := {
	"deer":   AnimalSim.AnimalType.DEER,
	"wolf":   AnimalSim.AnimalType.WOLF,
	"sheep":  AnimalSim.AnimalType.SHEEP,
	"horse":  AnimalSim.AnimalType.HORSE,
	"rabbit": AnimalSim.AnimalType.RABBIT,
	"fox":    AnimalSim.AnimalType.FOX,
}

# Settlement centres double as "buildings" for the domestication bonus.
func _building_positions() -> Array:
	var out: Array = []
	if settlement_system == null:
		return out
	for st in settlement_system.get_settlements():
		out.append(st.centre)
	return out

func _spawn_from_nest(evt: Dictionary) -> void:
	var species := str(evt.get("species", ""))
	if not SPECIES_TO_TYPE.has(species):
		return
	var tx := float(evt["x"]) + 0.5
	var tz := float(evt["z"]) + 0.5
	animal_sim.spawn_one(int(SPECIES_TO_TYPE[species]), tx, tz)
	world.consume_nest_spawn(int(evt["x"]), int(evt["z"]))

# Lotka-Volterra population dynamics. PopulationManager owns the maths and
# returns spawn/cull requests; applying them to the live animals is our job.
func _tick_population(game_delta: float) -> void:
	var live_counts: Dictionary = {}
	for species in SPECIES_TO_TYPE:
		live_counts[species] = 0
	for a in animal_sim.animals:
		if a.health <= 0.0:
			continue
		for species in SPECIES_TO_TYPE:
			if int(SPECIES_TO_TYPE[species]) == a.animal_type:
				live_counts[species] = int(live_counts[species]) + 1
				break

	population_manager.tick(game_delta, world, time_system.day, live_counts, history_log)

	for req in population_manager.get_spawn_requests():
		var species := str(req["species"])
		if not SPECIES_TO_TYPE.has(species):
			continue
		var positions: Array = req.get("positions", [])
		for i in range(int(req["count"])):
			var p: Vector2 = positions[i] if i < positions.size() else Vector2(-1, -1)
			if p.x < 0.0:
				continue
			animal_sim.spawn_one(int(SPECIES_TO_TYPE[species]), p.x, p.y)

	for req in population_manager.get_cull_requests():
		var species := str(req["species"])
		if not SPECIES_TO_TYPE.has(species):
			continue
		var want := int(req["count"])
		for a in animal_sim.animals:
			if want <= 0:
				break
			if a.health > 0.0 and a.animal_type == int(SPECIES_TO_TYPE[species]):
				a.health = 0.0
				want -= 1

# Terrain is chunk-meshed, so changed tiles rebuild only their own chunk.
# Felled trees vanish from the flora, and come back when they regrow.
func _flush_tile_changes() -> void:
	for c in world.drain_dirty_tiles():
		var cell: Vector2i = c
		terrain_renderer.rebuild_tile(cell.x, cell.y)
		environment_renderer.mark_dirty(cell.x, cell.y)
	terrain_renderer.flush_dirty()
	_prof("~terrain redraw")
	# Trees that grew a size, were felled, planted or burnt: their chunks redraw
	# a few at a time.
	for c in world.drain_flora_dirty():
		environment_renderer.mark_dirty(c.x, c.y)
	environment_renderer.flush()

# ── Utility ───────────────────────────────────────────────────────────────────

func _find_agent(id: int) -> Agent:
	for a in agents:
		if a.agent_id == id:
			return a
	return null

# ── Animal minds (appended; see docs/features/animals.md) ────────────────────

## Packs, taming, riding, flocks at camp and the rare predator attack.
## Built lazily for each new world so _reset() needs no edit.
var animal_minds: AnimalMinds

func _tick_animal_minds(game_delta: float) -> void:
	if animal_minds == null or animal_minds.sim != animal_sim:
		animal_minds = AnimalMinds.new()
		animal_minds.setup(world, animal_sim, population_manager, animal_skill_system)
	for evt in animal_minds.tick(game_delta, agents, settlement_system, time_system, history_log):
		story.add(str(evt["kind"]), str(evt["text"]), evt["pos"], evt["ids"], bool(evt["major"]))
		var who = evt.get("who")
		if who != null and str(evt.get("life", "")) != "":
			story.life_of(who).events.append({"day": time_system.day, "text": str(evt["life"]), "kind": "people"})
