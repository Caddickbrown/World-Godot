extends Node3D
## "Starting again": a look-and-feel mockup, not game code.
##
## Same world generator as the game (World.gd: same seed, same land and water,
## same biomes), drawn the way the new art direction proposes:
##   - smooth, real relief (hills, valleys, peaks) instead of flat 2 m tiles
##   - water with depth: turquoise shallows, ink-blue deeps, a foam line
##   - a sky, a sun that casts shadows, haze into the distance
##   - stylised trees with per-tree colour, rocks, snow on the peaks
##   - people as chunky, readable figures in tribe colours, round a camp
##   - a tilt-shift blur that sells "a little world you're watching"
## Everything is primitives and vertex colour: no texture work, cheap to draw.
## Render it with tools/capture/mockup.sh.

const STEP := 1.0                 # metres between terrain vertices (2 per tile)
const SEA_LEVEL := 0.0
const LAND_SCALE := 7.0           # metres of rise per unit of noise above the coast
const MOUNTAIN_SCALE := 70.0      # extra rise for the high ground (quadratic)
const SEA_SCALE := 18.0           # metres of depth per unit of noise below the coast
const COAST := -0.22              # World._generate's water threshold

var world: World
var size_m: float
var _heights: PackedFloat32Array
var _n: int                       # vertices per side
var sun: DirectionalLight3D
var env: Environment
var camera: Camera3D
var camp_centre: Vector3
var _rng := RandomNumberGenerator.new()
var _fire_light: OmniLight3D

func build(world_seed: int) -> void:
	_rng.seed = world_seed
	world = World.new(world_seed)
	size_m = World.WORLD_WIDTH * World.TILE_SIZE
	_n = int(size_m / STEP) + 1
	_build_heights()
	_build_environment()
	camp_centre = _find_camp_centre()
	_build_terrain()
	_build_water()
	_build_flora()
	_build_camp()
	camera = Camera3D.new()
	camera.fov = 40.0
	camera.far = 1200.0
	add_child(camera)
	camera.current = true

# ── Height ──────────────────────────────────────────────────────────────────

## World._noise, sampled continuously (it is a sum of sines, so fractional
## coordinates are valid) — the coastline matches the game's tile map.
func _noise_f(x: float, z: float) -> float:
	var s := world.seed_val * 0.137
	var ns := World.NOISE_REFERENCE_SIZE / float(World.WORLD_WIDTH)
	var fx := x * ns
	var fz := z * ns
	var base := (
		sin(fx * 0.18 + s) * cos(fz * 0.14 + s * 1.71) * 0.45 +
		sin(fx * 0.35 + s * 2.13) * cos(fz * 0.29 + s * 0.63) * 0.30 +
		sin(fx * 0.72 + s * 0.54) * cos(fz * 0.61 + s * 1.23) * 0.15 +
		cos(fx * 0.11 + fz * 0.16 + s * 1.87) * 0.25) / 1.15
	var detail := (sin(x * 0.31 + s * 3.1) * cos(z * 0.27 + s * 2.2) * 0.6 +
		sin(x * 0.63 + s * 1.4) * cos(z * 0.55 + s * 3.7) * 0.4)
	return base + detail * 0.055 * (1.0 - ns)

## The proposal makes the world an island: land falls away to sea at the map
## edge instead of stopping in a square cliff. Same noise inside.
func _shaped_noise(tx: float, tz: float) -> float:
	var u := absf(tx / World.WORLD_WIDTH * 2.0 - 1.0)
	var v := absf(tz / World.WORLD_HEIGHT * 2.0 - 1.0)
	var edge := smoothstep(0.72, 1.0, maxf(u, v))
	return _noise_f(tx, tz) - edge * 0.9

## Biome from the same thresholds World._generate uses, read off the continuous
## field so borders curve instead of stepping along tile edges.
func biome_at(x: float, z: float) -> float:
	return _shaped_noise(x / World.TILE_SIZE, z / World.TILE_SIZE)

func _height_from_noise(n: float, tx: float, tz: float) -> float:
	var h: float
	if n < COAST:
		h = (n - COAST) * SEA_SCALE
	else:
		var above := n - COAST
		h = above * LAND_SCALE + pow(maxf(0.0, n - 0.45), 2.0) * MOUNTAIN_SCALE
		# A little roughness so meadows aren't billiard tables.
		h += (sin(tx * 1.7 + tz * 0.9) * cos(tz * 1.3 - tx * 0.4)) * 0.18 * clampf(above * 4.0, 0.0, 1.0)
	return h

