class_name AmbientRenderer
extends Node3D
## Draws AmbientLife: whales (a few nodes each), and everything small as
## MultiMeshes of merged, vertex-coloured low-poly parts (one draw call per
## kind). Small things are drawn a little larger than life so they read, and
## only near the camera (LOD by distance); whales and their blows read from
## the sky view.
##
## Pure drawing: it reads AmbientLife and never writes to it, and animates by
## AmbientLife.clock (game time) so a paused world stands still. No global
## randf(): variety comes from each creature's index.

const T := World.TILE_SIZE
## How far from the camera (metres) each kind is drawn.
const FAR_BIRDS := 260.0
const FAR_FISH := 150.0
const FAR_HIVES := 170.0
const FAR_SMALL := 95.0          # bees, butterflies, frogs, robins, midges
const MIDGES_PER_SWARM := 24

var life: AmbientLife
var world: World
## What was drawn last frame, by kind (tests read this; the headless renderer
## keeps no MultiMesh data).
var drawn: Dictionary = {}

var _mm: Dictionary = {}         # kind -> MultiMeshInstance3D
var _whales: Array = []          # [{root, fluke, spout, splash}]
var _hives: Array = []           # Node3D per hive
var _mat: StandardMaterial3D
var _mist: StandardMaterial3D

const BUTTERFLY_COLS := [Color(0.98, 0.55, 0.15), Color(1.0, 0.86, 0.28), Color(0.97, 0.96, 0.90),
	Color(0.38, 0.62, 0.96), Color(0.88, 0.34, 0.48)]

func setup(p_life: AmbientLife, p_world: World) -> void:
	life = p_life
	world = p_world
	restyle()

## Rebuild meshes and materials in the current look (LookStyle.g grades them).
func restyle() -> void:
	for ch in get_children():
		ch.queue_free()
	_mm.clear()
	_whales.clear()
	_hives.clear()
	if life == null:
		return
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.roughness = 0.75
	_mist = StandardMaterial3D.new()
	# Lit, not unshaded: pure white at full brightness tripped the bloom and
	# a breach read as a blinding blob from the sky.
	_mist.albedo_color = Color(0.88, 0.92, 0.95, 0.45)
	_mist.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mist.roughness = 1.0
	_mist.cull_mode = BaseMaterial3D.CULL_DISABLED
	var n_fish := life.shoals.size() * AmbientLife.FISH_MAX
	var n_birds := life.flocks.size() * AmbientLife.BIRDS_PER_FLOCK
	_add_mm("fish", _fish_mesh(), n_fish, true)
	_add_mm("bird", _bird_mesh(), n_birds)
	_add_mm("bird_wing_r", _wing_mesh(1.0), n_birds)
	_add_mm("bird_wing_l", _wing_mesh(-1.0), n_birds)
	_add_mm("robin", _robin_mesh(), life.robins.size())
	_add_mm("fly_body", _fly_body_mesh(), life.butterflies.size())
	_add_mm("fly_wing_r", _fly_wing_mesh(1.0), life.butterflies.size(), true)
	_add_mm("fly_wing_l", _fly_wing_mesh(-1.0), life.butterflies.size(), true)
	_add_mm("bee", _bee_mesh(), life.bees.size())
	_add_mm("midge", _midge_mesh(), life.swarms.size() * MIDGES_PER_SWARM)
	_add_mm("frog", _frog_mesh(), life.frogs.size())
	_add_mm("frog_sac", _sac_mesh(), life.frogs.size())
	for w in life.whales:
		_whales.append(_make_whale())
	for h in life.hives:
		_hives.append(_make_hive(h))
	update()

func _add_mm(kind: String, mesh: Mesh, count: int, colours: bool = false) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colours
	mm.mesh = mesh
	mm.instance_count = maxi(1, count)
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.name = kind
	add_child(mmi)
	_mm[kind] = mmi

func _process(_delta: float) -> void:
	update()

# ── Per frame ────────────────────────────────────────────────────────────────

