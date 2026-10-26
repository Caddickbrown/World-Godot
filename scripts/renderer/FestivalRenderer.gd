class_name FestivalRenderer
extends Node3D
## What a festival looks like (FestivalSystem.active): the midsummer bonfire
## with sparks, the harvest's long table, the ring of midwinter lanterns, the
## candles at the shrine, a seed basket in the spring meadow. The people come
## from AgentRenderer (they dance, sit and stand by Agent.festival_pose).
##
## Drawing only: reads the festival list, never writes it, and never touches
## the global RNG (flicker comes from the clock and each prop's position).

const TILE_SIZE := World.TILE_SIZE
const MAX_LIGHTS := 6               # festival lights at once, over the whole island

var world: World
var darkness := 0.0
var _shown: Dictionary = {}         # festival id -> {node, flames: [MeshInstance3D], lights: [OmniLight3D], sparks: []}
var _mats: Dictionary = {}
var _clock := 0.0

func sync(fs: FestivalSystem, p_darkness: float) -> void:
	darkness = p_darkness
	_clock += get_process_delta_time()
	var live: Dictionary = {}
	if fs:
		for f in fs.active:
			live[int(f["id"])] = true
			if not _shown.has(int(f["id"])):
				_shown[int(f["id"])] = _build(f)
	for id in _shown.keys():
		if not live.has(id):
			(_shown[id]["node"] as Node).queue_free()
			_shown.erase(id)
	_animate()

## How many festivals are drawn (tests).
func shown_count() -> int:
	return _shown.size()

func restyle() -> void:
	for id in _shown:
		(_shown[id]["node"] as Node).queue_free()
	_shown.clear()
	_mats.clear()

# ── Building ─────────────────────────────────────────────────────────────────

func _build(f: Dictionary) -> Dictionary:
	var e := {"node": Node3D.new(), "flames": [], "lights": [], "sparks": []}
	var root: Node3D = e["node"]
	var focus: Vector2 = f["focus"]
	root.position = _ground(focus)
	add_child(root)
	match str(f["kind"]):
		"midsummer": _bonfire(e)
		"midwinter": _lanterns(e, f)
		"harvest": _table(e, f)
		"mourning": _candles(e)
		"planting": _basket(e, f)
	return e

func _bonfire(e: Dictionary) -> void:
	var root: Node3D = e["node"]
	var wood := _mat(Color(0.40, 0.26, 0.16))
	for i in 8:   # logs leaned together into a cone
		var lg := _mesh(_cyl(0.09, 0.12, 2.2), wood)
		var a := TAU * i / 8.0
		lg.position = Vector3(cos(a) * 0.45, 0.9, sin(a) * 0.45)
		lg.rotation = Vector3(0, -a, 0)
		lg.rotate_object_local(Vector3(0, 0, 1), 0.38)
		root.add_child(lg)
	for k in 3:
		var fl := _mesh(_cone(0.75 - k * 0.2, 2.0 + k * 0.5), _glow(Color(1.0, 0.55 + k * 0.12, 0.18), 5.0 + k))
		fl.position = Vector3(0.1 * (k - 1), 1.0 + k * 0.25, 0.08 * k)
		root.add_child(fl)
		e["flames"].append(fl)
	for i in 10:   # sparks rising and starting again
		var sp := _mesh(_ball(0.06), _glow(Color(1.0, 0.8, 0.4), 6.0))
		root.add_child(sp)
		e["sparks"].append(sp)
	_light(e, Vector3(0, 2.2, 0), Color(1.0, 0.6, 0.3), 26.0, 5.0)

func _lanterns(e: Dictionary, f: Dictionary) -> void:
	var root: Node3D = e["node"]
	var post_m := _mat(Color(0.36, 0.26, 0.18))
	var paper := _glow(Color(1.0, 0.80, 0.42), 3.5)
	var n := 10
	var r := (FestivalSystem.RING_RADIUS + 1.4) * TILE_SIZE
	for i in n:
		var a := TAU * i / n
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		var gy := _ground(Vector2(root.position.x, root.position.z) / TILE_SIZE + Vector2(p.x, p.z) / TILE_SIZE).y - root.position.y
		var post := _mesh(_cyl(0.05, 0.05, 1.8), post_m)
		post.position = p + Vector3(0, gy + 0.9, 0)
		root.add_child(post)
		var lamp := _mesh(_ball(0.22), paper)
		lamp.position = p + Vector3(0, gy + 1.9, 0)
		root.add_child(lamp)
		e["flames"].append(lamp)
	var fire := _mesh(_cone(0.4, 1.0), _glow(Color(1.0, 0.55, 0.2), 5.0))
	fire.position.y = 0.5
	root.add_child(fire)
	e["flames"].append(fire)
	_light(e, Vector3(0, 2.0, 0), Color(1.0, 0.72, 0.4), 20.0, 3.5)