func _build_heights() -> void:
	_heights.resize(_n * _n)
	for iz in _n:
		for ix in _n:
			var tx := ix * STEP / World.TILE_SIZE
			var tz := iz * STEP / World.TILE_SIZE
			_heights[iz * _n + ix] = _height_from_noise(_shaped_noise(tx, tz), tx, tz)

## Ground height at a world-space point (bilinear).
func height_at(x: float, z: float) -> float:
	var fx := clampf(x / STEP, 0.0, _n - 1.001)
	var fz := clampf(z / STEP, 0.0, _n - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var ax := fx - ix
	var az := fz - iz
	var h00 := _heights[iz * _n + ix]
	var h10 := _heights[iz * _n + ix + 1]
	var h01 := _heights[(iz + 1) * _n + ix]
	var h11 := _heights[(iz + 1) * _n + ix + 1]
	return lerpf(lerpf(h00, h10, ax), lerpf(h01, h11, ax), az)

func _normal_at(x: float, z: float) -> Vector3:
	var e := STEP
	return Vector3(height_at(x - e, z) - height_at(x + e, z), 2.0 * e,
		height_at(x, z - e) - height_at(x, z + e)).normalized()

func _tile_type(x: float, z: float) -> int:
	var t := world.get_tile_f(x / World.TILE_SIZE, z / World.TILE_SIZE)
	return -1 if t.is_empty() else int(t["type"])

# ── Palette ─────────────────────────────────────────────────────────────────

const C_SAND := Color(0.90, 0.80, 0.58)
const C_WET_SAND := Color(0.72, 0.62, 0.45)
const C_MEADOW := Color(0.42, 0.62, 0.26)
const C_MEADOW_DRY := Color(0.62, 0.64, 0.32)
const C_TRAMPLED := Color(0.60, 0.50, 0.35)
const C_WOOD := Color(0.30, 0.52, 0.22)
const C_FOREST := Color(0.18, 0.38, 0.17)
const C_DESERT := Color(0.86, 0.68, 0.42)
const C_ROCK := Color(0.55, 0.52, 0.50)
const C_ROCK_DARK := Color(0.40, 0.38, 0.38)
const C_SNOW := Color(0.95, 0.97, 1.0)

func _ground_color(x: float, z: float, h: float, nrm: Vector3) -> Color:
	var n := biome_at(x, z)
	# Meadow -> woodland -> forest -> rock, blended across each threshold.
	var c := C_MEADOW
	c = c.lerp(C_WOOD, smoothstep(0.14, 0.22, n))
	c = c.lerp(C_FOREST, smoothstep(0.27, 0.35, n))
	c = c.lerp(C_ROCK, smoothstep(0.50, 0.58, n))
	var t := World.TileType.GRASS if n < 0.18 else -1
	# Large soft patches so a meadow reads as a meadow, not a flat colour.
	var patch := sin(x * 0.07 + z * 0.05) * cos(z * 0.09 - x * 0.03) * 0.5 + 0.5
	if t == World.TileType.GRASS:
		c = c.lerp(C_MEADOW_DRY, patch * 0.45)
	if h < 0.35 and h > -2.0:
		c = c.lerp(C_SAND, 0.85 if h > 0.0 else 0.4)
	if h <= 0.0:
		c = c.lerp(C_WET_SAND, clampf(-h / 2.0, 0.0, 1.0))
	# Trampled earth round the camp, fading out into the grass.
	if camp_centre != Vector3.ZERO:
		var dc := Vector2(x - camp_centre.x, z - camp_centre.z).length()
		c = c.lerp(C_TRAMPLED, (1.0 - smoothstep(3.5, 8.0, dc + patch * 2.0)) * 0.9)
	# Steep ground shows rock; high ground gets snow.
	var slope := 1.0 - nrm.y
	c = c.lerp(C_ROCK_DARK, smoothstep(0.25, 0.55, slope))
	c = c.lerp(C_SNOW, smoothstep(13.0, 17.0, h) * (1.0 - smoothstep(0.35, 0.6, slope)))
	return c

# ── Terrain ─────────────────────────────────────────────────────────────────

func _build_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in _n:
		for ix in _n:
			var x := ix * STEP
			var z := iz * STEP
			var h := _heights[iz * _n + ix]
			var nrm := _normal_at(x, z)
			st.set_color(_ground_color(x, z, h, nrm))
			st.set_normal(nrm)
			st.add_vertex(Vector3(x, h, z))
	for iz in _n - 1:
		for ix in _n - 1:
			var i := iz * _n + ix
			st.add_index(i); st.add_index(i + 1); st.add_index(i + _n)
			st.add_index(i + 1); st.add_index(i + _n + 1); st.add_index(i + _n)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.95
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)

