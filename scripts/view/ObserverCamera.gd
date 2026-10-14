class_name ObserverCamera
extends Node3D
## The watcher's eye: orbit, pan and zoom over the world, and follow one person.
##
## Controls: WASD pan, Q/E turn, wheel zoom, left-drag tumble, middle- or
## Alt+left-drag pan, click to pick (emits `clicked`). Set follow_target_fn to
## ride along with someone (it returns their position, or Vector3.INF to stop).
## Only reads input while `active`; the walker owns input while walking.

signal clicked(screen_pos: Vector2)

const PAN_SPEED := 8.0
const ROT_SPEED := 1.8           # radians/sec for Q/E
const ZOOM_MIN := 8.0
## The world is WORLD_WIDTH * TILE_SIZE units across, so the far limit has to
## scale with it or you can never pull back far enough to see the whole map.
const ZOOM_MAX := 340.0
const ZOOM_STEP := 0.88          # proportional: fine up close, quick far out
const FOLLOW_EASE := 4.0         # higher = tighter follow
const LEFT_DRAG_THRESHOLD := 5.0 # pixels before a press becomes a drag
const TILT_MIN := deg_to_rad(10.0)
const TILT_MAX := deg_to_rad(85.0)

var camera: Camera3D
var active: bool = true
var target: Vector3 = Vector3.ZERO
var distance: float = 90.0
var angle_h: float = 0.0
var angle_v: float = deg_to_rad(55.0)
var bounds: Vector2 = Vector2(256, 256)  # world extent in units (x, z)

## Returns the followed point (world units) or Vector3.INF when nobody is followed.
var follow_target_fn: Callable = Callable()

var _keys: Dictionary = {}
var _left_pressed := false
var _left_is_drag := false
var _left_press_pos := Vector2.ZERO
var _drag_angle_h := 0.0
var _drag_angle_v := 0.0
var _pan_dragging := false
var _pan_start := Vector2.ZERO
var _pan_target := Vector3.ZERO

func _ready() -> void:
	camera = Camera3D.new()
	camera.far = 800.0
	add_child(camera)
	apply()

func is_following() -> bool:
	return follow_target_fn.is_valid() and follow_target_fn.call() != Vector3.INF

func stop_following() -> void:
	follow_target_fn = Callable()

func look_at_point(p: Vector3) -> void:
	target = Vector3(p.x, 0.0, p.z)
	_clamp_target()
	apply()

func apply() -> void:
	if camera == null:
		return
	var offset := Vector3(
		sin(angle_h) * cos(angle_v),
		sin(angle_v),
		cos(angle_h) * cos(angle_v)) * distance
	camera.position = target + offset
	camera.look_at(target, Vector3.UP)

func zoom_by(factor: float) -> void:
	distance = clampf(distance * factor, ZOOM_MIN, ZOOM_MAX)
	apply()

func _process(delta: float) -> void:
	if not active:
		return
	var moved := false
	var fwd := Vector3(sin(angle_h), 0, cos(angle_h))
	var right := Vector3(cos(angle_h), 0, -sin(angle_h))
	var speed := PAN_SPEED * (distance / 20.0)
	var pan := Vector3.ZERO
	if _keys.get(KEY_W, false): pan -= fwd
	if _keys.get(KEY_S, false): pan += fwd
	if _keys.get(KEY_A, false): pan -= right
	if _keys.get(KEY_D, false): pan += right
	if pan != Vector3.ZERO:
		# Panning by hand means you've stopped following.
		stop_following()
		target += pan.normalized() * speed * delta
		moved = true
	if _keys.get(KEY_Q, false): angle_h -= ROT_SPEED * delta; moved = true
	if _keys.get(KEY_E, false): angle_h += ROT_SPEED * delta; moved = true

	if follow_target_fn.is_valid():
		var p: Vector3 = follow_target_fn.call()
		if p == Vector3.INF:
			stop_following()
		else:
			target = target.lerp(Vector3(p.x, 0.0, p.z), clampf(FOLLOW_EASE * delta, 0.0, 1.0))
			moved = true
	if moved:
		_clamp_target()
		apply()

func _clamp_target() -> void:
	target.x = clampf(target.x, 0.0, bounds.x)
	target.z = clampf(target.z, 0.0, bounds.y)

func release_keys() -> void:
	_keys.clear()
	_left_pressed = false
	_pan_dragging = false

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.keycode in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E]:
			_keys[k.keycode] = k.pressed
	elif event is InputEventMouseButton:
		_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_mouse_motion(event as InputEventMouseMotion)

func _mouse_button(mb: InputEventMouseButton) -> void:
	match mb.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if mb.pressed: zoom_by(ZOOM_STEP)
		MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed: zoom_by(1.0 / ZOOM_STEP)
		MOUSE_BUTTON_MIDDLE:
			_set_pan_drag(mb.pressed, mb.position)
		MOUSE_BUTTON_LEFT:
			if mb.alt_pressed:
				_set_pan_drag(mb.pressed, mb.position)
			elif mb.pressed:
				_left_pressed = true
				_left_is_drag = false
				_left_press_pos = mb.position
				_drag_angle_h = angle_h
				_drag_angle_v = angle_v
			else:
				if _left_pressed and not _left_is_drag:
					clicked.emit(mb.position)
				_left_pressed = false
				_left_is_drag = false

func _set_pan_drag(on: bool, at: Vector2) -> void:
	_pan_dragging = on
	_pan_start = at
	_pan_target = target
	if on:
		stop_following()

func _mouse_motion(em: InputEventMouseMotion) -> void:
	if _left_pressed:
		if not _left_is_drag and em.position.distance_to(_left_press_pos) > LEFT_DRAG_THRESHOLD:
			_left_is_drag = true
		if _left_is_drag:
			angle_h = _drag_angle_h - (em.position.x - _left_press_pos.x) * 0.005
			angle_v = clampf(_drag_angle_v + (em.position.y - _left_press_pos.y) * 0.005, TILT_MIN, TILT_MAX)
			apply()
	if _pan_dragging:
		var s := distance / 400.0
		var fwd := Vector3(sin(angle_h), 0, cos(angle_h))
		var right := Vector3(cos(angle_h), 0, -sin(angle_h))
		target = _pan_target - right * (em.position.x - _pan_start.x) * s - fwd * (em.position.y - _pan_start.y) * s
		_clamp_target()
		apply()