func update() -> void:
	if life == null or _mm.is_empty():
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var eye := Vector3(world.width * T * 0.5, 80.0, world.height * T * 0.5)
	if cam:
		eye = cam.global_position if cam.is_inside_tree() else cam.position
	var c := life.clock
	_draw_whales(eye, c)
	_draw_fish(eye, c)
	_draw_birds(eye, c)
	_draw_robins(eye)
	_draw_butterflies(eye, c)
	_draw_bees(eye)
	_draw_midges(eye, c)
	_draw_frogs(eye)
	for i in _hives.size():
		var h: AmbientLife.Hive = life.hives[i]
		(_hives[i] as Node3D).visible = eye.distance_to(Vector3(h.pos.x, h.y, h.pos.y)) < FAR_HIVES
	drawn["hives"] = life.hives.size()

func _put(kind: String, i: int, xf: Transform3D, col: Variant = null) -> void:
	var mm: MultiMesh = (_mm[kind] as MultiMeshInstance3D).multimesh
	mm.set_instance_transform(i, xf)
	if col != null and mm.use_colors:
		mm.set_instance_color(i, col)

func _done(kind: String, n: int) -> void:
	var mm: MultiMesh = (_mm[kind] as MultiMeshInstance3D).multimesh
	mm.visible_instance_count = mini(n, mm.instance_count)
	drawn[kind] = n

static func _facing(yaw: float, pitch: float = 0.0, roll: float = 0.0) -> Basis:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch) * Basis(Vector3.BACK, roll)

func _draw_whales(eye: Vector3, c: float) -> void:
	var up := 0
	for i in _whales.size():
		var w: AmbientLife.Whale = life.whales[i]
		var parts: Dictionary = _whales[i]
		var root: Node3D = parts["root"]
		var under := w.y < -2.6 and w.state == AmbientLife.WhaleState.DIVE
		root.visible = not under
		root.position = Vector3(w.pos.x, w.y, w.pos.y)
		root.basis = _facing(w.heading, w.pitch, w.roll)
		(parts["fluke"] as Node3D).rotation.x = sin(c * 1.3 + i) * 0.22
		if not under:
			up += 1
		var spout: Node3D = parts["spout"]
		spout.visible = w.spout > 0.02 and w.y > -1.5
		if spout.visible:
			var hole := root.transform * Vector3(0, 0.85, 2.4)
			spout.position = Vector3(hole.x, 0.15, hole.z)
			spout.scale = Vector3(0.6 + w.spout * 0.5, 0.2 + w.spout * 1.0, 0.6 + w.spout * 0.5)
		var splash: Node3D = parts["splash"]
		splash.visible = w.splash > 0.02
		if splash.visible:
			var k := 1.0 - w.splash
			splash.position = Vector3(w.splash_pos.x, 0.05, w.splash_pos.y)
			splash.scale = Vector3(0.6 + k * 1.2, maxf(0.05, w.splash * 0.8), 0.6 + k * 1.2)
	drawn["whales"] = up

func _draw_fish(eye: Vector3, c: float) -> void:
	var n := 0
	var cols := [LookStyle.g(Color(0.32, 0.40, 0.46)), LookStyle.g(Color(0.42, 0.50, 0.55))]
	for si in life.shoals.size():
		var s: AmbientLife.Shoal = life.shoals[si]
		if eye.distance_to(Vector3(s.pos.x, s.y, s.pos.y)) > FAR_FISH:
			continue
		var dir := 1.0 if si % 2 == 0 else -1.0
		var heading := atan2(s.vel.x, s.vel.y)
		for i in s.stock:
			var k := float(i) / maxf(1.0, s.stock)
			var a := s.phase + k * TAU + c * 0.7 * dir
			var r := 0.6 + 0.45 * sin(float(i) * 1.7 + c * 0.5)
			var off := Vector2(cos(a), sin(a)) * r * Vector2(1.6, 1.0).rotated(-heading)
			var p := Vector3(s.pos.x + off.x, s.y + sin(c * 2.0 + i) * 0.03, s.pos.y + off.y)
			# Swim round the mill: face along the tangent.
			var yaw := atan2(-sin(a) * dir, cos(a) * dir)
			var glint := pow(maxf(0.0, sin(c * 2.3 + float(i) * 2.17 + s.phase * 5.0)), 40.0)
			var col: Color = (cols[i % 2] as Color).lerp(Color(1.6, 1.6, 1.5), glint)
			_put("fish", n, Transform3D(Basis(Vector3.UP, yaw), p), col)
			n += 1
	_done("fish", n)