func _table(e: Dictionary, f: Dictionary) -> void:
	var root: Node3D = e["node"]
	root.rotation.y = -float(f["yaw"])
	var length := FestivalSystem.table_length(f) * TILE_SIZE
	var wood := _mat(Color(0.55, 0.38, 0.22))
	var top := _mesh(_box(Vector3(length, 0.1, 0.9)), wood)
	top.position.y = 0.75
	root.add_child(top)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var leg := _mesh(_box(Vector3(0.1, 0.75, 0.1)), wood)
			leg.position = Vector3(sx * (length * 0.5 - 0.2), 0.37, sz * 0.35)
			root.add_child(leg)
	var bench_m := _mat(Color(0.47, 0.32, 0.19))
	for sz in [-1, 1]:
		var bench := _mesh(_box(Vector3(length, 0.08, 0.32)), bench_m)
		bench.position = Vector3(0, 0.42, sz * 1.1)
		root.add_child(bench)
	# The harvest along the table: loaves, apples, squash, a jug.
	var foods := [Color(0.85, 0.62, 0.32), Color(0.82, 0.22, 0.18), Color(0.95, 0.62, 0.15), Color(0.62, 0.70, 0.28)]
	var cloth := _mat(Color(0.93, 0.88, 0.76))
	var runner := _mesh(_box(Vector3(length * 0.92, 0.02, 0.4)), cloth)
	runner.position.y = 0.81
	root.add_child(runner)
	var count := int(length / 0.45)
	for i in count:
		var x := -length * 0.5 + 0.3 + i * (length - 0.6) / maxf(1.0, count - 1)
		var c: Color = foods[i % foods.size()]
		var item := _mesh(_ball(0.13 if i % 3 == 0 else 0.09), _mat(c))
		item.position = Vector3(x, 0.9, 0.12 * (1 if i % 2 == 0 else -1))
		root.add_child(item)
	for sx in [-1, 1]:   # a lantern at each end
		var lamp := _mesh(_ball(0.16), _glow(Color(1.0, 0.78, 0.40), 3.0))
		lamp.position = Vector3(sx * (length * 0.5 - 0.15), 1.05, 0)
		root.add_child(lamp)
		e["flames"].append(lamp)
	_light(e, Vector3(0, 2.4, 0), Color(1.0, 0.74, 0.45), 14.0, 2.5)

func _candles(e: Dictionary) -> void:
	var root: Node3D = e["node"]
	var wax := _mat(Color(0.95, 0.92, 0.82))
	var flame := _glow(Color(1.0, 0.72, 0.32), 4.0)
	for i in 9:
		var a := TAU * i / 9.0
		var r := 1.15
		var c := _mesh(_cyl(0.05, 0.05, 0.28), wax)
		c.position = Vector3(cos(a) * r, 0.14, sin(a) * r)
		root.add_child(c)
		var fl := _mesh(_cone(0.04, 0.12), flame)
		fl.position = c.position + Vector3(0, 0.2, 0)
		root.add_child(fl)
		e["flames"].append(fl)
	var wreath := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.58
	wreath.mesh = torus
	wreath.material_override = _mat(Color(0.38, 0.52, 0.28))
	wreath.position.y = 0.08
	root.add_child(wreath)
	_light(e, Vector3(0, 1.0, 0), Color(1.0, 0.75, 0.45), 8.0, 1.6)

func _basket(e: Dictionary, f: Dictionary) -> void:
	var root: Node3D = e["node"]
	var b := _mesh(_cyl(0.32, 0.24, 0.4), _mat(Color(0.70, 0.54, 0.30)))
	b.position.y = 0.2
	root.add_child(b)
	var grain := _mesh(_cyl(0.28, 0.28, 0.04), _mat(Color(0.86, 0.76, 0.46)))
	grain.position.y = 0.4
	root.add_child(grain)

# ── Each frame ───────────────────────────────────────────────────────────────

func _animate() -> void:
	var t := _clock
	for id in _shown:
		var e: Dictionary = _shown[id]
		var k := 0
		for fl in e["flames"]:
			var m: Node3D = fl
			var w := 0.88 + 0.12 * sin(t * 9.0 + k * 1.7 + m.position.x * 3.0)
			m.scale = Vector3(1.0, w, 1.0)
			k += 1
		var i := 0
		for sp in e["sparks"]:
			var s: Node3D = sp
			var life := fposmod(t * 0.7 + i * 0.37, 1.0)
			var a := i * 2.4 + t * 0.6
			s.position = Vector3(cos(a) * 0.4 * (1.0 + life), 1.6 + life * 4.5, sin(a) * 0.4 * (1.0 + life))
			s.scale = Vector3.ONE * (1.0 - life)
			i += 1
		for l in e["lights"]:
			var light: OmniLight3D = l
			light.light_energy = float(light.get_meta("energy")) * lerpf(0.35, 1.0, darkness) * (0.9 + 0.1 * sin(t * 11.0 + light.position.x))

# ── Bits ─────────────────────────────────────────────────────────────────────

func _ground(tile: Vector2) -> Vector3:
	var y := world.surface_y(tile.x, tile.y) if world else 0.0
	return Vector3(tile.x * TILE_SIZE, y, tile.y * TILE_SIZE)

func _light(e: Dictionary, at: Vector3, col: Color, range_m: float, energy: float) -> void:
	var lights := 0
	for id in _shown:
		lights += (_shown[id]["lights"] as Array).size()
	if lights >= MAX_LIGHTS:
		return
	var l := OmniLight3D.new()
	l.light_color = col
	l.omni_range = range_m
	l.position = at
	l.set_meta("energy", energy)
	l.shadow_enabled = false
	(e["node"] as Node3D).add_child(l)
	e["lights"].append(l)

func _mesh(m: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	return mi

func _mat(c: Color) -> StandardMaterial3D:
	var col := LookStyle.g(c)
	var key := "m" + col.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.9
		_mats[key] = m
	return _mats[key]

func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var key := "g%s%.1f" % [c.to_html(), energy]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mats[key] = m
	return _mats[key]

static func _cone(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 7
	c.rings = 1
	return c

static func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 8
	c.rings = 1
	return c

static func _ball(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 8
	s.rings = 4
	return s

static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b
