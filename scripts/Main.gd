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
var disease_system        # DiseaseSystem
var population_manager    # PopulationManager

# Camera
var camera: Camera3D
var _cam_target: Vector3
var _cam_distance: float = 90.0
var _cam_angle_h: float = 0.0         # horizontal orbit
var _cam_angle_v: float = deg_to_rad(55.0) # vertical tilt
var _pan_keys: Dictionary = {}
const PAN_SPEED := 8.0
const ZOOM_MIN := 8.0
# The world is WORLD_WIDTH * TILE_SIZE units across, so the far limit has to
# scale with it or you can never pull back far enough to see the whole map.
const ZOOM_MAX := 340.0

# Lighting
var sun: DirectionalLight3D
var sky_env: WorldEnvironment

# Game state
var game_over: bool = false
var selected_agent: Agent = null
var birth_times: Array = []

# ── Ready ────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_setup_scene()
	_load_data()

func _setup_scene() -> void:
	# Audio (needs to be in scene tree)
	audio_system = AudioSystem.new()
	add_child(audio_system)

	# Camera
	camera = Camera3D.new()
	add_child(camera)
	_cam_target = Vector3(WORLD_WIDTH * TILE_SIZE / 2.0, 0, WORLD_HEIGHT * TILE_SIZE / 2.0)
	_update_camera()

	# Directional light (sun)
	sun = DirectionalLight3D.new()
	sun.light_energy = 1.2
	sun.shadow_enabled = false
	add_child(sun)

	# Ambient via WorldEnvironment
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.53, 0.70, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.ambient_light_energy = 0.8
	sky_env = WorldEnvironment.new()
	sky_env.environment = env
	add_child(sky_env)

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

func _init_world() -> void:
	# Simulation
	world = World.new()
	time_system = TimeSystem.new()
	weather_system = WeatherSystem.new()
	concept_graph = ConceptGraph.new(concepts_data)

	# Agents
	agents.clear()
	var spawn_pts := world.get_spawn_points(AGENT_COUNT)
	for p in spawn_pts:
		var a := Agent.new(float(p["x"]), float(p["z"]))
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
	add_child(agent_renderer)
	agent_renderer.setup(agents)

	# Wildlife
	if animal_renderer:
		animal_renderer.clear()
		animal_renderer.queue_free()
	animal_sim = AnimalSim.new()
	animal_sim.spawn_wildlife(world)
	animal_renderer = AnimalRenderer.new()
	add_child(animal_renderer)
	animal_renderer.setup(animal_sim)

	# Settlement renderer (houses appear once organisation is discovered)
	if settlement_renderer:
		settlement_renderer.clear()
		settlement_renderer.queue_free()
	settlement_renderer = SettlementRenderer.new()
	add_child(settlement_renderer)

	# Environment props (trees, bushes, rocks) — placed once at world init
	if environment_renderer:
		environment_renderer.queue_free()
	environment_renderer = EnvironmentRenderer.new()
	add_child(environment_renderer)
	environment_renderer.setup(world)

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
	tile_items = TileItems.new()
	spatial_grid = SpatialGrid.new()
	animal_skill_system = AnimalSkillSystem.new()
	lineage_tracker = LineageTracker.new()
	disease_system = DiseaseSystem.new()
	population_manager = PopulationManager.new()

	game_over = false
	selected_agent = null
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

