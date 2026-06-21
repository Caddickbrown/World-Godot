class_name SettlementRenderer
extends Node3D

const TILE_SIZE    := World.TILE_SIZE
const HOUSE_PATH   := "res://assets/buildings/Prop_House.fbx"
const TOPDECO_PATH := "res://assets/buildings/Prop_House_TopDeco.fbx"
const FENCE_PATH   := "res://assets/buildings/Prop_Fence.fbx"

# House scale — Prop_House.fbx is modelled at ~1 unit = 1 cm in Unity
# so import scale ~0.01 makes it ~1 m.  Adjust here if it looks wrong.
const HOUSE_SCALE := 0.8

var _house_scene: PackedScene    # null until imported
var _topdeco_scene: PackedScene
var _fence_scene: PackedScene
var _house_tex: Texture2D

# settlement_key (e.g. "12,7") → Node3D root
var _placed: Dictionary = {}

func _ready() -> void:
	_load_assets()

func _load_assets() -> void:
	var tex := load("res://assets/buildings/Color Texture.png")
	if tex is Texture2D:
		_house_tex = tex as Texture2D

	if ResourceLoader.exists(HOUSE_PATH):
		var r := load(HOUSE_PATH)
		if r is PackedScene: _house_scene = r as PackedScene

	if ResourceLoader.exists(TOPDECO_PATH):
		var r := load(TOPDECO_PATH)
		if r is PackedScene: _topdeco_scene = r as PackedScene

	if ResourceLoader.exists(FENCE_PATH):
		var r := load(FENCE_PATH)
		if r is PackedScene: _fence_scene = r as PackedScene

# Called from Main each frame with the current set of active settlement tiles.
# tiles_xz is an Array of [x, z] int pairs.
func sync(settlement_tiles: Array) -> void:
	var active_keys: Dictionary = {}

	for pair in settlement_tiles:
		var tx: int = int(pair[0])
		var tz: int = int(pair[1])
		var key: String = "%d,%d" % [tx, tz]
		active_keys[key] = true
		if not _placed.has(key):
			_place_house(tx, tz, key)

	# Remove houses whose settlement has dissolved
	for key in _placed.keys():
		if not active_keys.has(key):
			var node: Node3D = _placed[key] as Node3D
			if node: node.queue_free()
			_placed.erase(key)

func _place_house(tx: int, tz: int, key: String) -> void:
	var root := Node3D.new()
	root.position = Vector3(
		(float(tx) + 0.5) * TILE_SIZE,
		0.0,
		(float(tz) + 0.5) * TILE_SIZE
	)
	root.scale = Vector3(HOUSE_SCALE, HOUSE_SCALE, HOUSE_SCALE)
	add_child(root)

	if _house_scene:
		var inst := _house_scene.instantiate()
		if inst is Node3D:
			_apply_tex(inst as Node3D)
			root.add_child(inst)
	else:
		_add_fallback(root)

	if _topdeco_scene:
		var deco := _topdeco_scene.instantiate()
		if deco is Node3D:
			_apply_tex(deco as Node3D)
			root.add_child(deco)

	_placed[key] = root

func _apply_tex(node: Node3D) -> void:
	if not _house_tex: return
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for s in range(mi.mesh.get_surface_count()):
				var mat := mi.get_active_material(s)
				if mat is StandardMaterial3D:
					var sm := mat as StandardMaterial3D
					if sm.albedo_texture == null:
						var nm := sm.duplicate() as StandardMaterial3D
						nm.albedo_texture = _house_tex
						mi.set_surface_override_material(s, nm)
	for child in node.get_children():
		if child is Node3D:
			_apply_tex(child as Node3D)

func _add_fallback(root: Node3D) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.2, 1.0, 1.2)
	mi.mesh = box
	mi.position.y = 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.75, 0.60)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	root.add_child(mi)

func clear() -> void:
	for key in _placed:
		var node: Node3D = _placed[key] as Node3D
		if node: node.queue_free()
	_placed.clear()