func _build_water() -> void:
	# A grid over the sea carrying depth in vertex colour, plus a far skirt.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 2.0
	var margin := 300.0
	var n := int((size_m + margin * 2.0) / step) + 1
	for iz in n:
		for ix in n:
			var x := -margin + ix * step
			var z := -margin + iz * step
			var inside := x >= 0.0 and z >= 0.0 and x <= size_m and z <= size_m
			var d := (SEA_LEVEL - height_at(x, z)) if inside else 40.0
			st.set_color(Color(clampf(d / 10.0, -0.1, 1.0), 0, 0))
			st.add_vertex(Vector3(x, SEA_LEVEL, z))
	for iz in n - 1:
		for ix in n - 1:
			var i := iz * n + ix
			st.add_index(i); st.add_index(i + 1); st.add_index(i + n)
			st.add_index(i + 1); st.add_index(i + n + 1); st.add_index(i + n)
	st.generate_normals()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/mockup_water.gdshader")
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Under-sea skirt so the world's edge isn't a cliff into the void.
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size_m + margin * 2.0, size_m + margin * 2.0)
	floor_mi.mesh = plane
	floor_mi.position = Vector3(size_m / 2.0, -9.0, size_m / 2.0)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.05, 0.16, 0.30)
	floor_mi.material_override = fm
	add_child(floor_mi)

# ── Flora ───────────────────────────────────────────────────────────────────

