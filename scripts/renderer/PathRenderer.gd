class_name PathRenderer
extends Node3D
## Worn paths: the footfall counts PathSystem keeps (World.trade_traffic),
## drawn as bare earth on the ground. A separate layer, not a slab: it is
## built on the Heightfield's own 1 m grid, with the terrain's own triangle
## split, a few centimetres up, and blends in by vertex alpha, so it lies on
## the ground like paint (docs/LESSONS.md: "never a slab on top"). Owns no
## terrain colour; LookStyle.TRAMPLED (graded for the look) is the earth.
##
## Rebuilt at most every REBUILD_SECONDS, and only when PathSystem's revision
## moved; the mesh covers only the cells near worn tiles.

const TILE_SIZE := World.TILE_SIZE
const WEAR_START := 4.0            # footfalls before a tile shows at all
const WEAR_FULL := 22.0            # ...and when it is a beaten path
const LIFT := 0.035                # metres above the ground
const REBUILD_SECONDS := 1.5       # real seconds between rebuilds at most
const SPREAD := 1.35               # metres a tile's wear reaches past its centre

var world: World
var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _revision := -1
var _cooldown := 0.0
## Tiles drawn at the last rebuild ("x,z" -> wear 0..1), for tests and the
## inspect card. The headless renderer keeps no mesh data (docs/LESSONS.md).
var shown: Dictionary = {}

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	restyle()

func restyle() -> void:
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.roughness = 1.0
	_material.render_priority = -1
	if _mesh:
		_mesh.material_override = _material
	_revision = -1

## Redraw if the wear has changed (cheap to call every frame).
func sync(paths: PathSystem) -> void:
	if paths == null or world == null:
		return
	_cooldown -= get_process_delta_time()
	if paths.revision == _revision or _cooldown > 0.0:
		return
	_revision = paths.revision
	_cooldown = REBUILD_SECONDS
	rebuild()

func rebuild() -> void:
	shown.clear()
	if world == null:
		return
	var field: Heightfield = world.heightfield
	for key in world.trade_traffic:
		var p: PackedStringArray = str(key).split(",")
		var w := clampf((float(world.trade_traffic[key]) - WEAR_START) / (WEAR_FULL - WEAR_START), 0.0, 1.0)
		if w > 0.0:
			shown[Vector2i(int(p[0]), int(p[1]))] = w
	if shown.is_empty() or field == null:
		_mesh.mesh = null
		return
	# Splat each worn tile's wear onto the 1 m vertices round it.
	var step := Heightfield.STEP
	var weight: Dictionary = {}   # Vector2i vertex -> alpha
	var reach := int(ceil((TILE_SIZE * 0.5 + SPREAD) / step))
	for t in shown:
		var cx := (t.x + 0.5) * TILE_SIZE
		var cz := (t.y + 0.5) * TILE_SIZE
		var w: float = shown[t]
		var ix0 := int(round(cx / step))
		var iz0 := int(round(cz / step))
		for dz in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				var v := Vector2i(ix0 + dx, iz0 + dz)
				if v.x < 0 or v.y < 0 or v.x >= field.n or v.y >= field.n:
					continue
				var d := Vector2(v.x * step - cx, v.y * step - cz).length()
				var a := w * (1.0 - smoothstep(TILE_SIZE * 0.35, TILE_SIZE * 0.5 + SPREAD, d))
				if a > float(weight.get(v, 0.0)):
					weight[v] = a
	# Cells with any weighted corner become two triangles, split the way the
	# terrain splits its own (TerrainRenderer._build_chunk), so they lie flat on it.
	var earth := LookStyle.g(LookStyle.TRAMPLED.darkened(0.08))
	var dust := LookStyle.g(LookStyle.TRAMPLED.lightened(0.12))
	var cells: Dictionary = {}
	for v in weight:
		for o in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
			var c: Vector2i = v + o
			if c.x >= 0 and c.y >= 0 and c.x < field.n - 1 and c.y < field.n - 1:
				cells[c] = true
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx := {}
	var count := 0
	for c in cells:
		var corners := [c, c + Vector2i(1, 0), c + Vector2i(0, 1), c + Vector2i(1, 1)]
		var ids: Array = []
		for v in corners:
			if not idx.has(v):
				var x: float = v.x * step
				var z: float = v.y * step
				var a := float(weight.get(v, 0.0))
				# A little grain so a path frays at its edges, from position only.
				var grain := 0.5 + 0.5 * sin(x * 2.3 + z * 1.7) * cos(z * 2.9 - x * 0.7)
				var col := earth.lerp(dust, grain * 0.6)
				col.a = clampf(a * (0.78 + 0.22 * grain), 0.0, 0.92)
				st.set_color(col)
				st.set_normal(field.normal_at(x, z))
				st.add_vertex(Vector3(x, field.height_at(x, z) + LIFT, z))
				idx[v] = count
				count += 1
			ids.append(idx[v])
		# corners: 0 = (ix, iz), 1 = (ix+1, iz), 2 = (ix, iz+1), 3 = (ix+1, iz+1)
		st.add_index(ids[0]); st.add_index(ids[1]); st.add_index(ids[2])
		st.add_index(ids[1]); st.add_index(ids[3]); st.add_index(ids[2])
	_mesh.mesh = st.commit()
	_mesh.material_override = _material

## Wear shown on a tile (0 = none), for the inspect card.
func wear_at(x: int, z: int) -> float:
	return float(shown.get(Vector2i(x, z), 0.0))