func _process(delta: float) -> void:
	_handle_camera_pan(delta)
	if game_over: return

	var game_delta := time_system.update(delta)
	if game_delta <= 0.0:
		return

	var season := time_system.season.to_lower()
	weather_system.update(game_delta, time_system.season)
	world.day = time_system.day
	world.update_resources(game_delta, season)
	world.update_depletion(game_delta)
	world.update_cut_trees(game_delta)
	world.update_glaciers(game_delta, weather_system.temperature)
	world.decay_trade_traffic(time_system.day)

	# Ground-nesting fauna: nests that filled their clutch this tick become
	# new animals.
	for evt in world.update_nests(game_delta):
		_spawn_from_nest(evt)

	# Buildings nearby speed a nest's lay rate — the domestication feedback.
	world.update_domestication(game_delta, _building_positions())

	# Flora slow tick
	world.flora_slow_timer += game_delta
	if world.flora_slow_timer >= 10.0:
		world.flora_slow_tick(world.flora_slow_timer, season)
		world.flora_slow_timer = 0.0

	# Fire system (spreading fires + lightning)
	fire_system.tick(game_delta, world, time_system.game_time, weather_system.is_storm, time_system.day, history_log)
	if fire_system.lightning_fire_pos != Vector2(-1, -1):
		_push_notification("Lightning strikes the forest!")

	# Disaster system
	var prev_disaster: int = disaster_system.current
	disaster_system.tick(game_delta, time_system.day, history_log)
	if disaster_system.current != prev_disaster:
		if disaster_system.current != 0:
			_push_notification(disaster_system.label + " has begun!")
			audio_system.play_disaster()
		else:
			_push_notification("The disaster has passed.")

	# Legacy lightning storms (now handled by FireSystem but keep for safety)
	if weather_system.is_storm:
		_maybe_lightning(game_delta)

	# Spatial grid update (before agent ticks so proximity queries are fresh)
	spatial_grid.update(agents)

	# Tick agents
	for a in agents:
		if a.health > 0.0 and not a.is_dead:
			var w_mult := weather_system.energy_drain_mult_at(a.pos.x, a.pos.y)
			a.tick(game_delta, world, agents, concept_graph, w_mult, item_defs, season,
				   time_system, time_system.day, tile_items, settlement_system, spatial_grid)
			if a.knowledge.has("organisation") and a.task.is_empty():
				a.adopt_task(agents)

	# Handle births
	_handle_births()

	# Handle concept events
	_handle_events()

	# Handle campfires
	_handle_campfires(game_delta)

	# Ecology, conflict, trading, crafting, settlements
	ecology_system.tick(game_delta, world, agents, time_system.day, history_log)
	conflict_system.tick(game_delta, agents, time_system.day, history_log, spatial_grid)
	var was_outbreak: bool = disease_system.outbreak_active
	disease_system.tick(game_delta, agents, time_system.day, history_log, settlement_system)
	if disease_system.outbreak_active != was_outbreak:
		if disease_system.outbreak_active:
			_push_notification("A sickness is spreading!")
		else:
			_push_notification("The sickness has passed.")
	trading_system.tick(game_delta, agents, item_defs, time_system.day, history_log, spatial_grid)
	crafting_system.tick(game_delta, agents, item_defs, time_system.day, history_log)
	settlement_system.tick(game_delta, agents, concept_graph, time_system.day, history_log, spatial_grid)
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
			history_log.add("death", history_log.format_death(a.agent_name, a.death_cause), time_system.day)
			audio_system.play_death()

	# Game over detection
	var alive_count := agents.filter(func(a): return a.health > 0.0 and not a.is_dead).size()
	if not game_over and agents.size() > 0 and alive_count == 0:
		game_over = true
		_show_game_over()

	# Sun position (day/night)
	_update_sun()

	# Tick wildlife
	animal_sim.tick(game_delta, world)
	_tick_population(game_delta)

	# Push any tile changes this frame into the chunked terrain mesh.
	_flush_tile_changes()

	# Rendering
	agent_renderer.update()
	animal_renderer.update()
	_update_settlements()
	_update_hud()

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
		var birth_msg: String = str(evt.get("parent_name", "Someone")) + " has a child — " + child.agent_name
		_push_notification(birth_msg)
		history_log.add("birth", birth_msg, time_system.day)
		audio_system.play_birth()

func _handle_events() -> void:
	for evt in concept_graph.drain_events():
		if evt["type"] == "discovery":
			var concept: Dictionary = concept_graph.concepts.get(str(evt["concept_id"]), {})
			var cname: String = concept.get("name", str(evt["concept_id"]))
			_push_notification(str(evt["agent_name"]) + " discovered " + cname + "!")
			history_log.add("discovery", str(evt["agent_name"]) + " discovered " + cname, time_system.day)
			audio_system.play_discovery()
			var agent: Agent = _find_agent(int(evt["agent_id"]))
			if agent:
				agent.discovery_flash = 1.5
				lineage_tracker.record(str(evt["concept_id"]), agent, time_system.day)
				if evt["concept_id"] == "organisation":
					agent.adopt_task(agents)

func _handle_campfires(delta: float) -> void:
	for evt in world.campfire_events:
		var key := "%d,%d" % [evt["tx"], evt["tz"]]
		if not world.natural_fires.has(key):
			world.natural_fires[key] = {"end_time": time_system.game_time + 40.0 + randf() * 20.0}
	world.campfire_events.clear()

func _maybe_lightning(_delta: float) -> void:
	# Simple: random forest tile catches fire during storm
	if randf() > 0.001: return
	var forest_tiles := world.get_tiles_of_type([World.TileType.FOREST])
	if forest_tiles.is_empty(): return
	var tile: Dictionary = forest_tiles[randi() % forest_tiles.size()]
	var key := "%d,%d" % [tile["x"], tile["z"]]
	world.natural_fires[key] = {"end_time": time_system.game_time + 28.0 + randf() * 18.0}
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
			"weather": weather_system.label,
			"temp": weather_system.temp_label,
			"era": _get_era(discovered.size()),
			"concepts": discovered,
			"selected_agent": selected_agent,
			"disaster": disaster_system.label if disaster_system.current != 0 else "",
			"history": history_log.get_recent(8),
			"settlements": settlement_system.get_settlements().size(),
			"speed": time_system.speed,
			"unlocked_achievements": achievements.get_unlocked_list(),
		})

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

