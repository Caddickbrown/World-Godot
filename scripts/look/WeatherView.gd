class_name WeatherView
extends Node3D
## The island's weather as you see it from the sky. WeatherSystem keeps a 4x4
## grid of zones; this draws them: cloud banks drifting on the wind that thicken
## and darken as they pass over cloudy, rainy and stormy zones, grey rain
## curtains hanging under the ones over rain, lightning bolts in storms, and a
## rainbow standing where rain has just cleared, opposite the sun.
##
## Clouds near the line from the camera to what it looks at thin away, so the
## people you're watching are never hidden. Visual randomness is a local RNG;
## the simulation's dice are never touched by looking.

const WIND := Vector2(0.9, 0.35)        # metres per game-second the clouds drift
const CLUSTERS := 84
const PUFFS := 4                        # balls per cluster
const SPAN := 352.0                     # the drift wraps over this square (metres)
const ORIGIN := -48.0
const EASE := 0.12                      # how fast a cluster takes on a zone's look, per game-second
const CLOUD_BASE := 34.0
## Lightning: per game-second for each storm cloud near the view.
const BOLT_PER_SECOND := 0.06
const BOLT_RANGE := 140.0
const BOLT_SECONDS := 0.28
const RAINBOW_RADIUS := 46.0

var _rng := RandomNumberGenerator.new()
var _base: Array = []                   # [Vector3 base xz + altitude]
var _size: PackedFloat32Array
var _pick: PackedFloat32Array
var _amount: PackedFloat32Array         # 0..1 how much of the cluster shows
var _dark: PackedFloat32Array           # 0..1 how grey
var _wet: PackedFloat32Array            # 0..1 rain curtain
var _storm: PackedFloat32Array
var _drift := Vector2.ZERO
var _puffs: MultiMeshInstance3D
var _curtains: MultiMeshInstance3D
var _puff_mat: ShaderMaterial
var _curtain_mat: ShaderMaterial
var _bolt: MeshInstance3D
var _bolt_light: OmniLight3D
var _bolt_t := 0.0
var _rainbow: MeshInstance3D
var _rainbow_mat: ShaderMaterial
var _sun_dir := Vector3(0, 1, 0)
var _night := 0.0
var _warm := 0.0
var _sun_up := true
var _sky: SkyLook
var _primed := false

## Take on the current weather at once on the next update (captures, a new world).
func snap() -> void:
	_primed = false

## Read by tests (the dummy renderer keeps no GPU data).
var raining_clusters := 0
var shown_clusters := 0
var bolts := 0
## A bolt came down at this ground point (metres): thunder follows (Soundscape).
signal struck(ground: Vector3)
var rainbow_shown := 0.0               # the rainbow's drawn strength (0 hidden)
var rainbow_at := Vector3.INF

func _ready() -> void:
	_rng.seed = 4242
	_size.resize(CLUSTERS)
	_pick.resize(CLUSTERS)
	_amount.resize(CLUSTERS)
	_dark.resize(CLUSTERS)
	_wet.resize(CLUSTERS)
	_storm.resize(CLUSTERS)
	var seeder := RandomNumberGenerator.new()
	seeder.seed = 1717
	for i in CLUSTERS:
		_base.append(Vector3(seeder.randf() * SPAN, CLOUD_BASE + seeder.randf() * 9.0, seeder.randf() * SPAN))
		_size[i] = seeder.randf_range(7.0, 13.0)
		_pick[i] = seeder.randf()
	_puff_mat = ShaderMaterial.new()
	_puff_mat.shader = preload("res://shaders/cloud_puff.gdshader")
	_puffs = _multimesh(_ball(), _puff_mat, CLUSTERS * PUFFS)
	_puffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_curtain_mat = ShaderMaterial.new()
	_curtain_mat.shader = preload("res://shaders/rain_curtain.gdshader")
	_curtains = _multimesh(_tube(), _curtain_mat, CLUSTERS)
	_curtains.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt = MeshInstance3D.new()
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(0.92, 0.95, 1.0)
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.disable_fog = true
	_bolt.material_override = bm
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt.visible = false
	add_child(_bolt)
	_bolt_light = OmniLight3D.new()
	_bolt_light.light_color = Color(0.80, 0.86, 1.0)
	_bolt_light.omni_range = 70.0
	_bolt_light.light_energy = 0.0
	_bolt_light.shadow_enabled = false
	add_child(_bolt_light)
	_rainbow_mat = ShaderMaterial.new()
	_rainbow_mat.shader = preload("res://shaders/rainbow.gdshader")
	_rainbow = MeshInstance3D.new()
	_rainbow.mesh = _arc()
	_rainbow.material_override = _rainbow_mat
	_rainbow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rainbow.visible = false
	add_child(_rainbow)
	apply_style()

