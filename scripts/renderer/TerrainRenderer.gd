class_name TerrainRenderer
extends Node3D

const TILE_SIZE := World.TILE_SIZE

var world: World
var _mesh_instance: MeshInstance3D

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
	return Color(0.5, 0.5, 0.5)

func setup(p_world: World) -> void:
	world = p_world
	_build_mesh()

func _build_mesh() -> void:
	if _mesh_instance:
		_mesh_instance.queue_free()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for z in range(World.WORLD_HEIGHT):
		for x in range(World.WORLD_WIDTH):
			var tile: Dictionary = world.tiles[z][x]
			var color := tile_color(tile["type"])

			# River tint
			if tile.get("river", false):
				color = color.lerp(Color(0.2, 0.5, 0.85), 0.4)

			var elev: float = tile["elevation"]
			# Cut trees appear darker
			if tile.get("tree_cut", false):
				color = color.darkened(0.3)

			var wx := x * TILE_SIZE
			var wz := z * TILE_SIZE
			var wy := elev * 0.3  # slight height variation

			# Quad vertices (two triangles)
			var v0 := Vector3(wx,           wy, wz)
			var v1 := Vector3(wx + TILE_SIZE, wy, wz)
			var v2 := Vector3(wx + TILE_SIZE, wy, wz + TILE_SIZE)
			var v3 := Vector3(wx,           wy, wz + TILE_SIZE)
			var normal := Vector3.UP

			st.set_color(color)
			st.set_normal(normal)
			st.add_vertex(v0)
			st.add_vertex(v1)
			st.add_vertex(v2)

			st.set_color(color)
			st.set_normal(normal)
			st.add_vertex(v0)
			st.add_vertex(v2)
			st.add_vertex(v3)

	st.index()
	var mesh := st.commit()

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh_instance.material_override = mat

	add_child(_mesh_instance)

func rebuild() -> void:
	_build_mesh()
