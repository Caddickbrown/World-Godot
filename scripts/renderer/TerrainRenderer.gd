class_name TerrainRenderer
extends Node3D
## The ground: the World's Heightfield drawn as smooth, vertex-coloured chunks,
## with a depth-shaded sea around the island. Colours come from LookStyle, so
## the look switches with the UI style. Tile changes (felled trees, overgrazing)
## rebuild only their chunk, a few per frame.

const TILE_SIZE := World.TILE_SIZE
const CHUNK_M := 32               # metres per chunk edge
const DIRTY_PER_FLUSH := 2
const SEA_MARGIN := 320.0
## Kept for anything still reading the old constant.
const HEIGHT_SCALE := World.HEIGHT_SCALE

var world: World
var field: Heightfield
var chunk_count := 0
var _chunks: Dictionary = {}      # Vector2i -> MeshInstance3D
var _dirty: Dictionary = {}       # Vector2i -> true
var _material: ShaderMaterial
var _season: Dictionary = {}
var _water: MeshInstance3D
## Settlement centres (world metres) for trampled ground; set by Main.
var camps: Array = []
## The native mesher (native/world_kernels TerrainMesher) when built: a chunk
## in ~1 ms instead of ~16 (and boot 1.7 s faster). null: _chunk_arrays_gd.
var _mesher: Object = null
var _index := PackedInt32Array()   # the same triangles for every chunk

static func tile_color(tile_type: int) -> Color:
	# Minimap and anything else that wants one colour per tile type.
	match tile_type:
		World.TileType.DEEP_WATER: return Color(0.10, 0.22, 0.45)
		World.TileType.WATER:      return Color(0.20, 0.50, 0.62)
		World.TileType.BEACH:      return LookStyle.SAND
		World.TileType.GRASS:      return LookStyle.MEADOW
		World.TileType.WOODLAND:   return LookStyle.WOOD
		World.TileType.FOREST:     return LookStyle.FOREST
		World.TileType.DESERT:     return LookStyle.DESERT
		World.TileType.STONE:      return LookStyle.ROCK
		World.TileType.MOUNTAIN:   return LookStyle.ROCK_DARK
		World.TileType.GLACIER:    return LookStyle.SNOW
		World.TileType.LAVA:       return LookStyle.LAVA
	return Color(0.5, 0.5, 0.5)

func setup(p_world: World) -> void:
	world = p_world
	field = world.heightfield
	if field == null:
		field = Heightfield.new().build(world)
		world.heightfield = field
	_mesher = null
	if World.kernels and ClassDB.class_exists("TerrainMesher"):
		_mesher = ClassDB.instantiate("TerrainMesher")
		_mesher.set_field(field.heights, field.biome, field.n, Heightfield.STEP, field.size_m, TILE_SIZE)
	rebuild()

## The colours the native mesher needs, in its palette order (lib.rs P_*).
## LookStyle stays the one place the look is defined.
static func palette() -> PackedColorArray:
	return PackedColorArray([LookStyle.MEADOW, LookStyle.MEADOW_DRY, LookStyle.WOOD, LookStyle.FOREST,
		LookStyle.ROCK, LookStyle.DESERT, LookStyle.SNOW.lerp(Color(0.75, 0.86, 0.95), 0.3), LookStyle.LAVA,
		LookStyle.BARREN, LookStyle.ASH, LookStyle.RIVER, LookStyle.FLOOD_MUD, LookStyle.SAND,
		LookStyle.WET_SAND, LookStyle.ROCK_DARK, LookStyle.SNOW, LookStyle.g(LookStyle.PARCHED),
		LookStyle.g(LookStyle.BLIGHT), LookStyle.g(LookStyle.TRAMPLED)])

func _sync_palette() -> void:
	if _mesher:
		_mesher.set_palette(palette(), LookStyle.naturalist(), PackedVector2Array(camps))

func rebuild() -> void:
	for ch in get_children():
		ch.queue_free()
	_chunks.clear()
	_dirty.clear()
	# Vertex colours (LookStyle.ground) with the season laid over in the shader,
	# so the year turns through uniforms (set_season), not rebuilds.
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/terrain_season.gdshader")
	SeasonLook.apply(_material, _season)
	chunk_count = int(ceil(field.size_m / CHUNK_M))
	_sync_palette()
	for cz in chunk_count:
		for cx in chunk_count:
			_build_chunk(Vector2i(cx, cz))
	_build_water()