func _multimesh(mesh: Mesh, mat: Material, n: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = n
	mm.visible_instance_count = 0
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat
	add_child(inst)
	return inst

func apply_style() -> void:
	var nat := LookStyle.naturalist()
	if _rainbow_mat:
		_rainbow_mat.set_shader_parameter("gain", 0.55 if nat else 0.85)
		_rainbow_mat.set_shader_parameter("width", 0.11 if nat else 0.15)
	if _curtain_mat:
		_curtain_mat.set_shader_parameter("tint", Color(0.50, 0.54, 0.58) if nat else Color(0.56, 0.62, 0.72))

func set_light(sun_dir: Vector3, night: float, warm: float, sun_up: bool) -> void:
	_sun_dir = sun_dir
	_night = night
	_warm = warm
	_sun_up = sun_up

## Real-time decay of the bolt (runs while paused too).
func _process(delta: float) -> void:
	if _bolt_t > 0.0:
		_bolt_t -= delta
		var flick := 1.0 if fmod(_bolt_t, 0.09) > 0.03 else 0.35
		_bolt_light.light_energy = 8.0 * clampf(_bolt_t / BOLT_SECONDS, 0.0, 1.0) * flick
		if _bolt_t <= 0.0:
			_bolt.visible = false
			_bolt_light.light_energy = 0.0

## Where a cluster is now (metres), drifted on the wind and wrapped round.
func cluster_pos(i: int) -> Vector3:
	var b: Vector3 = _base[i]
	return Vector3(ORIGIN + fposmod(b.x + _drift.x, SPAN), b.y, ORIGIN + fposmod(b.z + _drift.y, SPAN))

## One step: drift, take on the weather of the zone each cluster is over,
## lightning, the rainbow. dt is game-seconds (0 while paused).
func update_weather(ws: WeatherSystem, focus: Vector3, dt: float, sky: SkyLook = null) -> void:
	_sky = sky
	_drift += WIND * dt
	var k := clampf(EASE * dt, 0.0, 1.0)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var cam_p := cam.global_position if cam else focus + Vector3(0, 60, 60)
	var cloud_col := Color(1, 1, 1).lerp(Color(1.0, 0.82, 0.70), _warm * (1.0 - _night) * 0.7)
	var rain_col := Color(0.58, 0.61, 0.66)
	var storm_col := Color(0.34, 0.36, 0.42)
	var night_k := 1.0 - 0.78 * _night
	var mm := _puffs.multimesh
	var cm := _curtains.multimesh
	var n_puff := 0
	var n_curt := 0
	raining_clusters = 0
	shown_clusters = 0
	var storm_near: Array = []
	for i in CLUSTERS:
		var p := cluster_pos(i)
		var st := ws.get_weather_at(p.x / World.TILE_SIZE, p.z / World.TILE_SIZE)
		var want := 0.0
		var dark := 0.0
		var wet := 0.0
		var storm := 0.0
		match st:
			WeatherSystem.WeatherType.CLEAR: want = 1.0 if _pick[i] < 0.22 else 0.0
			WeatherSystem.WeatherType.CLOUDY:
				want = 1.0 if _pick[i] < 0.75 else 0.0
				dark = 0.25
			WeatherSystem.WeatherType.RAIN:
				want = 1.0
				dark = 0.6
				wet = 1.0
			WeatherSystem.WeatherType.STORM:
				want = 1.0
				dark = 1.0
				wet = 1.0
				storm = 1.0
		var kk := k if _primed else 1.0
		_amount[i] = lerpf(_amount[i], want, kk)
		_dark[i] = lerpf(_dark[i], dark, kk)
		_wet[i] = lerpf(_wet[i], wet, kk)
		_storm[i] = lerpf(_storm[i], storm, kk)
		var amt := _amount[i]
		if amt < 0.03:
			continue
		# Thin away near the line of sight to the focus, and right by the camera.
		var clear_view := _seg_dist(p, cam_p, focus)
		var fade := smoothstep(10.0, 30.0, clear_view) * smoothstep(12.0, 30.0, p.distance_to(cam_p))
		var a := amt * fade
		if a < 0.03:
			continue
		shown_clusters += 1
		var col: Color = cloud_col.lerp(rain_col, clampf(_dark[i] / 0.6, 0.0, 1.0)).lerp(storm_col, clampf((_dark[i] - 0.6) / 0.4, 0.0, 1.0))
		col = Color(col.r * night_k, col.g * night_k, col.b * night_k * 1.06, a)
		var s := _size[i] * lerpf(0.7, 1.15, _dark[i]) * lerpf(0.55, 1.0, amt)
		for j in PUFFS:
			var ang := _pick[i] * 40.0 + j * 1.9
			var off := Vector3(cos(ang), 0.0, sin(ang)) * s * (0.15 + 0.32 * float(j))
			var ps := s * (0.62 - 0.08 * j)
			var xf := Transform3D(Basis().scaled(Vector3(ps, ps * 0.55, ps * 0.85)), p + off + Vector3(0, j * 0.6, 0))
			mm.set_instance_transform(n_puff, xf)
			mm.set_instance_color(n_puff, col)
			n_puff += 1
		if _wet[i] > 0.05:
			raining_clusters += 1
			var r := s * 0.75
			var cxf := Transform3D(Basis().scaled(Vector3(r, p.y, r)), Vector3(p.x, 0.0, p.z))
			cm.set_instance_transform(n_curt, cxf)
			cm.set_instance_color(n_curt, Color(lerpf(0.0, 1.0, _storm[i]), 0, 0, _wet[i] * fade * (1.0 - 0.4 * _night)))
			n_curt += 1
		if _storm[i] > 0.6 and Vector2(p.x - focus.x, p.z - focus.z).length() < BOLT_RANGE:
			storm_near.append(i)
	_primed = true
	mm.visible_instance_count = n_puff
	cm.visible_instance_count = n_curt
	_curtain_mat.set_shader_parameter("scroll", fposmod(_drift.length() * 0.9, 1000.0))
	# Lightning from the storm clouds you can see.
	if dt > 0.0 and not storm_near.is_empty():
		if _rng.randf() < minf(0.5, BOLT_PER_SECOND * dt * storm_near.size()):
			var i: int = storm_near[_rng.randi() % storm_near.size()]
			var p := cluster_pos(i)
			var spot := Vector3(p.x + _rng.randf_range(-6, 6), 0.0, p.z + _rng.randf_range(-6, 6))
			strike_at(spot, p.y - 2.0)
	_update_rainbow(ws, focus, cam_p)

static func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return p.distance_to(a + ab * t)

## A bolt from the cloud base to the ground at `ground` (metres; y is ignored
## and taken as the ground under it if the parent can tell, else 0).
func strike_at(ground: Vector3, top: float = CLOUD_BASE) -> void:
	bolts += 1
	var y0 := ground.y
	var pts: Array = []
	var p := Vector3(ground.x + _rng.randf_range(-3, 3), top, ground.z + _rng.randf_range(-3, 3))
	var steps := 12
	for i in steps + 1:
		var t := float(i) / steps
		var q := p.lerp(Vector3(ground.x, y0, ground.z), t)
		if i > 0 and i < steps:
			q += Vector3(_rng.randf_range(-1.6, 1.6), 0, _rng.randf_range(-1.6, 1.6))
		pts.append(q)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var view := (cam.global_position - ground).normalized() if cam else Vector3(0, 0, 1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var side := (b - a).cross(view).normalized() * 0.22
		st.add_vertex(a - side); st.add_vertex(a + side); st.add_vertex(b + side)
		st.add_vertex(a - side); st.add_vertex(b + side); st.add_vertex(b - side)
		# A small fork now and then.
		if i > 2 and i < steps - 2 and _rng.randf() < 0.25:
			var f := b + Vector3(_rng.randf_range(-4, 4), -_rng.randf_range(2, 5), _rng.randf_range(-4, 4))
			var s2 := (f - b).cross(view).normalized() * 0.12
			st.add_vertex(b - s2); st.add_vertex(b + s2); st.add_vertex(f)
	_bolt.mesh = st.commit()
	_bolt.visible = true
	_bolt_t = BOLT_SECONDS
	_bolt_light.global_position = Vector3(ground.x, y0 + 12.0, ground.z) if is_inside_tree() else Vector3.ZERO
	if _sky:
		_sky.lightning_flash(0.9)
	struck.emit(Vector3(ground.x, y0, ground.z))

func bolt_visible() -> bool:
	return _bolt.visible

func _update_rainbow(ws: WeatherSystem, focus: Vector3, cam_p: Vector3) -> void:
	var s := ws.rainbow_strength if _sun_up else 0.0
	rainbow_shown = s
	if s <= 0.001:
		_rainbow.visible = false
		rainbow_at = Vector3.INF
		return
	var c := ws.rainbow_pos() * World.TILE_SIZE
	# Opposite the sun: the arc stands on the far side of the cleared rain, its
	# face to the sun (so with the sun at your back you see it face on).
	var away := Vector3(-_sun_dir.x, 0.0, -_sun_dir.z)
	if away.length() < 0.05:
		away = Vector3(0, 0, 1)
	away = away.normalized()
	var pos := Vector3(c.x, -4.0, c.y) + away * 22.0
	_rainbow.visible = true
	var b := Basis.looking_at(-away, Vector3.UP)   # local -Z toward the sun's side
	_rainbow.global_transform = Transform3D(b.scaled(Vector3.ONE * RAINBOW_RADIUS), pos) if is_inside_tree() else Transform3D()
	rainbow_at = pos
	_rainbow_mat.set_shader_parameter("strength", s * (1.0 - 0.8 * _night))

# ── Meshes ───────────────────────────────────────────────────────────────────

static func _ball() -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 10
	s.rings = 6
	return s

## An open tube from y = 0 to 1 (scaled to the cloud base).
static func _tube() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 12
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p00 := Vector3(cos(a0), 0, sin(a0))
		var p10 := Vector3(cos(a1), 0, sin(a1))
		var u0 := float(i) / seg
		var u1 := float(i + 1) / seg
		for v in [[p00, u0, 0.0], [p10, u1, 0.0], [p10 + Vector3.UP, u1, 1.0],
				[p00, u0, 0.0], [p10 + Vector3.UP, u1, 1.0], [p00 + Vector3.UP, u0, 1.0]]:
			st.set_uv(Vector2(v[1], v[2]))
			st.add_vertex(v[0])
	return st.commit()

## A half ring in the XY plane, radius 1 at the outer edge; UV.x runs along it,
## UV.y across the band (0 inner, 1 outer).
static func _arc() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 64
	var r0 := 0.80
	for i in seg:
		var a0 := PI * i / seg
		var a1 := PI * (i + 1) / seg
		var in0 := Vector3(cos(a0), sin(a0), 0) * r0
		var in1 := Vector3(cos(a1), sin(a1), 0) * r0
		var out0 := Vector3(cos(a0), sin(a0), 0)
		var out1 := Vector3(cos(a1), sin(a1), 0)
		var u0 := float(i) / seg
		var u1 := float(i + 1) / seg
		for v in [[in0, u0, 0.0], [out0, u0, 1.0], [out1, u1, 1.0], [in0, u0, 0.0], [out1, u1, 1.0], [in1, u1, 0.0]]:
			st.set_uv(Vector2(v[1], v[2]))
			st.add_vertex(v[0])
	return st.commit()
