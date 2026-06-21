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
var _scenes: Dictionary = {}   # path → PackedScene or null

func setup(world: World) -> void:
	_synty_mat = SyntyMaterial.make()
	_cache_scenes()
	_populate(world)

func _cache_scenes() -> void:
	var all_paths: Array = []
	for p in TREE_PATHS: all_paths.append(str(p))
	all_paths.append_array([BUSH_PATH, BUSH2_PATH, ROCK_PATH, ROCK2_PATH])

	for path in all_paths:
		var p: String = str(path)
		if ResourceLoader.exists(p):
			var res := load(p)
			_scenes[p] = res if res is PackedScene else null
		else:
			_scenes[p] = null

func _populate(world: World) -> void:
	# Use a fixed RNG seed so the same world always places props the same way
	var rng := RandomNumberGenerator.new()
	rng.seed = 42 + world.seed

	for z in range(World.WORLD_HEIGHT):
		for x in range(World.WORLD_WIDTH):
			var tile: Dictionary = world.tiles[z][x]
			var tile_type: int = int(tile.get("type", -1))
			_maybe_place(tile_type, x, z, rng)

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
	var packed: PackedScene = _scenes.get(path) as PackedScene
	if packed == null: return

	var inst := packed.instantiate()
	if not (inst is Node3D):
		inst.queue_free()
		return
	var node := inst as Node3D

	var ox: float = (rng.randf() - 0.5) * TILE_SIZE * 0.5
	var oz: float = (rng.randf() - 0.5) * TILE_SIZE * 0.5
	node.position = Vector3(
		(float(x) + 0.5) * TILE_SIZE + ox,
		0.0,
		(float(z) + 0.5) * TILE_SIZE + oz
	)
	node.rotation.y = rng.randf() * TAU
	node.scale = Vector3(scale, scale, scale)

	# BrokenVector DAE trees have vertex colours baked in — no palette needed.
	# Synty bushes/rocks need the palette applied.
	if not is_dae_tree:
		SyntyMaterial.apply_to(node, _synty_mat)

	add_child(node)