func rebuild_tile(x: int, z: int) -> void:
	var c := Vector2i(int(x * TILE_SIZE / CHUNK_M), int(z * TILE_SIZE / CHUNK_M))
	_dirty[c] = true

## Older callers rebuilt by tile chunk index; now any chunk key works.
func rebuild_chunk(cx: int, cz: int) -> void:
	_dirty[Vector2i(cx, cz)] = true

func flush_dirty() -> void:
	var done := 0
	for c in _dirty.keys():
		if done >= DIRTY_PER_FLUSH:
			break
		_dirty.erase(c)
		_build_chunk(c)
		done += 1

## Everything waiting, now (captures and tests; the game spreads it over frames).
func flush_all() -> void:
	while not _dirty.is_empty():
		flush_dirty()

func _build_chunk(c: Vector2i) -> void:
	if _chunks.has(c):
		(_chunks[c] as Node).queue_free()
	var steps := int(CHUNK_M / Heightfield.STEP)
	if _index.is_empty():
		var count := steps + 1
		for iz in steps:
			for ix in steps:
				var i := iz * count + ix
				_index.append_array([i, i + 1, i + count, i + 1, i + count + 1, i + count])
	var arrays := _chunk_arrays(c)
	var mesh_arrays := []
	mesh_arrays.resize(Mesh.ARRAY_MAX)
	mesh_arrays[Mesh.ARRAY_VERTEX] = arrays[0]
	mesh_arrays[Mesh.ARRAY_NORMAL] = arrays[1]
	mesh_arrays[Mesh.ARRAY_COLOR] = arrays[2]
	mesh_arrays[Mesh.ARRAY_INDEX] = _index
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material
	add_child(mi)
	_chunks[c] = mi

## A chunk's [vertices, normals, colours], natively when built.
func _chunk_arrays(c: Vector2i) -> Array:
	if _mesher == null:
		return _chunk_arrays_gd(c)
	var tiles := int(CHUNK_M / TILE_SIZE)
	var win := Vector2i(c.x * tiles - 1, c.y * tiles - 1)
	var w := tiles + 3
	var ttype := PackedByteArray(); ttype.resize(w * w)
	var flags := PackedByteArray(); flags.resize(w * w)
	var depl := PackedFloat32Array(); depl.resize(w * w)
	var drought := PackedFloat32Array(); drought.resize(w * w)
	var blight := PackedFloat32Array(); blight.resize(w * w)
	for wz in w:
		for wx in w:
			var i := wz * w + wx
			var t := world.get_tile(win.x + wx, win.y + wz)
			if t.is_empty():
				ttype[i] = 255
				continue
			ttype[i] = int(t["type"])
			flags[i] = (1 if bool(t.get("tree_cut", false)) else 0) | (2 if float(t.get("burnt", 0.0)) > 0.0 else 0) \
				| (4 if bool(t.get("river", false)) else 0) | (8 if bool(t.get("flooded", false)) else 0)
			depl[i] = world.depletion_of(t)
			drought[i] = float(t.get("drought", 0.0))
			blight[i] = float(t.get("blight", 0.0))
	return _mesher.chunk(c.x * CHUNK_M, c.y * CHUNK_M, int(CHUNK_M / Heightfield.STEP), win, w,
		ttype, flags, depl, drought, blight)

## The GDScript chunk: the fallback, and what the native one is held to.
func _chunk_arrays_gd(c: Vector2i) -> Array:
	var x0 := c.x * CHUNK_M
	var z0 := c.y * CHUNK_M
	var steps := int(CHUNK_M / Heightfield.STEP)
	var count := steps + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for iz in count:
		for ix in count:
			var x := minf(x0 + ix * Heightfield.STEP, field.size_m)
			var z := minf(z0 + iz * Heightfield.STEP, field.size_m)
			var h := field.height_at(x, z)
			var nrm := field.normal_at(x, z)
			var tile := world.get_tile_f(x / TILE_SIZE, z / TILE_SIZE)
			var wob := sin(x * 0.07 + z * 0.05) * cos(z * 0.09 - x * 0.03) * 0.5 + 0.5
			var col := LookStyle.ground(field.biome_at(x, z), h, nrm, tile, wob, world.depletion_of(tile))
			col = LookStyle.disaster_tint(col, _field_at(x, z, "drought"), _field_at(x, z, "blight"))
			col = _trample(col, x, z)
			verts.append(Vector3(x, h, z))
			normals.append(nrm)
			colors.append(col)
	return [verts, normals, colors]

