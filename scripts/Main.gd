extends Node3D

const AGENT_COUNT := 12
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

# Camera
var camera: Camera3D
var _cam_target: Vector3
var _cam_distance: float = 40.0
var _cam_angle_h: float = 0.0         # horizontal orbit
var _cam_angle_v: float = deg_to_rad(55.0) # vertical tilt
var _pan_keys: Dictionary = {}
const PAN_SPEED := 8.0
const ZOOM_MIN := 8.0
const ZOOM_MAX := 100.0

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

	game_over = false
	selected_agent = null
	birth_times.clear()

	_update_hud()

# ── Process (game loop) ───────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_handle_camera_pan(delta)

	var game_delta := time_system.update(delta)
	if game_delta <= 0.0:
		return

	var season := time_system.season.to_lower()
	weather_system.update(game_delta, time_system.season)
	world.day = time_system.day
	world.update_resources(game_delta, season)
	world.update_depletion(game_delta)
	world.update_cut_trees(game_delta)

	# Flora slow tick
	world.flora_slow_timer += game_delta
	if world.flora_slow_timer >= 10.0:
		world.flora_slow_tick(world.flora_slow_timer, season)
		world.flora_slow_timer = 0.0

	# Lightning during storms
	if weather_system.is_storm:
		_maybe_lightning(game_delta)

	# Tick agents
	for a in agents:
		if a.health > 0.0 and not a.is_dead:
			var w_mult := weather_system.energy_drain_mult_at(a.pos.x, a.pos.y)
			a.tick(game_delta, world, agents, concept_graph, w_mult, item_defs, season, time_system)
			if a.knowledge.has("organisation") and a.task.is_empty():
				a.adopt_task(agents)

	# Handle births
	_handle_births()

	# Handle concept events
	_handle_events()

	# Handle campfires
	_handle_campfires(game_delta)

	# Prune expired fires
	for key in world.natural_fires.keys():
		if time_system.game_time >= world.natural_fires[key]["end_time"]:
			world.natural_fires.erase(key)

	# Game over detection
	var alive_count := agents.filter(func(a): return a.health > 0.0 and not a.is_dead).size()
	if not game_over and agents.size() > 0 and alive_count == 0:
		game_over = true
		_show_game_over()

	# Sun position (day/night)
	_update_sun()

	# Rendering
	agent_renderer.update()
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
			var tile := world.find_nearest(bx, bz, [World.TileType.GRASS, World.TileType.FOREST], 4.0)
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
		_push_notification(evt.get("parent_name", "Someone") + " has a child — " + child.agent_name)

func _handle_events() -> void:
	for evt in concept_graph.drain_events():
		if evt["type"] == "discovery":
			var concept: Dictionary = concept_graph.concepts.get(str(evt["concept_id"]), {})
			var cname: String = concept.get("name", str(evt["concept_id"]))
			_push_notification(str(evt["agent_name"]) + " discovered " + cname + "!")
			var agent: Agent = _find_agent(int(evt["agent_id"]))
			if agent:
				agent.discovery_flash = 1.5
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
		})

func _get_era(n: int) -> String:
	if n == 0:  return "Stone Age"
	if n < 5:   return "Early Stone Age"
	if n < 10:  return "Late Stone Age"
	if n < 16:  return "Bronze Age"
	if n < 22:  return "Iron Age"
	if n < 30:  return "Classical Age"
	return "Advanced Age"

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
			KEY_R:
				if down: _init_world()  # Reset
			KEY_H:
				if down: _centre_on_agents()

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_distance = clampf(_cam_distance - 4.0, ZOOM_MIN, ZOOM_MAX)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_distance = clampf(_cam_distance + 4.0, ZOOM_MIN, ZOOM_MAX)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_click(event.position)

var _drag_start: Vector2
var _drag_cam_target: Vector3
var _is_dragging: bool = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE or \
		   (event.button_index == MOUSE_BUTTON_LEFT and event.alt_pressed):
			if event.pressed:
				_drag_start = event.position
				_drag_cam_target = _cam_target
				_is_dragging = true
			else:
				_is_dragging = false

	if event is InputEventMouseMotion and _is_dragging:
		var em := event as InputEventMouseMotion
		var scale := _cam_distance / 400.0
		var dx: float = (em.position.x - _drag_start.x) * scale
		var dz: float = (em.position.y - _drag_start.y) * scale
		var fwd := Vector3(sin(_cam_angle_h), 0, cos(_cam_angle_h))
		var right := Vector3(cos(_cam_angle_h), 0, -sin(_cam_angle_h))
		_cam_target = _drag_cam_target - right * dx + fwd * dz
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

# ── Utility ───────────────────────────────────────────────────────────────────

func _find_agent(id: int) -> Agent:
	for a in agents:
		if a.agent_id == id:
			return a
	return null