func _mm(mesh: Mesh, xforms: Array, colors: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.9
	inst.material_override = mat
	add_child(inst)

func _cone(r: float, h: float, segs: int = 7) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c

func _ball(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 1.8
	s.radial_segments = 8
	s.rings = 5
	return s

func _build_flora() -> void:
	var pine_lo: Array = []; var pine_lo_c: Array = []
	var pine_hi: Array = []; var pine_hi_c: Array = []
	var crowns: Array = []; var crowns_c: Array = []
	var trunks: Array = []; var trunks_c: Array = []
	var rocks: Array = []; var rocks_c: Array = []
	var bushes: Array = []; var bushes_c: Array = []
	var trunk_col := Color(0.42, 0.29, 0.20)
	var spacing := 2.2
	var count := int(size_m / spacing)
	for iz in count:
		for ix in count:
			var x := ix * spacing + _rng.randf_range(-0.9, 0.9)
			var z := iz * spacing + _rng.randf_range(-0.9, 0.9)
			var h := height_at(x, z)
			if h < 0.6 or Vector2(x - camp_centre.x, z - camp_centre.z).length() < 9.0:
				continue
			var nrm := _normal_at(x, z)
			var bn := biome_at(x, z)
			var t: int = World.TileType.GRASS
			if bn > 0.52: t = World.TileType.STONE
			elif bn > 0.30: t = World.TileType.FOREST
			elif bn > 0.18: t = World.TileType.WOODLAND
			var roll := _rng.randf()
			var yaw := _rng.randf() * TAU
			var b := Basis(Vector3.UP, yaw)
			# Clumps: a slow noise decides where woods thicken.
			var clump := sin(x * 0.11 + z * 0.07) * cos(z * 0.13 - x * 0.05) * 0.5 + 0.5
			if t == World.TileType.FOREST and roll < 0.55 + clump * 0.3 and nrm.y > 0.8:
				var s := _rng.randf_range(0.8, 1.35)
				var tint := Color(0.16, 0.36, 0.20).lerp(Color(0.26, 0.45, 0.22), _rng.randf())
				pine_lo.append(Transform3D(b.scaled(Vector3(s, s, s)), Vector3(x, h + 1.6 * s, z)))
				pine_lo_c.append(tint)
				pine_hi.append(Transform3D(b.scaled(Vector3(s, s, s)), Vector3(x, h + 3.0 * s, z)))
				pine_hi_c.append(tint.lightened(0.08))
				trunks.append(Transform3D(b.scaled(Vector3(s, s, s)), Vector3(x, h + 0.5 * s, z)))
				trunks_c.append(trunk_col)
			elif (t == World.TileType.WOODLAND and roll < 0.30 + clump * 0.3) or (t == World.TileType.GRASS and roll < 0.025 * clump * 3.0):
				if nrm.y < 0.85:
					continue
				var s := _rng.randf_range(0.8, 1.3)
				var tint := Color(0.36, 0.58, 0.24).lerp(Color(0.58, 0.68, 0.26), _rng.randf() * 0.6)
				if _rng.randf() < 0.08:
					tint = Color(0.86, 0.55, 0.22)  # the odd tree turning early
				trunks.append(Transform3D(b.scaled(Vector3(s, s * 1.4, s)), Vector3(x, h + 0.7 * s, z)))
				trunks_c.append(trunk_col)
				crowns.append(Transform3D(b.scaled(Vector3(s, s * 0.9, s)), Vector3(x, h + 2.4 * s, z)))
				crowns_c.append(tint)
				crowns.append(Transform3D(b.scaled(Vector3(s * 0.7, s * 0.6, s * 0.7)), Vector3(x + 0.6 * s, h + 2.0 * s, z + 0.3 * s)))
				crowns_c.append(tint.darkened(0.08))
			elif t == World.TileType.GRASS and roll < 0.07:
				var s := _rng.randf_range(0.5, 0.9)
				bushes.append(Transform3D(b.scaled(Vector3(s, s * 0.7, s)), Vector3(x, h + 0.2, z)))
				var berry := _rng.randf() < 0.4
				bushes_c.append(Color(0.30, 0.50, 0.22) if not berry else Color(0.42, 0.45, 0.24))
			elif (t == World.TileType.STONE or t == World.TileType.MOUNTAIN or nrm.y < 0.7) and roll < 0.12:
				var s := _rng.randf_range(0.5, 1.6)
				rocks.append(Transform3D(b.scaled(Vector3(s * 1.3, s * 0.8, s)), Vector3(x, h + 0.1, z)))
				rocks_c.append(C_ROCK.lerp(C_ROCK_DARK, _rng.randf()))
	_mm(_cone(1.3, 2.6), pine_lo, pine_lo_c)
	_mm(_cone(0.95, 2.0), pine_hi, pine_hi_c)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.12
	trunk.bottom_radius = 0.18
	trunk.height = 1.0
	trunk.radial_segments = 6
	_mm(trunk, trunks, trunks_c)
	_mm(_ball(1.2), crowns, crowns_c)
	_mm(_ball(0.8), bushes, bushes_c)
	var rock := SphereMesh.new()
	rock.radius = 0.6
	rock.height = 1.0
	rock.radial_segments = 5
	rock.rings = 3
	_mm(rock, rocks, rocks_c)

# ── The camp: where the founders are ─────────────────────────────────────────

const TRIBE := [Color(0.80, 0.42, 0.22), Color(0.88, 0.70, 0.30), Color(0.62, 0.30, 0.24), Color(0.92, 0.86, 0.70)]
const SKIN := [Color(0.93, 0.76, 0.60), Color(0.78, 0.56, 0.40), Color(0.55, 0.37, 0.26), Color(0.98, 0.84, 0.70)]
const HAIR := [Color(0.16, 0.11, 0.08), Color(0.36, 0.22, 0.12), Color(0.62, 0.42, 0.22), Color(0.85, 0.82, 0.78)]

func _build_camp() -> void:
	# Fire: stones, logs, flame, light.
	for i in 8:
		var a := TAU * i / 8.0
		_prop(_ball(0.22), Color(0.5, 0.48, 0.46), camp_centre + Vector3(cos(a) * 0.75, 0.1, sin(a) * 0.75))
	var flame := MeshInstance3D.new()
	flame.mesh = _cone(0.42, 1.1)
	flame.position = camp_centre + Vector3(0, 0.6, 0)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(1.0, 0.62, 0.22)
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.45, 0.12)
	fmat.emission_energy_multiplier = 4.0
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.material_override = fmat
	add_child(flame)
	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color(1.0, 0.6, 0.3)
	_fire_light.omni_range = 14.0
	_fire_light.light_energy = 2.5
	_fire_light.shadow_enabled = true
	_fire_light.position = camp_centre + Vector3(0, 1.4, 0)
	add_child(_fire_light)

	# Hide tents round the fire.
	for i in 4:
		var a := TAU * (i + 0.3) / 4.0
		var p := camp_centre + Vector3(cos(a) * 5.0, 0, sin(a) * 5.0)
		p.y = height_at(p.x, p.z)
		var tent := MeshInstance3D.new()
		tent.mesh = _cone(1.5, 2.6, 6)
		tent.position = p + Vector3(0, 1.3, 0)
		var tm := StandardMaterial3D.new()
		tm.albedo_color = Color(0.74, 0.60, 0.44).darkened(i * 0.05)
		tm.roughness = 1.0
		tent.material_override = tm
		add_child(tent)
		_prop(_cone(0.05, 0.9, 4), Color(0.4, 0.3, 0.2), p + Vector3(0.0, 2.8, 0.0))
	# Drying rack and a woodpile.
	for i in 5:
		_prop(_ball(0.16), Color(0.45, 0.32, 0.22), camp_centre + Vector3(-3.0 + i * 0.25, 0.15, 2.4), Vector3(0.6, 0.6, 3.0))

	# People: round the fire, at work, children running.
	var placements := [
		[1.6, 0.0, "sit"], [1.7, 1.2, "sit"], [1.6, 2.4, "sit"], [1.8, 3.6, "stand"],
		[1.7, 4.8, "sit"], [3.3, 5.6, "stand"], [3.0, 2.0, "child"], [3.6, 2.4, "child"],
		[9.0, 0.6, "stand"], [10.5, 1.0, "stand"], [12.0, 4.2, "stand"], [8.0, 3.9, "child"],
	]
	for i in placements.size():
		var pl: Array = placements[i]
		var a: float = pl[1]
		var r: float = pl[0]
		var p := camp_centre + Vector3(cos(a) * r, 0, sin(a) * r)
		p.y = height_at(p.x, p.z)
		var face := atan2(camp_centre.x - p.x, camp_centre.z - p.z) if r < 4.0 else _rng.randf() * TAU
		_person(p, face, str(pl[2]), i)

func _find_camp_centre() -> Vector3:
	var pts: Array = world.get_spawn_points(40)
	var c := Vector2.ZERO
	for p in pts:
		c += Vector2(float(p["x"]), float(p["z"]))
	c /= float(pts.size())
	return _flat_spot_near(c.x * World.TILE_SIZE, c.y * World.TILE_SIZE)

func _flat_spot_near(x: float, z: float) -> Vector3:
	var best := Vector3(x, height_at(x, z), z)
	var best_score := INF
	for i in 120:
		var px := x + _rng.randf_range(-20, 20)
		var pz := z + _rng.randf_range(-20, 20)
		var h := height_at(px, pz)
		if h < 1.0: continue
		var score := (1.0 - _normal_at(px, pz).y) * 40.0 + Vector2(px - x, pz - z).length() * 0.05
		if score < best_score:
			best_score = score
			best = Vector3(px, h, pz)
	return best

func _prop(mesh: Mesh, color: Color, pos: Vector3, scale_v: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scale_v
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	mi.material_override = m
	add_child(mi)
	return mi

## A readable figure: big head, tunic in tribe colour, hair. Proportions are
## pushed (head ~1/4 of height) so a person reads from the observer's height.
func _person(feet: Vector3, yaw: float, pose: String, i: int) -> void:
	var root := Node3D.new()
	root.position = feet
	root.rotation.y = yaw
	add_child(root)
	var s := 0.65 if pose == "child" else 1.0
	var sit := pose == "sit"
	var tunic := StandardMaterial3D.new()
	tunic.albedo_color = TRIBE[i % TRIBE.size()]
	tunic.roughness = 0.9
	var skin := StandardMaterial3D.new()
	skin.albedo_color = SKIN[(i * 3) % SKIN.size()]
	var hair := StandardMaterial3D.new()
	hair.albedo_color = HAIR[(i * 7 + 1) % HAIR.size()]
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.28 * s
	cap.height = (0.9 if sit else 1.15) * s
	body.mesh = cap
	body.position.y = (0.45 if sit else 0.78) * s
	body.material_override = tunic
	root.add_child(body)
	var head := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.24 * s
	hs.height = 0.48 * s
	head.mesh = hs
	head.position.y = (1.05 if sit else 1.55) * s
	head.material_override = skin
	root.add_child(head)
	var hr := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.26 * s
	hm.height = 0.3 * s
	hm.is_hemisphere = true
	hr.mesh = hm
	hr.position.y = head.position.y + 0.03 * s
	hr.position.z = -0.03 * s
	hr.material_override = hair
	root.add_child(hr)
	# Eyes: bigger than life, so they read from the observer's height.
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.08, 0.06, 0.05)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.045 * s
		em.height = 0.09 * s
		eye.mesh = em
		eye.position = Vector3(side * 0.09 * s, head.position.y + 0.02 * s, 0.21 * s)
		eye.material_override = eye_mat
		root.add_child(eye)
	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var lm := CapsuleMesh.new()
		lm.radius = 0.1 * s
		lm.height = 0.5 * s
		leg.mesh = lm
		leg.material_override = skin
		if sit:
			leg.rotation.x = PI / 2.0
			leg.position = Vector3(side * 0.12 * s, 0.12 * s, 0.25 * s)
		else:
			leg.position = Vector3(side * 0.12 * s, 0.25 * s, 0)
		root.add_child(leg)

# ── Light, sky, air ─────────────────────────────────────────────────────────

func _build_environment() -> void:
	env = Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.32, 0.55, 0.85)
	sm.sky_horizon_color = Color(0.78, 0.84, 0.88)
	sm.ground_horizon_color = Color(0.70, 0.76, 0.80)
	sm.ground_bottom_color = Color(0.20, 0.28, 0.36)
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.92
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.82, 0.90)
	env.fog_density = 0.0016
	env.fog_sun_scatter = 0.25
	env.fog_aerial_perspective = 0.6
	env.ssao_enabled = true
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	sun.light_angular_distance = 1.0
	add_child(sun)
	set_hour(10.0)