## A per-tile amount (DisasterSystem's drought / blight) read smoothly between
## tile centres, so a drought's edge is a gradient, never a staircase.
func _field_at(x: float, z: float, key: String) -> float:
	var tx := x / TILE_SIZE - 0.5
	var tz := z / TILE_SIZE - 0.5
	var x0 := floori(tx)
	var z0 := floori(tz)
	var fx := tx - x0
	var fz := tz - z0
	var a := _tile_val(x0, z0, key)
	var b := _tile_val(x0 + 1, z0, key)
	var c := _tile_val(x0, z0 + 1, key)
	var d := _tile_val(x0 + 1, z0 + 1, key)
	if a == 0.0 and b == 0.0 and c == 0.0 and d == 0.0:
		return 0.0
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)

func _tile_val(x: int, z: int, key: String) -> float:
	var t := world.get_tile(x, z)
	return 0.0 if t.is_empty() else float(t.get(key, 0.0))

## The season's look (SeasonLook.blend): a few uniforms, set when they move.
func set_season(b: Dictionary) -> void:
	var changed := _season.is_empty()
	for k in b:
		if absf(float(b[k]) - float(_season.get(k, -1.0))) > 0.004:
			changed = true
	if not changed:
		return
	_season = b.duplicate()
	SeasonLook.apply(_material, _season)

func season_value(key: String) -> float:
	return float(_season.get(key, 0.0))

func _trample(col: Color, x: float, z: float) -> Color:
	for p in camps:
		var d := Vector2(x - p.x, z - p.y).length()
		if d < 9.0:
			col = col.lerp(LookStyle.g(LookStyle.TRAMPLED), (1.0 - smoothstep(3.5, 9.0, d)) * 0.85)
	return col

## Repaint chunks under these camps (world metres) when settlements change.
func set_camps(centres: Array) -> void:
	var changed := centres.size() != camps.size()
	if not changed:
		for i in centres.size():
			if (centres[i] as Vector2).distance_to(camps[i]) > 1.0:
				changed = true
				break
	if not changed:
		return
	var touched: Array = camps.duplicate() + centres
	camps = centres
	_sync_palette()
	for p in touched:
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var q: Vector2 = p + Vector2(dx, dz) * 9.0
				_dirty[Vector2i(clampi(int(q.x / CHUNK_M), 0, chunk_count - 1), clampi(int(q.y / CHUNK_M), 0, chunk_count - 1))] = true

func _build_water() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 2.0
	var n := int((field.size_m + SEA_MARGIN * 2.0) / step) + 1
	for iz in n:
		for ix in n:
			var x := -SEA_MARGIN + ix * step
			var z := -SEA_MARGIN + iz * step
			var inside := x >= 0.0 and z >= 0.0 and x <= field.size_m and z <= field.size_m
			var d := (Heightfield.SEA_LEVEL - field.height_at(x, z)) if inside else 40.0
			st.set_color(Color(clampf(d / 10.0, -0.1, 1.0), 0, 0))
			st.add_vertex(Vector3(x, Heightfield.SEA_LEVEL, z))
	for iz in n - 1:
		for ix in n - 1:
			var i := iz * n + ix
			st.add_index(i); st.add_index(i + 1); st.add_index(i + n)
			st.add_index(i + 1); st.add_index(i + n + 1); st.add_index(i + n)
	st.generate_normals()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/mockup_water.gdshader")
	if LookStyle.naturalist():
		mat.set_shader_parameter("shallow_color", Color(0.42, 0.62, 0.58))
		mat.set_shader_parameter("mid_color", Color(0.18, 0.38, 0.45))
		mat.set_shader_parameter("deep_color", Color(0.08, 0.17, 0.26))
		mat.set_shader_parameter("foam_color", Color(0.86, 0.88, 0.85))
	_water = MeshInstance3D.new()
	_water.mesh = st.commit()
	_water.material_override = mat
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(field.size_m + SEA_MARGIN * 2.0, field.size_m + SEA_MARGIN * 2.0)
	floor_mi.mesh = plane
	floor_mi.position = Vector3(field.size_m / 2.0, -12.0, field.size_m / 2.0)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.05, 0.16, 0.30)
	floor_mi.material_override = fm
	add_child(floor_mi)