func _draw_birds(eye: Vector3, c: float) -> void:
	var n := 0
	for fl: AmbientLife.Flock in life.flocks:
		for bi in fl.birds.size():
			var b: AmbientLife.Bird = fl.birds[bi]
			if eye.distance_to(b.pos) > FAR_BIRDS:
				continue
			var yaw := atan2(b.vel.x, b.vel.z) if not b.perched else float(bi) * 2.4
			var pitch := clampf(b.vel.y * 0.15, -0.4, 0.4)
			var basis := _facing(yaw, pitch, 0.0)
			# Flap in bursts, glide between; perched birds fold up.
			var flap := 0.0
			var fold := 1.0
			if b.perched:
				fold = 0.35
				flap = -0.25
			else:
				var burst := 0.5 + 0.5 * sin(b.flap * 0.11 + bi)
				flap = sin(b.flap) * 0.65 * smoothstep(0.3, 0.6, burst) + 0.08
			var xf := Transform3D(basis, b.pos)
			_put("bird", n, xf)
			_put("bird_wing_r", n, Transform3D(basis * Basis(Vector3.BACK, flap).scaled(Vector3(fold, 1, 1)), b.pos))
			_put("bird_wing_l", n, Transform3D(basis * Basis(Vector3.BACK, -flap).scaled(Vector3(fold, 1, 1)), b.pos))
			n += 1
	_done("bird", n)
	_done("bird_wing_r", n)
	_done("bird_wing_l", n)

func _draw_robins(eye: Vector3) -> void:
	var n := 0
	for r: AmbientLife.Robin in life.robins:
		var p := Vector3(r.pos.x, r.y, r.pos.y)
		if not r.shown or eye.distance_to(p) > FAR_SMALL:
			continue
		_put("robin", n, Transform3D(Basis(Vector3.UP, r.facing), p))
		n += 1
	_done("robin", n)

func _draw_butterflies(eye: Vector3, c: float) -> void:
	var n := 0
	for i in life.butterflies.size():
		var b: AmbientLife.Butterfly = life.butterflies[i]
		if not b.shown or eye.distance_to(b.pos) > FAR_SMALL:
			continue
		var to := b.target - b.pos
		var basis := Basis(Vector3.UP, atan2(to.x, to.z))
		var flap := sin(c * 16.0 + i * 1.3) * 0.9 + 0.3
		var col: Color = LookStyle.g(BUTTERFLY_COLS[i % BUTTERFLY_COLS.size()])
		_put("fly_body", n, Transform3D(basis, b.pos))
		_put("fly_wing_r", n, Transform3D(basis * Basis(Vector3.BACK, flap), b.pos), col)
		_put("fly_wing_l", n, Transform3D(basis * Basis(Vector3.BACK, -flap), b.pos), col)
		n += 1
	_done("fly_body", n)
	_done("fly_wing_r", n)
	_done("fly_wing_l", n)

func _draw_bees(eye: Vector3) -> void:
	var n := 0
	for b: AmbientLife.Bee in life.bees:
		if not b.shown or eye.distance_to(b.pos) > FAR_SMALL:
			continue
		var to := b.target - b.pos
		_put("bee", n, Transform3D(Basis(Vector3.UP, atan2(to.x, to.z)), b.pos))
		n += 1
	_done("bee", n)

func _draw_midges(eye: Vector3, c: float) -> void:
	var n := 0
	for si in life.swarms.size():
		var s: AmbientLife.Swarm = life.swarms[si]
		if s.level <= 0.01 or eye.distance_to(s.pos) > FAR_SMALL:
			continue
		var count := int(round(s.level * MIDGES_PER_SWARM))
		for i in count:
			var f := float(i * 7 + si * 13)
			var p := s.pos + Vector3(sin(c * (2.1 + fmod(f, 1.3)) + f) * 0.7,
				sin(c * (1.3 + fmod(f * 0.7, 0.9)) + f * 0.5) * 0.6,
				cos(c * (1.8 + fmod(f * 0.3, 1.1)) + f * 1.3) * 0.7)
			_put("midge", n, Transform3D(Basis.IDENTITY, p))
			n += 1
	_done("midge", n)

