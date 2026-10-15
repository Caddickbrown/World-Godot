class_name DisasterView
extends Node3D
## A flood's water: a sheet over every flooded tile (DisasterSystem marks them),
## at the flood's water level, translucent so the drowned ground shows through.
## Rebuilt only when the set of flooded tiles changes.

const SHEET_ABOVE := 0.06   # metres over the higher of ground and water level

var _mm: MultiMeshInstance3D
var _mat: StandardMaterial3D
var _count := -1
var shown := 0              # tiles under the sheet (tests read it)

func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.roughness = 0.4          # glossier blew out into a sun glare under the bloom
	_mat.metallic_specular = 0.3
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	apply_style()
	_mm = MultiMeshInstance3D.new()
	_mm.material_override = _mat
	_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mm)

func apply_style() -> void:
	if _mat:
		var c := LookStyle.g(Color(0.32, 0.55, 0.62))
		_mat.albedo_color = Color(c, 0.62)

## Redraw if the flooded tiles changed. Cheap when nothing has.
func update(ds: DisasterSystem, world: World) -> void:
	if ds == null or world == null or _mm == null:
		return
	var n := ds.flooded_count if ds.current == DisasterSystem.DisasterType.FLOOD else 0
	if n == _count:
		return
	_count = n
	var tiles: Array = ds.flooded_tiles(world) if n > 0 else []
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := PlaneMesh.new()
	quad.size = Vector2(World.TILE_SIZE, World.TILE_SIZE)   # exact: overlapping see-through quads drew a grid
	mm.mesh = quad
	mm.instance_count = tiles.size()
	for i in tiles.size():
		var k: Vector2i = tiles[i]
		var tx := k.x + 0.5
		var tz := k.y + 0.5
		var y := maxf(world.surface_y(tx, tz), ds.water_level) + SHEET_ABOVE
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(tx * World.TILE_SIZE, y, tz * World.TILE_SIZE)))
	_mm.multimesh = mm
	shown = tiles.size()
