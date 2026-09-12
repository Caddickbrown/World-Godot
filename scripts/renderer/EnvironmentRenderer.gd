class_name EnvironmentRenderer
extends Node3D

const TILE_SIZE := World.TILE_SIZE

# BrokenVector DAE trees — 3 type groups, 5-6 variants each.
# DAE files include their own vertex colours so no palette needed.
const TREE_PATHS: Array = [
	"res://assets/nature/trees/Tree Type1 01.dae",
	"res://assets/nature/trees/Tree Type1 02.dae",
	"res://assets/nature/trees/Tree Type1 03.dae",
	"res://assets/nature/trees/Tree Type2 01.dae",
	"res://assets/nature/trees/Tree Type2 02.dae",
	"res://assets/nature/trees/Tree Type3 01.dae",
	"res://assets/nature/trees/Tree Type3 02.dae",
]
const BUSH_PATH  := "res://assets/nature/synty/SM_Env_Bush_Cluster_01.fbx"
const BUSH2_PATH := "res://assets/nature/synty/SM_Env_Bush_01.fbx"
const ROCK_PATH  := "res://assets/nature/synty/SM_Env_Rock_01.fbx"
const ROCK2_PATH := "res://assets/nature/synty/SM_Env_Rock_02.fbx"

# BrokenVector trees are modelled at roughly 1 unit tall — scale is already right.
const TREE_SCALE  := 1.0
const BUSH_SCALE  := 0.45
const ROCK_SCALE  := 0.40

# Fraction of eligible tiles that actually get a prop
const FOREST_DENSITY   := 0.55
const WOODLAND_DENSITY := 0.30
const GRASS_DENSITY    := 0.12
const STONE_DENSITY    := 0.20

var _synty_mat: StandardMaterial3D

# path -> Array[{mesh: Mesh, xform: Transform3D}]  (one entry per MeshInstance3D
# found in that prop's source scene, transform relative to the scene root)
var _mesh_defs: Dictionary = {}
# path -> bool, whether the source scene loaded successfully
var _scene_valid: Dictionary = {}

# path -> Array[Transform3D]  (per-tile placement transform, collected in pass 1)
var _pending: Dictionary = {}
# "x,z" -> {path: String, idx: int}  (tree placements only, for remove_tree_at)
var _tree_lookup: Dictionary = {}
# path -> Array[MultiMesh]  (one MultiMesh per mesh part of that prop)
var _multimesh_by_path: Dictionary = {}

func setup(world: World) -> void:
	clear()
	_synty_mat = SyntyMaterial.make()
	_mesh_defs.clear()
	_scene_valid.clear()
	_cache_scenes()
	_populate(world)

func clear() -> void:
	for child in get_children():
		if child is MultiMeshInstance3D:
			child.queue_free()
	_pending.clear()
	_tree_lookup.clear()
	_multimesh_by_path.clear()

# ---------------------------------------------------------------------------
# Scene caching: load each prop scene once, extract its mesh part(s) and their
# local transforms relative to the scene root, then discard the scene.
# ---------------------------------------------------------------------------

func _cache_scenes() -> void:
	var all_paths: Array = []
	for p in TREE_PATHS: all_paths.append(str(p))
	all_paths.append_array([BUSH_PATH, BUSH2_PATH, ROCK_PATH, ROCK2_PATH])

	for path in all_paths:
		var p: String = str(path)
		_mesh_defs[p] = []
		_scene_valid[p] = false
		if not ResourceLoader.exists(p):
			continue
		var res := load(p)
		if not (res is PackedScene):
			continue
		_scene_valid[p] = true
		var packed := res as PackedScene
		var inst := packed.instantiate()
		if inst is Node3D:
			var is_dae_tree: bool = TREE_PATHS.has(p)
			var parts: Array = []
			_extract_mesh_defs(inst as Node3D, Transform3D.IDENTITY, true, is_dae_tree, parts)
			_mesh_defs[p] = parts
		inst.free()

# Walk a freshly-instantiated (unparented) scene, recording each MeshInstance3D's
# mesh together with its transform relative to the scene root. The root's own
# transform is excluded, since at placement time the root is replaced by the
# per-tile placement transform (mirrors the old node.position/rotation/scale
# assignment onto the root of an instantiated scene).
func _extract_mesh_defs(node: Node3D, accum: Transform3D, is_root: bool, is_dae_tree: bool, out_list: Array) -> void:
	var local_xform: Transform3D = accum if is_root else accum * node.transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			var mesh: Mesh = mi.mesh
			if not is_dae_tree:
				mesh = _bake_synty_material(mesh)
			out_list.append({"mesh": mesh, "xform": local_xform})
	for child in node.get_children():
		if child is Node3D:
			_extract_mesh_defs(child as Node3D, local_xform, false, is_dae_tree, out_list)

# Synty FBX props need the flat-colour palette applied to any surface that
# doesn't already have its own albedo texture. Bake this onto a duplicated
# mesh resource once, so every MultiMesh instance gets it for free.
func _bake_synty_material(mesh: Mesh) -> Mesh:
	var new_mesh: Mesh = mesh.duplicate()
	for s in range(new_mesh.get_surface_count()):
		var existing := new_mesh.surface_get_material(s)
		var needs_apply := true
		if existing is StandardMaterial3D:
			if (existing as StandardMaterial3D).albedo_texture != null:
				needs_apply = false
		if needs_apply:
			new_mesh.surface_set_material(s, _synty_mat)
	return new_mesh

