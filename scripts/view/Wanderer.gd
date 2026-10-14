class_name Wanderer
extends Node3D
## You, walking among them: an unseen wisp, third person.
##
## Still the observer, just closer. Nobody can see or hear the wisp and nothing
## in the simulation knows it exists: it can't block, startle, teach or help.
## Listening in (Main, E) only opens a person's thoughts to you.
##
## Controls: WASD move (relative to the camera), Shift run, mouse look (the
## mouse is captured; Esc frees it, a click takes it back), wheel zoom.

const WALK_SPEED := 2.0     # tiles/sec (people walk at 1.8)
const RUN_SPEED := 4.2
const TURN_EASE := 10.0
const GROUND_EASE := 12.0
const MOUSE_SENS := 0.0035
const CAM_DIST_MIN := 2.5
const CAM_DIST_MAX := 14.0
const PITCH_MIN := deg_to_rad(-10.0)
const PITCH_MAX := deg_to_rad(60.0)
const EYE_HEIGHT := 1.1

var world: World
var tile_pos: Vector2 = Vector2.ZERO   # tile space, like Agent.pos
var cam_yaw: float = 0.0
var cam_pitch: float = deg_to_rad(18.0)
var cam_distance: float = 6.0
var active: bool = false:
	set(v):
		active = v
		visible = v
		if camera:
			camera.current = v
		if not v:
			_keys.clear()

var camera: Camera3D
var model: Node3D
var _keys: Dictionary = {}

func _ready() -> void:
	model = _build_model()
	add_child(model)
	camera = Camera3D.new()
	camera.far = 600.0
	add_child(camera)
	visible = active

## Put the wanderer down at a tile-space point, nudged onto walkable ground.
func place_at(p: Vector2) -> void:
	tile_pos = _nearest_walkable(p)
	position = _world_pos(tile_pos)
	_update_camera()

func world_position() -> Vector3:
	return _world_pos(tile_pos)

## One movement step; split out of _process so tests can drive it.
func step(delta: float, input_dir: Vector2, running: bool) -> void:
	if input_dir.length() > 0.0:
		var dir := input_dir.normalized()
		# Rotate the stick by the camera's yaw so W is always "away from camera".
		var fwd := Vector2(-sin(cam_yaw), -cos(cam_yaw))
		var right := Vector2(cos(cam_yaw), -sin(cam_yaw))
		var move := (right * dir.x + fwd * -dir.y) * (RUN_SPEED if running else WALK_SPEED) * delta
		_try_move(move)
		var want_yaw := atan2(move.x, move.y)
		model.rotation.y = lerp_angle(model.rotation.y, want_yaw, clampf(TURN_EASE * delta, 0.0, 1.0))
	var ground := _world_pos(tile_pos)
	position = Vector3(ground.x, lerpf(position.y, ground.y, clampf(GROUND_EASE * delta, 0.0, 1.0)), ground.z)
	_update_camera()

func _process(delta: float) -> void:
	if not active:
		return
	var dir := Vector2.ZERO
	if _keys.get(KEY_A, false): dir.x -= 1.0
	if _keys.get(KEY_D, false): dir.x += 1.0
	if _keys.get(KEY_W, false): dir.y -= 1.0
	if _keys.get(KEY_S, false): dir.y += 1.0
	step(delta, dir, Input.is_key_pressed(KEY_SHIFT))

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.keycode in [KEY_W, KEY_A, KEY_S, KEY_D]:
			_keys[k.keycode] = k.pressed
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		cam_yaw -= m.relative.x * MOUSE_SENS
		cam_pitch = clampf(cam_pitch + m.relative.y * MOUSE_SENS, PITCH_MIN, PITCH_MAX)
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP: cam_distance = clampf(cam_distance * 0.9, CAM_DIST_MIN, CAM_DIST_MAX)
			MOUSE_BUTTON_WHEEL_DOWN: cam_distance = clampf(cam_distance / 0.9, CAM_DIST_MIN, CAM_DIST_MAX)
			MOUSE_BUTTON_LEFT: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ── Internals ────────────────────────────────────────────────────────────────

func _try_move(move: Vector2) -> void:
	# Slide along water and cliffs: try the full step, then each axis alone.
	for candidate in [tile_pos + move, tile_pos + Vector2(move.x, 0), tile_pos + Vector2(0, move.y)]:
		if _walkable(candidate):
			tile_pos = candidate
			return

func _walkable(p: Vector2) -> bool:
	return world != null and world.is_walkable(p.x, p.y)

func _nearest_walkable(p: Vector2) -> Vector2:
	if _walkable(p) or world == null:
		return p
	var tile := world.find_nearest(p.x, p.y,
		[World.TileType.GRASS, World.TileType.WOODLAND, World.TileType.FOREST,
		 World.TileType.BEACH, World.TileType.DESERT, World.TileType.STONE], 30.0)
	if tile.is_empty():
		return p
	return Vector2(float(tile["x"]) + 0.5, float(tile["z"]) + 0.5)

func _world_pos(p: Vector2) -> Vector3:
	var y := world.surface_y(p.x, p.y) if world else 0.0
	return Vector3(p.x * World.TILE_SIZE, y, p.y * World.TILE_SIZE)

func _update_camera() -> void:
	if camera == null:
		return
	var pivot := Vector3(0, EYE_HEIGHT, 0)
	var offset := Vector3(sin(cam_yaw) * cos(cam_pitch), sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch)) * cam_distance
	camera.position = pivot + offset
	if camera.is_inside_tree():
		camera.look_at(global_position + pivot, Vector3.UP)

## A small glowing wisp with a couple of trailing motes: plainly not one of
## them, and light enough to read as "not really here".
func _build_model() -> Node3D:
	var root := Node3D.new()
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.80, 0.93, 1.0, 0.75)
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.emission_enabled = true
	glow.emission = Color(0.55, 0.85, 1.0)
	glow.emission_energy_multiplier = 1.6
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	core.mesh = sphere
	core.position.y = 1.1
	core.material_override = glow
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	for i in 3:
		var mote := MeshInstance3D.new()
		var m := SphereMesh.new()
		m.radius = 0.09 - i * 0.02
		m.height = m.radius * 2.0
		mote.mesh = m
		mote.position = Vector3(0.0, 1.0 - i * 0.12, -0.28 - i * 0.22)
		mote.material_override = glow
		mote.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mote)
	var light := OmniLight3D.new()
	light.light_color = Color(0.65, 0.85, 1.0)
	light.omni_range = 6.0
	light.light_energy = 0.0   # Main turns it up after dusk
	light.position = core.position
	light.name = "Lantern"
	root.add_child(light)
	return root

func set_lantern(amount: float) -> void:
	var light := model.get_node_or_null("Lantern") as OmniLight3D
	if light:
		light.light_energy = 1.6 * clampf(amount, 0.0, 1.0)