func _draw_frogs(eye: Vector3) -> void:
	var n := 0
	var croaks := 0
	for f: AmbientLife.Frog in life.frogs:
		var p := Vector3(f.pos.x, f.y, f.pos.y)
		if not f.shown or eye.distance_to(p) > FAR_SMALL:
			continue
		var basis := Basis(Vector3.UP, f.facing)
		_put("frog", n, Transform3D(basis, p))
		var puff := 0.25 + f.croak * 0.9
		_put("frog_sac", n, Transform3D(basis.scaled(Vector3(puff, puff, puff)), p + basis * Vector3(0, 0.035, 0.07)))
		if f.croak > 0.3:
			croaks += 1
		n += 1
	_done("frog", n)
	_done("frog_sac", n)
	drawn["croaking"] = croaks

# ── Meshes ───────────────────────────────────────────────────────────────────

## Primitive parts merged into one vertex-coloured mesh.
class Parts:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()

	func add(prim: PrimitiveMesh, xf: Transform3D, c: Color) -> Parts:
		var arr := prim.get_mesh_arrays()
		var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var pi: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var nb := xf.basis.inverse().transposed()
		var base := v.size()
		for k in pv.size():
			v.append(xf * pv[k])
			nrm.append((nb * pn[k]).normalized())
			col.append(LookStyle.g(c))
		for k in pi.size():
			idx.append(base + pi[k])
		return self

	func mesh() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = nrm
		arr[Mesh.ARRAY_COLOR] = col
		arr[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m

static func _ball(r: float, rings: int = 4, segs: int = 7) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.rings = rings
	s.radial_segments = segs
	return s

static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

static func _cone(r: float, h: float, segs: int = 5) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c

static func _xf(pos: Vector3, scale: Vector3 = Vector3.ONE, basis: Basis = Basis.IDENTITY) -> Transform3D:
	return Transform3D(basis * Basis.from_scale(scale), pos)

func _fish_mesh() -> Mesh:
	# Drawn white; the instance colour gives the back and the glint.
	return Parts.new() \
		.add(_ball(1.0, 3, 6), _xf(Vector3.ZERO, Vector3(0.07, 0.06, 0.22)), Color.WHITE) \
		.add(_box(Vector3(0.14, 0.02, 0.1)), _xf(Vector3(0, 0, -0.24)), Color.WHITE).mesh()

func _bird_mesh() -> Mesh:
	return Parts.new() \
		.add(_ball(1.0, 4, 7), _xf(Vector3.ZERO, Vector3(0.13, 0.12, 0.30)), Color(0.97, 0.97, 0.95)) \
		.add(_ball(0.1, 3, 6), _xf(Vector3(0, 0.07, 0.26)), Color(0.97, 0.97, 0.95)) \
		.add(_cone(0.035, 0.12, 4), _xf(Vector3(0, 0.06, 0.38), Vector3.ONE, Basis(Vector3.RIGHT, PI / 2)), Color(0.95, 0.66, 0.16)) \
		.add(_box(Vector3(0.18, 0.02, 0.14)), _xf(Vector3(0, 0.0, -0.32)), Color(0.85, 0.87, 0.88)).mesh()

func _wing_mesh(side: float) -> Mesh:
	return Parts.new() \
		.add(_box(Vector3(0.42, 0.025, 0.2)), _xf(Vector3(side * 0.27, 0.03, 0.0)), Color(0.66, 0.71, 0.76)) \
		.add(_box(Vector3(0.2, 0.024, 0.14)), _xf(Vector3(side * 0.56, 0.03, -0.02)), Color(0.16, 0.16, 0.2)).mesh()

func _robin_mesh() -> Mesh:
	var brown := Color(0.46, 0.33, 0.21)
	return Parts.new() \
		.add(_ball(1.0, 4, 7), _xf(Vector3(0, 0.1, 0), Vector3(0.075, 0.075, 0.1)), brown) \
		.add(_ball(1.0, 4, 7), _xf(Vector3(0, 0.085, 0.04), Vector3(0.062, 0.06, 0.07)), Color(0.93, 0.42, 0.16)) \
		.add(_ball(0.05, 3, 6), _xf(Vector3(0, 0.17, 0.07)), brown) \
		.add(_cone(0.014, 0.05, 4), _xf(Vector3(0, 0.17, 0.12), Vector3.ONE, Basis(Vector3.RIGHT, PI / 2)), Color(0.22, 0.16, 0.10)) \
		.add(_box(Vector3(0.06, 0.012, 0.09)), _xf(Vector3(0, 0.13, -0.12), Vector3.ONE, Basis(Vector3.RIGHT, -0.5)), brown) \
		.add(_box(Vector3(0.01, 0.06, 0.01)), _xf(Vector3(0.025, 0.03, 0)), Color(0.3, 0.22, 0.15)) \
		.add(_box(Vector3(0.01, 0.06, 0.01)), _xf(Vector3(-0.025, 0.03, 0)), Color(0.3, 0.22, 0.15)).mesh()

func _fly_body_mesh() -> Mesh:
	return Parts.new().add(_ball(1.0, 3, 5), _xf(Vector3.ZERO, Vector3(0.018, 0.018, 0.07)), Color(0.15, 0.12, 0.10)).mesh()

func _fly_wing_mesh(side: float) -> Mesh:
	return Parts.new() \
		.add(_box(Vector3(0.12, 0.006, 0.1)), _xf(Vector3(side * 0.07, 0, 0.03)), Color.WHITE) \
		.add(_box(Vector3(0.09, 0.006, 0.07)), _xf(Vector3(side * 0.055, 0, -0.05)), Color(0.85, 0.85, 0.85)).mesh()

func _bee_mesh() -> Mesh:
	return Parts.new() \
		.add(_ball(1.0, 3, 6), _xf(Vector3.ZERO, Vector3(0.045, 0.045, 0.07)), Color(0.98, 0.76, 0.16)) \
		.add(_ball(1.0, 3, 6), _xf(Vector3(0, 0, -0.02), Vector3(0.047, 0.047, 0.02)), Color(0.12, 0.10, 0.08)) \
		.add(_ball(1.0, 3, 6), _xf(Vector3(0, 0, 0.05), Vector3(0.03, 0.03, 0.03)), Color(0.12, 0.10, 0.08)) \
		.add(_box(Vector3(0.12, 0.004, 0.04)), _xf(Vector3(0, 0.045, 0)), Color(0.92, 0.96, 1.0)).mesh()

func _midge_mesh() -> Mesh:
	return Parts.new().add(_ball(0.03, 2, 4), Transform3D.IDENTITY, Color(0.13, 0.12, 0.11)).mesh()

func _frog_mesh() -> Mesh:
	var green := Color(0.36, 0.62, 0.22)
	return Parts.new() \
		.add(_ball(1.0, 4, 7), _xf(Vector3(0, 0.06, 0), Vector3(0.09, 0.06, 0.11)), green) \
		.add(_ball(0.025, 3, 5), _xf(Vector3(0.04, 0.115, 0.06)), Color(0.12, 0.12, 0.08)) \
		.add(_ball(0.025, 3, 5), _xf(Vector3(-0.04, 0.115, 0.06)), Color(0.12, 0.12, 0.08)) \
		.add(_ball(1.0, 3, 5), _xf(Vector3(0.08, 0.03, -0.05), Vector3(0.035, 0.03, 0.08)), green.darkened(0.2)) \
		.add(_ball(1.0, 3, 5), _xf(Vector3(-0.08, 0.03, -0.05), Vector3(0.035, 0.03, 0.08)), green.darkened(0.2)).mesh()

func _sac_mesh() -> Mesh:
	return Parts.new().add(_ball(0.06, 3, 6), Transform3D.IDENTITY, Color(0.88, 0.86, 0.55)).mesh()

func _make_whale() -> Dictionary:
	var back := Color(0.27, 0.36, 0.46)
	var pale := Color(0.84, 0.87, 0.87)
	var root := Node3D.new()
	add_child(root)
	var body := Parts.new() \
		.add(_ball(1.0, 6, 10), _xf(Vector3.ZERO, Vector3(1.15, 0.95, 4.4)), back) \
		.add(_ball(1.0, 5, 9), _xf(Vector3(0, -0.28, 0.6), Vector3(0.95, 0.7, 3.4)), pale) \
		.add(_ball(1.0, 3, 6), _xf(Vector3(0, 0.82, -1.6), Vector3(0.18, 0.3, 0.5)), back) \
		.add(_box(Vector3(2.6, 0.12, 0.55)), _xf(Vector3(1.7, -0.45, 1.2), Vector3.ONE, Basis(Vector3.BACK, -0.5) * Basis(Vector3.UP, -0.5)), pale) \
		.add(_box(Vector3(2.6, 0.12, 0.55)), _xf(Vector3(-1.7, -0.45, 1.2), Vector3.ONE, Basis(Vector3.BACK, 0.5) * Basis(Vector3.UP, 0.5)), pale)
	var mi := MeshInstance3D.new()
	mi.mesh = body.mesh()
	mi.material_override = _mat
	root.add_child(mi)
	# The tail stock and flukes, on their own pivot so they beat.
	var fluke := Node3D.new()
	fluke.position = Vector3(0, 0, -3.6)
	root.add_child(fluke)
	var tail := Parts.new() \
		.add(_ball(1.0, 4, 7), _xf(Vector3(0, 0, -0.6), Vector3(0.45, 0.4, 1.4)), back) \
		.add(_box(Vector3(1.5, 0.12, 0.9)), _xf(Vector3(0.75, 0, -1.9), Vector3.ONE, Basis(Vector3.UP, 0.35)), back) \
		.add(_box(Vector3(1.5, 0.12, 0.9)), _xf(Vector3(-0.75, 0, -1.9), Vector3.ONE, Basis(Vector3.UP, -0.35)), back)
	var tmi := MeshInstance3D.new()
	tmi.mesh = tail.mesh()
	tmi.material_override = _mat
	fluke.add_child(tmi)
	# The blow: a column of mist; the splash: a ring of white water.
	var spout := MeshInstance3D.new()
	var sp := Parts.new() \
		.add(_ball(0.5, 4, 7), _xf(Vector3(0, 1.0, 0), Vector3(0.6, 1.4, 0.6)), Color.WHITE) \
		.add(_ball(0.5, 4, 7), _xf(Vector3(0, 2.6, 0), Vector3(1.3, 1.0, 1.3)), Color.WHITE)
	spout.mesh = sp.mesh()
	spout.material_override = _mist
	spout.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(spout)
	var splash := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 2.2
	ring.outer_radius = 3.4
	ring.rings = 16
	ring.ring_segments = 5
	var spray := Parts.new() \
		.add(ring, _xf(Vector3.ZERO, Vector3(1, 0.5, 1)), Color.WHITE) \
		.add(_ball(1.0, 4, 8), _xf(Vector3(0, 1.0, 0), Vector3(2.0, 1.6, 2.0)), Color.WHITE)
	splash.mesh = spray.mesh()
	splash.material_override = _mist
	splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(splash)
	return {"root": root, "fluke": fluke, "spout": spout, "splash": splash}

## A wild nest: a papery comb hanging from a branch of a little old tree.
func _make_hive(h: AmbientLife.Hive) -> Node3D:
	var bark := Color(0.42, 0.29, 0.20)
	var comb := Color(0.88, 0.68, 0.30)
	var g := h.y - AmbientLife.HIVE_HEIGHT
	var p := Parts.new() \
		.add(_cylinder(0.16, 0.22, 3.0), _xf(Vector3(-0.7, 1.5, 0)), bark) \
		.add(_cylinder(0.06, 0.09, 1.0), _xf(Vector3(-0.3, 2.35, 0), Vector3.ONE, Basis(Vector3.BACK, -1.25)), bark) \
		.add(_ball(1.0, 4, 8), _xf(Vector3(-0.7, 3.4, 0), Vector3(0.9, 0.7, 0.9)), Color(0.36, 0.58, 0.24)) \
		.add(_ball(1.0, 4, 8), _xf(Vector3(0, 1.95, 0), Vector3(0.26, 0.22, 0.26)), comb) \
		.add(_ball(1.0, 4, 8), _xf(Vector3(0, 1.72, 0), Vector3(0.24, 0.14, 0.24)), comb.darkened(0.25)) \
		.add(_ball(1.0, 4, 8), _xf(Vector3(0, 1.55, 0), Vector3(0.18, 0.13, 0.18)), comb) \
		.add(_ball(0.05, 2, 5), _xf(Vector3(0, 1.6, 0.17)), Color(0.15, 0.10, 0.06))
	var mi := MeshInstance3D.new()
	mi.mesh = p.mesh()
	mi.material_override = _mat
	mi.position = Vector3(h.pos.x, g, h.pos.y)
	add_child(mi)
	return mi

static func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = 6
	c.rings = 1
	return c