## Sun, sky and fire for a time of day (6 = sunrise, 19.5 = sunset).
func set_hour(hour: float) -> void:
	var day := clampf((hour - 6.0) / 13.5, 0.0, 1.0)  # 0 sunrise .. 1 sunset
	var elev := sin(day * PI)
	sun.rotation = Vector3(-deg_to_rad(4.0 + 60.0 * elev), deg_to_rad(lerpf(-100.0, 100.0, day)) + PI, 0)
	var warm := 1.0 - smoothstep(0.15, 0.45, elev)
	sun.light_color = Color(1.0, 0.97, 0.90).lerp(Color(1.0, 0.62, 0.36), warm)
	sun.light_energy = lerpf(0.35, 1.25, smoothstep(0.0, 0.5, elev))
	var sm := env.sky.sky_material as ProceduralSkyMaterial
	sm.sky_horizon_color = Color(0.78, 0.84, 0.88).lerp(Color(0.98, 0.70, 0.50), warm)
	sm.sky_top_color = Color(0.32, 0.55, 0.85).lerp(Color(0.30, 0.38, 0.62), warm)
	env.fog_light_color = Color(0.74, 0.82, 0.90).lerp(Color(0.95, 0.72, 0.58), warm)
	if _fire_light:
		_fire_light.light_energy = lerpf(1.2, 4.0, warm)

## Point the camera; tilt_shift > 0 blurs near and far like a miniature.
func frame(cam_pos: Vector3, look: Vector3, tilt_shift: float = 0.0) -> void:
	camera.position = cam_pos
	camera.look_at(look, Vector3.UP)
	if tilt_shift > 0.0:
		var attrs := CameraAttributesPractical.new()
		var dist := cam_pos.distance_to(look)
		attrs.dof_blur_far_enabled = true
		attrs.dof_blur_far_distance = dist * 1.25
		attrs.dof_blur_far_transition = dist * 0.8
		attrs.dof_blur_near_enabled = true
		attrs.dof_blur_near_distance = dist * 0.6
		attrs.dof_blur_near_transition = dist * 0.3
		attrs.dof_blur_amount = 0.12 * tilt_shift
		camera.attributes = attrs