func _update_sun() -> void:
	var tod := time_system.time_of_day
	var sun_angle := (tod - 0.25) * TAU  # noon at tod=0.5
	sun.rotation = Vector3(sun_angle, deg_to_rad(30), 0)
	# Dim at night
	var t := clampf(sin(tod * PI) * 2.0, 0.0, 1.0)
	sun.light_energy = lerpf(0.05, 1.2, t)
	# Sky colour
	var env := sky_env.environment
	if env:
		var day_color := Color(0.53, 0.70, 0.95)
		var night_color := Color(0.04, 0.04, 0.12)
		env.background_color = night_color.lerp(day_color, t)
		env.ambient_light_energy = lerpf(0.15, 0.8, t)

# ── Camera ────────────────────────────────────────────────────────────────────

func _update_camera() -> void:
	var offset := Vector3(
		sin(_cam_angle_h) * cos(_cam_angle_v),
		sin(_cam_angle_v),
		cos(_cam_angle_h) * cos(_cam_angle_v)
	) * _cam_distance
	camera.position = _cam_target + offset
	camera.look_at(_cam_target, Vector3.UP)

func _handle_camera_pan(delta: float) -> void:
	var moved := false
	var fwd := Vector3(sin(_cam_angle_h), 0, cos(_cam_angle_h))
	var right := Vector3(cos(_cam_angle_h), 0, -sin(_cam_angle_h))
	var speed := PAN_SPEED * (_cam_distance / 20.0)

	if _pan_keys.get("w", false): _cam_target -= fwd * speed * delta; moved = true
	if _pan_keys.get("s", false): _cam_target += fwd * speed * delta; moved = true
	if _pan_keys.get("a", false): _cam_target -= right * speed * delta; moved = true
	if _pan_keys.get("d", false): _cam_target += right * speed * delta; moved = true

	const ROT_SPEED := 1.8  # radians/sec
	if _pan_keys.get("q", false): _cam_angle_h -= ROT_SPEED * delta; moved = true
	if _pan_keys.get("e", false): _cam_angle_h += ROT_SPEED * delta; moved = true

	_cam_target.x = clampf(_cam_target.x, 0, WORLD_WIDTH * TILE_SIZE)
	_cam_target.z = clampf(_cam_target.z, 0, WORLD_HEIGHT * TILE_SIZE)

	if moved: _update_camera()

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var e := event as InputEventKey
		var k: Key = e.keycode
		var down: bool = e.pressed
		match k:
			KEY_W: _pan_keys["w"] = down
			KEY_S: _pan_keys["s"] = down
			KEY_A: _pan_keys["a"] = down
			KEY_D: _pan_keys["d"] = down
			KEY_Q: _pan_keys["q"] = down
			KEY_E: _pan_keys["e"] = down
			KEY_R:
				if down: _init_world()
			KEY_H:
				if down: _centre_on_agents()
			KEY_SPACE:
				if down: time_system.set_speed(0.0 if time_system.speed > 0.0 else 1.0)
			KEY_1: if down: time_system.set_speed(1.0)
			KEY_2: if down: time_system.set_speed(5.0)
			KEY_3: if down: time_system.set_speed(20.0)

	if event is InputEventMouseButton:
		# Proportional zoom: a fixed step feels fine up close and glacial when
		# pulled back across a 256-unit world.
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_distance = clampf(_cam_distance * 0.88, ZOOM_MIN, ZOOM_MAX)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_distance = clampf(_cam_distance / 0.88, ZOOM_MIN, ZOOM_MAX)
			_update_camera()

# ── Mouse drag state ─────────────────────────────────────────────────────────

# Left drag: tumble (rotate + tilt). Also used for click-to-select when
# the mouse barely moves (threshold check on release).
var _left_press_pos: Vector2 = Vector2.ZERO
var _left_pressed: bool = false
var _left_is_drag: bool = false
var _left_drag_angle_h: float = 0.0
var _left_drag_angle_v: float = 0.0
const LEFT_DRAG_THRESHOLD := 5.0  # pixels before motion becomes a drag

