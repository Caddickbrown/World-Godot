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
var _material: StandardMaterial3D
var _water: MeshInstance3D
## Settlement centres (world metres) for trampled ground; set by Main.
var camps: Array = []

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
	rebuild()

func rebuild() -> void:
	for ch in get_children():
		ch.queue_free()
	_chunks.clear()
	_dirty.clear()
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.roughness = 0.95
	chunk_count = int(ceil(field.size_m / CHUNK_M))
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

func _build_chunk(c: Vector2i) -> void:
	if _chunks.has(c):
		(_chunks[c] as Node).queue_free()
	var x0 := c.x * CHUNK_M
	var z0 := c.y * CHUNK_M
	var steps := int(CHUNK_M / Heightfield.STEP)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := steps + 1
	for iz in count:
		for ix in count:
			var x := minf(x0 + ix * Heightfield.STEP, field.size_m)
			var z := minf(z0 + iz * Heightfield.STEP, field.size_m)
			var h := field.height_at(x, z)
			var nrm := field.normal_at(x, z)
			var tile := world.get_tile_f(x / TILE_SIZE, z / TILE_SIZE)
			var wob := sin(x * 0.07 + z * 0.05) * cos(z * 0.09 - x * 0.03) * 0.5 + 0.5
			var col := LookStyle.ground(field.biome_at(x, z), h, nrm, tile, wob)
			col = _trample(col, x, z)
			st.set_color(col)
			st.set_normal(nrm)
			st.add_vertex(Vector3(x, h, z))
	for iz in steps:
		for ix in steps:
			var i := iz * count + ix
			st.add_index(i); st.add_index(i + 1); st.add_index(i + count)
			st.add_index(i + 1); st.add_index(i + count + 1); st.add_index(i + count)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _material
	add_child(mi)
	_chunks[c] = mi

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
