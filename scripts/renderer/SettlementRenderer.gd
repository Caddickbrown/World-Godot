class_name SettlementRenderer
extends Node3D

const TILE_SIZE := World.TILE_SIZE

# Buildings unlocked progressively as concepts are discovered.
# Era 0 (no concepts): nothing
# Era 1 (1-4): shelters
# Era 2 (5-9): huts
# Era 3 (10-15): houses
# Era 4 (16-21): houses + specialist buildings
# Era 5 (22+): full town with church, blacksmith, tavern
const BUILDING_TIERS: Array = [
	[],  # era 0 — wilderness
	["res://assets/buildings/synty/SM_Bld_Preset_Shelter_01_Optimized.fbx",
	 "res://assets/buildings/synty/SM_Bld_Preset_Shelter_02_Optimized.fbx"],
	["res://assets/buildings/synty/SM_Bld_Preset_Hut_01_Optimized.fbx",
	 "res://assets/buildings/synty/SM_Bld_Preset_Hut_02_Optimized.fbx"],
	["res://assets/buildings/synty/SM_Bld_Preset_House_01_A_Optimized.fbx",
	 "res://assets/buildings/synty/SM_Bld_Preset_House_02_A_Optimized.fbx",
	 "res://assets/buildings/synty/SM_Bld_Preset_House_03_Optimized.fbx"],
	["res://assets/buildings/synty/SM_Bld_Preset_House_01_A_Optimized.fbx",
	 "res://assets/buildings/synty/SM_Bld_Preset_House_02_A_Optimized.fbx",
	 "res://assets/buildings/synty/SM_Bld_Preset_Blacksmith_01_Optimized.fbx",
	 "res://assets/buildings/synty/SM_Bld_Preset_Stables_01_Optimized.fbx"],
	["res://assets/buildings/synty/SM_Bld_Preset_House_01_A_Optimized.fbx",
	 "res://assets/buildings/synty/SM_Bld_Preset_House_03_Optimized.fbx",
	 "res://assets/buildings/synty/SM_Bld_Preset_Tavern_01_Optimized.fbx",
	 "res://assets/buildings/synty/SM_Bld_Preset_Church_01_A_Optimized.fbx",
	 "res://assets/buildings/synty/SM_Bld_Preset_Blacksmith_01_Optimized.fbx"],
]

# Campfire prop shown at every settlement regardless of era
const FIREPIT_PATH := "res://assets/props/SM_Prop_Camp_Firepit_01.fbx"

# Synty models are in Unity units; 0.9 gives ~1 tile footprint for a house
const BUILDING_SCALE := 0.9

var world: World  # for ground height; set by Main
var _mat: StandardMaterial3D
var _scenes: Dictionary = {}         # path → PackedScene or null
var _placed: Dictionary = {}         # settlement_key → { node, era, path }
var _current_era: int = 0

func _ready() -> void:
	_mat = SyntyMaterial.make()
	_cache_scenes()

func _cache_scenes() -> void:
	var all_paths: Array = []
	for tier in BUILDING_TIERS:
		for p in tier:
			if not all_paths.has(p):
				all_paths.append(p)
	all_paths.append(FIREPIT_PATH)

	for path in all_paths:
		var p: String = str(path)
		if ResourceLoader.exists(p):
			var res := load(p)
			_scenes[p] = res if res is PackedScene else null
		else:
			_scenes[p] = null

# Called from Main each frame.
# settlement_tiles: Array of [x, z] pairs.
# era: int 0-5 from _get_era_index().
func sync(settlement_tiles: Array, era: int) -> void:
	_current_era = era
	var active_keys: Dictionary = {}

	for pair in settlement_tiles:
		var tx: int = int(pair[0])
		var tz: int = int(pair[1])
		var key: String = "%d,%d" % [tx, tz]
		active_keys[key] = true

		var path: String = _pick_building(tx, tz, era)
		if not _placed.has(key):
			_place(tx, tz, key, path, era)
		else:
			# Upgrade if era increased or path differs
			var entry: Dictionary = _placed[key] as Dictionary
			if int(entry.get("era", -1)) != era:
				var old_node: Node3D = entry.get("node") as Node3D
				if old_node: old_node.queue_free()
				_placed.erase(key)
				_place(tx, tz, key, path, era)

	# Remove dissolved settlements
	for key in _placed.keys():
		if not active_keys.has(key):
			var entry: Dictionary = _placed[key] as Dictionary
			var node: Node3D = entry.get("node") as Node3D
			if node: node.queue_free()
			_placed.erase(key)

func _pick_building(tx: int, tz: int, era: int) -> String:
	if era == 0: return ""
	var tier: Array = BUILDING_TIERS[clampi(era, 0, BUILDING_TIERS.size() - 1)]
	if tier.is_empty(): return ""
	var idx: int = (tx * 7 + tz * 13) % tier.size()
	return str(tier[idx])

func _place(tx: int, tz: int, key: String, path: String, era: int) -> void:
	if era == 0: return

	var root := Node3D.new()
	root.position = Vector3(
		(float(tx) + 0.5) * TILE_SIZE,
		world.surface_y(float(tx) + 0.5, float(tz) + 0.5) if world else 0.0,
		(float(tz) + 0.5) * TILE_SIZE
	)
	# Vary rotation so not every building faces the same way
	root.rotation.y = float((tx + tz) % 4) * (PI * 0.5)
	add_child(root)

	# Building mesh
	var packed: PackedScene = _scenes.get(path) as PackedScene
	if packed:
		var inst := packed.instantiate()
		if inst is Node3D:
			var building := inst as Node3D
			building.scale = Vector3(BUILDING_SCALE, BUILDING_SCALE, BUILDING_SCALE)
			SyntyMaterial.apply_to(building, _mat)
			root.add_child(building)
	else:
		_add_fallback(root)

	# Firepit prop at every settlement (era 1+)
	var fp: PackedScene = _scenes.get(FIREPIT_PATH) as PackedScene
	if fp:
		var fire_inst := fp.instantiate()
		if fire_inst is Node3D:
			var fire := fire_inst as Node3D
			fire.position = Vector3(0.3, 0.0, 0.3)
			fire.scale = Vector3(0.8, 0.8, 0.8)
			SyntyMaterial.apply_to(fire, _mat)
			root.add_child(fire)

	_placed[key] = {"node": root, "era": era, "path": path}

func _add_fallback(root: Node3D) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.2, 1.0, 1.2)
	mi.mesh = box
	mi.position.y = 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.68, 0.52)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	root.add_child(mi)

func clear() -> void:
	for key in _placed:
		var entry: Dictionary = _placed[key] as Dictionary
		var node: Node3D = entry.get("node") as Node3D
		if node: node.queue_free()
	_placed.clear()