# ---------------------------------------------------------------------------
# Pass 1: walk the world and collect per-tile placement transforms, keyed by
# prop path. No nodes are instantiated here.
# ---------------------------------------------------------------------------

func _populate(world: World) -> void:
	# Use a fixed RNG seed so the same world always places props the same way
	var rng := RandomNumberGenerator.new()
	rng.seed = 42 + world.seed_val

	for z in range(World.WORLD_HEIGHT):
		for x in range(World.WORLD_WIDTH):
			var tile: Dictionary = world.tiles[z][x]
			var tile_type: int = int(tile.get("type", -1))
			_maybe_place(tile_type, x, z, rng)

	_build_multimeshes()

func _maybe_place(tile_type: int, x: int, z: int, rng: RandomNumberGenerator) -> void:
	var roll: float = rng.randf()
	var path: String = ""
	var scale: float = 1.0

	var is_dae_tree := false
	match tile_type:
		World.TileType.FOREST:
			if roll < FOREST_DENSITY:
				var tidx: int = (x * 3 + z * 7) % TREE_PATHS.size()
				path = str(TREE_PATHS[tidx])
				scale = TREE_SCALE * (0.8 + rng.randf() * 0.4)
				is_dae_tree = true
		World.TileType.WOODLAND:
			if roll < WOODLAND_DENSITY:
				if rng.randf() < 0.5:
					var tidx: int = (x + z * 5) % TREE_PATHS.size()
					path = str(TREE_PATHS[tidx])
					scale = TREE_SCALE * 0.7
					is_dae_tree = true
				else:
					path = BUSH2_PATH
					scale = BUSH_SCALE * (0.8 + rng.randf() * 0.4)
		World.TileType.GRASS:
			if roll < GRASS_DENSITY:
				path = BUSH_PATH if rng.randf() < 0.6 else BUSH2_PATH
				scale = BUSH_SCALE * (0.7 + rng.randf() * 0.3)
		World.TileType.STONE, World.TileType.MOUNTAIN:
			if roll < STONE_DENSITY:
				path = ROCK_PATH if rng.randf() < 0.5 else ROCK2_PATH
				scale = ROCK_SCALE * (0.7 + rng.randf() * 0.6)
		_:
			return

	if path.is_empty(): return
	if not _scene_valid.get(path, false): return

	# NOTE: these rng calls must stay unconditional here (matching the old
	# code's behaviour of always consuming them once a valid scene is found,
	# even in the rare case the scene has no usable mesh) so that placement
	# for every other tile stays bit-for-bit deterministic.
	var ox: float = (rng.randf() - 0.5) * TILE_SIZE * 0.5
	var oz: float = (rng.randf() - 0.5) * TILE_SIZE * 0.5
	var rot_y: float = rng.randf() * TAU

	var parts: Array = _mesh_defs.get(path, [])
	if parts.is_empty(): return

	var pos := Vector3(
		(float(x) + 0.5) * TILE_SIZE + ox,
		0.0,
		(float(z) + 0.5) * TILE_SIZE + oz
	)
	var basis := Basis(Vector3.UP, rot_y).scaled(Vector3(scale, scale, scale))
	var xform := Transform3D(basis, pos)

	if not _pending.has(path):
		_pending[path] = []
	var arr: Array = _pending[path]
	var idx: int = arr.size()
	arr.append(xform)

	if is_dae_tree:
		_tree_lookup["%d,%d" % [x, z]] = {"path": path, "idx": idx}

# ---------------------------------------------------------------------------
# Pass 2: now that every placement's prop path is known, allocate one
# MultiMesh per mesh part per path and fill in the instance transforms.
# ---------------------------------------------------------------------------

func _build_multimeshes() -> void:
	for path in _pending.keys():
		var xforms: Array = _pending[path]
		if xforms.is_empty(): continue
		var parts: Array = _mesh_defs.get(path, [])
		if parts.is_empty(): continue

		var mm_list: Array = []
		for part_idx in range(parts.size()):
			var part: Dictionary = parts[part_idx]
			var mesh: Mesh = part["mesh"]
			var local_xform: Transform3D = part["xform"]

			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = xforms.size()
			for i in range(xforms.size()):
				var world_xform: Transform3D = xforms[i]
				mm.set_instance_transform(i, world_xform * local_xform)

			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.name = "%s_part%d" % [path.get_file(), part_idx]
			add_child(mmi)
			mm_list.append(mm)

		_multimesh_by_path[path] = mm_list

# ---------------------------------------------------------------------------
# Runtime updates
# ---------------------------------------------------------------------------

# Agents cut trees down; hide that instance by collapsing its transform to a
# zero scale (MultiMesh has no cheap way to delete a single instance).
func remove_tree_at(x: int, z: int) -> void:
	var key := "%d,%d" % [x, z]
	if not _tree_lookup.has(key): return
	var entry: Dictionary = _tree_lookup[key]
	var path: String = entry["path"]
	var idx: int = entry["idx"]
	var mm_list: Array = _multimesh_by_path.get(path, [])
	var degenerate := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for mm in mm_list:
		(mm as MultiMesh).set_instance_transform(idx, degenerate)