# Middle / Alt+Left drag: pan
var _pan_drag_start: Vector2 = Vector2.ZERO
var _pan_drag_target: Vector3 = Vector3.ZERO
var _is_pan_dragging: bool = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.alt_pressed:
					# Alt+Left = pan drag (same as middle mouse)
					if mb.pressed:
						_pan_drag_start = mb.position
						_pan_drag_target = _cam_target
						_is_pan_dragging = true
					else:
						_is_pan_dragging = false
				else:
					# Normal left = tumble drag OR click-to-select
					if mb.pressed:
						_left_press_pos = mb.position
						_left_drag_angle_h = _cam_angle_h
						_left_drag_angle_v = _cam_angle_v
						_left_pressed = true
						_left_is_drag = false
					else:
						if _left_pressed and not _left_is_drag:
							_handle_click(mb.position)
						_left_pressed = false
						_left_is_drag = false
			MOUSE_BUTTON_MIDDLE:
				if mb.pressed:
					_pan_drag_start = mb.position
					_pan_drag_target = _cam_target
					_is_pan_dragging = true
				else:
					_is_pan_dragging = false

	if event is InputEventMouseMotion:
		var em := event as InputEventMouseMotion

		# Left drag: tumble (horizontal = orbit, vertical = tilt)
		if _left_pressed:
			if not _left_is_drag and em.position.distance_to(_left_press_pos) > LEFT_DRAG_THRESHOLD:
				_left_is_drag = true
			if _left_is_drag:
				var delta_x: float = (em.position.x - _left_press_pos.x) * 0.005
				var delta_y: float = (em.position.y - _left_press_pos.y) * 0.005
				_cam_angle_h = _left_drag_angle_h - delta_x
				_cam_angle_v = clampf(_left_drag_angle_v + delta_y, deg_to_rad(10.0), deg_to_rad(85.0))
				_update_camera()

		# Pan drag
		if _is_pan_dragging:
			var scale := _cam_distance / 400.0
			var dx: float = (em.position.x - _pan_drag_start.x) * scale
			var dz: float = (em.position.y - _pan_drag_start.y) * scale
			var fwd  := Vector3(sin(_cam_angle_h), 0, cos(_cam_angle_h))
			var right := Vector3(cos(_cam_angle_h), 0, -sin(_cam_angle_h))
			_cam_target = _pan_drag_target - right * dx - fwd * dz
			_cam_target.x = clampf(_cam_target.x, 0, WORLD_WIDTH * TILE_SIZE)
			_cam_target.z = clampf(_cam_target.z, 0, WORLD_HEIGHT * TILE_SIZE)
			_update_camera()

func _centre_on_agents() -> void:
	var alive := agents.filter(func(a): return a.health > 0.0 and not a.is_dead)
	if alive.is_empty(): return
	var cx := 0.0
	var cz := 0.0
	for a in alive:
		cx += a.pos.x * TILE_SIZE
		cz += a.pos.y * TILE_SIZE
	_cam_target = Vector3(cx / alive.size(), 0, cz / alive.size())
	_update_camera()

func _handle_click(screen_pos: Vector2) -> void:
	var from := camera.project_ray_origin(screen_pos)
	var dir  := camera.project_ray_normal(screen_pos)
	if dir.y >= 0.0: return  # Ray going up, ignore
	var t := -from.y / dir.y
	var world_pos := from + dir * t

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

	if selected_agent:
		selected_agent.selected = false
	selected_agent = best
	if selected_agent:
		selected_agent.selected = true

# ── Settlements ───────────────────────────────────────────────────────────────

func _update_settlements() -> void:
	# Only show buildings after organisation is discovered
	var org_known := false
	for a in agents:
		if a.knowledge.has("organisation"):
			org_known = true
			break
	if not org_known:
		return

	# Determine era index for building tier selection
	var discovered_count: int = concept_graph.get_discovered_concepts().size()
	var era_idx: int = _get_era_index(discovered_count)

	# Place buildings wherever there's an active campfire
	var settlement_tiles: Array = []
	for key in world.natural_fires:
		var parts: PackedStringArray = key.split(",")
		if parts.size() == 2:
			settlement_tiles.append([int(parts[0]), int(parts[1])])

	settlement_renderer.sync(settlement_tiles, era_idx)

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
# Felled trees also have to be removed from the prop MultiMesh.
func _flush_tile_changes() -> void:
	for c in world.drain_dirty_tiles():
		var cell: Vector2i = c
		terrain_renderer.rebuild_tile(cell.x, cell.y)
		var tile := world.get_tile(cell.x, cell.y)
		if not tile.is_empty() and bool(tile.get("tree_cut", false)):
			environment_renderer.remove_tree_at(cell.x, cell.y)
	terrain_renderer.flush_dirty()

# ── Utility ───────────────────────────────────────────────────────────────────

func _find_agent(id: int) -> Agent:
	for a in agents:
		if a.agent_id == id:
			return a
	return null
