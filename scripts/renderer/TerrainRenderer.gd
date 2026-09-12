class_name TerrainRenderer
extends Node3D

const TILE_SIZE := World.TILE_SIZE

## Tiles per chunk edge. The world is split into CHUNK_TILES x CHUNK_TILES
## chunks so each chunk becomes its own MeshInstance3D (frustum-cullable,
## independently rebuildable).
const CHUNK_TILES := 16

## World-space height per elevation unit (kept identical to the old renderer).
const HEIGHT_SCALE := 0.3

## How far below a border tile's own height the world-edge skirt extends,
## so you don't see under the world at a low camera angle.
const BORDER_SKIRT_DEPTH := 0.5

## Max number of dirty chunks rebuilt per flush_dirty() call, so a burst of
## tile changes (e.g. a spreading wildfire) can't spike a frame.
const DIRTY_PER_FLUSH := 2

var world: World

var chunk_cols: int = 0
var chunk_rows: int = 0

var _chunk_instances: Dictionary = {}   # "cx,cz" -> MeshInstance3D
var _dirty_chunks: Dictionary = {}      # "cx,cz" -> true
var _material: StandardMaterial3D

# Tile colours (base)
static func tile_color(tile_type: int) -> Color:
	match tile_type:
		World.TileType.DEEP_WATER: return Color(0.10, 0.22, 0.55)
		World.TileType.WATER:      return Color(0.18, 0.38, 0.72)
		World.TileType.BEACH:      return Color(0.85, 0.80, 0.60)
		World.TileType.GRASS:      return Color(0.34, 0.62, 0.25)
		World.TileType.WOODLAND:   return Color(0.22, 0.50, 0.18)
		World.TileType.FOREST:     return Color(0.10, 0.38, 0.12)
		World.TileType.DESERT:     return Color(0.82, 0.72, 0.42)
		World.TileType.STONE:      return Color(0.55, 0.52, 0.50)
		World.TileType.MOUNTAIN:   return Color(0.70, 0.68, 0.65)
		World.TileType.GLACIER:    return Color(0.85, 0.92, 0.98)
		World.TileType.LAVA:       return Color(0.85, 0.25, 0.08)
	return Color(0.5, 0.5, 0.5)

func setup(p_world: World) -> void:
	world = p_world
	rebuild()

## Full rebuild: regenerates every chunk from scratch. Still used by
## Main.gd right after world generation.
func rebuild() -> void:
	if world == null:
		return
	_ensure_material()

	for child in get_children():
		child.queue_free()
	_chunk_instances.clear()
	_dirty_chunks.clear()

	chunk_cols = (world.width + CHUNK_TILES - 1) / CHUNK_TILES
	chunk_rows = (world.height + CHUNK_TILES - 1) / CHUNK_TILES

	for cz in range(chunk_rows):
		for cx in range(chunk_cols):
			_rebuild_chunk_mesh(cx, cz)

## Marks the chunk containing tile (x, z) dirty. It will be rebuilt on the
## next flush_dirty() (or immediately if rebuild_chunk() is called directly).
func rebuild_tile(x: int, z: int) -> void:
	if world == null or chunk_cols <= 0 or chunk_rows <= 0:
		return
	var cx := x / CHUNK_TILES
	var cz := z / CHUNK_TILES
	_mark_dirty(cx, cz)

	# A tile's height skirts can be built by a neighbouring chunk (the skirt
	# is only emitted by the taller side of a boundary), so a tile sitting on
	# a chunk edge can also affect the adjacent chunk's mesh.
	if x % CHUNK_TILES == 0 and x > 0:
		_mark_dirty(cx - 1, cz)
	if x % CHUNK_TILES == CHUNK_TILES - 1:
		_mark_dirty(cx + 1, cz)
	if z % CHUNK_TILES == 0 and z > 0:
		_mark_dirty(cx, cz - 1)
	if z % CHUNK_TILES == CHUNK_TILES - 1:
		_mark_dirty(cx, cz + 1)

## Immediately rebuilds a single chunk's mesh.
func rebuild_chunk(cx: int, cz: int) -> void:
	if world == null:
		return
	_rebuild_chunk_mesh(cx, cz)
	_dirty_chunks.erase("%d,%d" % [cx, cz])

## Rebuilds a handful of dirty chunks (at most DIRTY_PER_FLUSH). Call this
## once per frame (or tick) to lazily catch up on pending tile changes
## without spiking a frame when many tiles change at once.
func flush_dirty() -> void:
	if _dirty_chunks.is_empty():
		return
	var keys: Array = _dirty_chunks.keys()
	var n: int = min(DIRTY_PER_FLUSH, keys.size())
	for i in range(n):
		var key: String = keys[i]
		var parts := key.split(",")
		rebuild_chunk(int(parts[0]), int(parts[1]))

func _mark_dirty(cx: int, cz: int) -> void:
	if cx < 0 or cz < 0 or cx >= chunk_cols or cz >= chunk_rows:
		return
	_dirty_chunks["%d,%d" % [cx, cz]] = true

func _ensure_material() -> void:
	if _material:
		return
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_material.roughness = 1.0
	_material.metallic_specular = 0.1
	# Skirts are only built on the taller side of a height boundary, and the
	# top faces use an explicit UP normal regardless of triangle winding, so
	# disable culling to avoid depending on exact vertex winding order.
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED

func _rebuild_chunk_mesh(cx: int, cz: int) -> void:
	var key := "%d,%d" % [cx, cz]
	var x0 := cx * CHUNK_TILES
	var z0 := cz * CHUNK_TILES

	if cx < 0 or cz < 0 or x0 >= world.width or z0 >= world.height:
		var stale: MeshInstance3D = _chunk_instances.get(key)
		if stale:
			stale.queue_free()
			_chunk_instances.erase(key)
		return

	var x1: int = min(x0 + CHUNK_TILES, world.width)
	var z1: int = min(z0 + CHUNK_TILES, world.height)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for z in range(z0, z1):
		for x in range(x0, x1):
			_add_tile(st, x, z)

	st.index()
	var mesh := st.commit()

	var inst: MeshInstance3D = _chunk_instances.get(key)
	if inst == null:
		inst = MeshInstance3D.new()
		inst.material_override = _material
		add_child(inst)
		_chunk_instances[key] = inst
	inst.mesh = mesh

func _tile_render_color(tile: Dictionary) -> Color:
	var color := tile_color(int(tile["type"]))

	# River tint
	if tile.get("river", false):
		color = color.lerp(Color(0.2, 0.5, 0.85), 0.4)

	# Cut trees appear darker
	if tile.get("tree_cut", false):
		color = color.darkened(0.3)

	return color

func _add_tile(st: SurfaceTool, x: int, z: int) -> void:
	var tile: Dictionary = world.tiles[z][x]
	var color := _tile_render_color(tile)

	var elev: float = float(tile["elevation"])
	var wx := x * TILE_SIZE
	var wz := z * TILE_SIZE
	var wy := elev * HEIGHT_SCALE  # slight height variation, stepped per tile

	# Quad vertices (two triangles), flat per-tile — intentionally not
	# smoothed with neighbours so the blocky tile look is preserved.
	var v0 := Vector3(wx,              wy, wz)
	var v1 := Vector3(wx + TILE_SIZE,  wy, wz)
	var v2 := Vector3(wx + TILE_SIZE,  wy, wz + TILE_SIZE)
	var v3 := Vector3(wx,              wy, wz + TILE_SIZE)

	_add_tri(st, v0, v1, v2, Vector3.UP, color)
	_add_tri(st, v0, v2, v3, Vector3.UP, color)

	# Vertical skirts on any edge where this tile is higher than its
	# neighbour, so mountains next to water (or any height step) don't show
	# a gap through the world at a low camera angle.
	_add_skirt_edge(st, x, z, wx, wz, wy, color, 1, 0)
	_add_skirt_edge(st, x, z, wx, wz, wy, color, -1, 0)
	_add_skirt_edge(st, x, z, wx, wz, wy, color, 0, 1)
	_add_skirt_edge(st, x, z, wx, wz, wy, color, 0, -1)

func _add_skirt_edge(st: SurfaceTool, x: int, z: int, wx: float, wz: float, wy_top: float, color: Color, dx: int, dz: int) -> void:
	var nx := x + dx
	var nz := z + dz
	var in_bounds := nx >= 0 and nx < world.width and nz >= 0 and nz < world.height

	var wy_bottom: float
	if in_bounds:
		var ntile: Dictionary = world.tiles[nz][nx]
		var n_wy: float = float(ntile["elevation"]) * HEIGHT_SCALE
		if n_wy >= wy_top:
			return  # neighbour is level or higher: no gap on this side
		wy_bottom = n_wy
	else:
		wy_bottom = wy_top - BORDER_SKIRT_DEPTH

	var p_a: Vector3
	var p_b: Vector3
	var normal: Vector3
	if dx == 1:
		p_a = Vector3(wx + TILE_SIZE, 0.0, wz)
		p_b = Vector3(wx + TILE_SIZE, 0.0, wz + TILE_SIZE)
		normal = Vector3(1, 0, 0)
	elif dx == -1:
		p_a = Vector3(wx, 0.0, wz)
		p_b = Vector3(wx, 0.0, wz + TILE_SIZE)
		normal = Vector3(-1, 0, 0)
	elif dz == 1:
		p_a = Vector3(wx, 0.0, wz + TILE_SIZE)
		p_b = Vector3(wx + TILE_SIZE, 0.0, wz + TILE_SIZE)
		normal = Vector3(0, 0, 1)
	else:
		p_a = Vector3(wx, 0.0, wz)
		p_b = Vector3(wx + TILE_SIZE, 0.0, wz)
		normal = Vector3(0, 0, -1)

	var top_a := Vector3(p_a.x, wy_top, p_a.z)
	var top_b := Vector3(p_b.x, wy_top, p_b.z)
	var bot_a := Vector3(p_a.x, wy_bottom, p_a.z)
	var bot_b := Vector3(p_b.x, wy_bottom, p_b.z)

	var wall_color := color.darkened(0.12)
	_add_tri(st, top_a, bot_a, bot_b, normal, wall_color)
	_add_tri(st, top_a, bot_b, top_b, normal, wall_color)

func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	st.set_normal(normal)
	st.set_color(color)
	st.add_vertex(a)
	st.set_normal(normal)
	st.set_color(color)
	st.add_vertex(b)
	st.set_normal(normal)
	st.set_color(color)
	st.add_vertex(c)
