class_name AnimalRenderer
extends Node3D

const TILE_SIZE     := World.TILE_SIZE
const EAGLE_HEIGHT  := 3.5  # Y above ground for soaring eagles

# FBX path for each AnimalType int value
const MESH_PATHS: Dictionary = {
	0: "res://assets/animals/Deer/SKM_Deer_Animations.fbx",
	1: "res://assets/animals/Wolf/SKM_Wolf_Animations.fbx",
	2: "res://assets/animals/Sheep/SKM_Sheep_Animations.fbx",
	3: "res://assets/animals/Deer/SKM_Deer_Animations.fbx",  # the horse FBX has no mesh: a deer's body, horse-coloured
	4: "res://assets/animals/Cow/SKM_Cow_Animations.fbx",
	5: "res://assets/animals/Rabbit/SKM_Rabbit_Rig.fbx",
	6: "res://assets/animals/Eagle/SKM_Eagle_Animations.fbx",
	7: "res://assets/animals/Fox/SKM_Fox.fbx",
	8: "res://assets/animals/Pig/SKM_Pig_Animations.fbx",
	9: "res://assets/animals/Bear/SKM_Bear_Animations.fbx",
}

# Standing height (metres) each species is scaled to. The FBX files come in at
# wildly different units (a cow imported 4 mm tall, a fox 3 mm), so the scale
# is measured from each model once, not guessed. People are 1.7 m.
const TARGET_HEIGHT: Dictionary = {
	0: 1.5,   # DEER
	1: 0.85,  # WOLF
	2: 0.9,   # SHEEP
	3: 1.7,   # HORSE
	4: 1.5,   # COW
	5: 0.45,  # RABBIT (a touch big, so you can see it)
	6: 0.6,   # EAGLE
	7: 0.6,   # FOX
	8: 0.8,   # PIG
	9: 1.4,   # BEAR
}
var _type_scale: Dictionary = {}   # AnimalType int -> uniform scale for its model

# Species colours: for models without a texture, and the stand-in figure
const FALLBACK_COLORS: Dictionary = {
	0: Color(0.85, 0.70, 0.45),  # DEER  - tan
	1: Color(0.55, 0.45, 0.35),  # WOLF  - grey-brown
	2: Color(0.92, 0.90, 0.85),  # SHEEP - white
	3: Color(0.65, 0.50, 0.35),  # HORSE - chestnut
	4: Color(0.80, 0.75, 0.65),  # COW   - cream
	5: Color(0.82, 0.68, 0.52),  # RABBIT- beige
	6: Color(0.45, 0.30, 0.15),  # EAGLE - dark brown
	7: Color(0.88, 0.55, 0.18),  # FOX   - orange
	8: Color(0.92, 0.72, 0.65),  # PIG   - pink
	9: Color(0.38, 0.32, 0.28),  # BEAR  - dark brown
}

# Candidate animation names tried in order; first match wins
const ANIM_IDLE:  Array = ["Idle_A", "Idle", "idle"]
const ANIM_WALK:  Array = ["Walk_A", "Walk_B", "Walk", "walk"]
const ANIM_RUN:   Array = ["Run_A",  "Run_B",  "Run",  "run",  "Walk_B"]
const ANIM_EAT:   Array = ["Eat_A",  "Eat",    "eat",  "Idle_A", "Idle"]
const ANIM_FLEE:  Array = ["Run_A",  "Run_B",  "Run",  "run"]
const ANIM_HUNT:  Array = ["Run_A",  "Run_B",  "Run",  "run"]
const ANIM_SOAR:  Array = ["Fly_A",  "Fly",    "fly",  "Walk_A", "Walk", "Idle_A"]
const ANIM_DEAD:  Array = ["Death_A","Death",  "death","Idle_A"]

var _sim: AnimalSim
var _scenes: Dictionary = {}     # AnimalType int → PackedScene (null if not imported yet)

# Per-animal visual state: anim_id → { node, anim, prev_state }
var _instances: Dictionary = {}

var world: World  # for ground height; set by Main

func setup(sim: AnimalSim) -> void:
	_sim = sim
	_cache_scenes()
	for a in sim.animals:
		var animal: AnimalSim.Animal = a as AnimalSim.Animal
		if animal: _spawn(animal)

func _cache_scenes() -> void:
	for type_key in MESH_PATHS:
		var path: String = str(MESH_PATHS[type_key])
		if ResourceLoader.exists(path):
			var res := load(path)
			if res is PackedScene:
				_scenes[type_key] = res as PackedScene
			else:
				_scenes[type_key] = null
		else:
			_scenes[type_key] = null

func update() -> void:
	for a in _sim.animals:
		var animal: AnimalSim.Animal = a as AnimalSim.Animal
		if animal == null: continue
		if not _instances.has(animal.anim_id):
			_spawn(animal)
		_update_instance(animal)

# ── Per-instance update ──────────────────────────────────────────────────────

func _update_instance(animal: AnimalSim.Animal) -> void:
	var entry: Dictionary = _instances.get(animal.anim_id, {}) as Dictionary
	var node: Node3D = entry.get("node") as Node3D
	if node == null: return

	node.visible = animal.state != AnimalSim.AnimalState.DEAD

	var tx: float = animal.pos.x * TILE_SIZE
	var tz: float = animal.pos.y * TILE_SIZE
	var ground: float = world.surface_y(animal.pos.x, animal.pos.y) if world else 0.0
	var ty: float = EAGLE_HEIGHT if animal.animal_type == AnimalSim.AnimalType.EAGLE else ground + 0.05
	node.position = Vector3(tx, ty, tz)
	node.rotation.y = animal.facing

	# Gentle bank for flying eagles
	if animal.animal_type == AnimalSim.AnimalType.EAGLE:
		node.rotation.z = sin(Time.get_ticks_msec() * 0.0008) * 0.12

	# Trigger animation change only on state transition
	var prev_state: int = int(entry.get("prev_state", -1))
	if animal.state != prev_state:
		entry["prev_state"] = animal.state
		var player: AnimationPlayer = entry.get("anim") as AnimationPlayer
		if player:
			_play_for_state(player, animal.state, animal.animal_type)

# ── Spawning ─────────────────────────────────────────────────────────────────

func _spawn(animal: AnimalSim.Animal) -> void:
	var type_int: int = animal.animal_type
	var packed: PackedScene = _scenes.get(type_int) as PackedScene
	var root: Node3D
	var anim_player: AnimationPlayer = null

	if packed:
		var inst := packed.instantiate()
		if inst is Node3D and _model_height(inst as Node3D) > 0.0:
			root = inst as Node3D
			anim_player = _find_anim_player(inst)
			_ensure_texture(inst, type_int)
		else:
			inst.queue_free()   # e.g. the horse imports with no mesh at all
			root = _make_fallback(type_int)
	else:
		root = _make_fallback(type_int)

	if not _type_scale.has(type_int):
		var h := _model_height(root)
		_type_scale[type_int] = float(TARGET_HEIGHT.get(type_int, 1.0)) / h if h > 0.0 else 1.0
	var s: float = _type_scale[type_int]
	root.scale = Vector3(s, s, s)
	add_child(root)

	var entry := {
		"node":       root,
		"anim":       anim_player,
		"prev_state": -1,
		"type":       type_int,
	}
	_instances[animal.anim_id] = entry

	_update_instance(animal)   # stand where they are now, not at the map origin

# ── Animation ────────────────────────────────────────────────────────────────

func _play_for_state(player: AnimationPlayer, state: int, animal_type: int) -> void:
	var candidates: Array
	match state:
		AnimalSim.AnimalState.IDLE: candidates = ANIM_IDLE
		AnimalSim.AnimalState.WALK: candidates = ANIM_WALK
		AnimalSim.AnimalState.RUN:  candidates = ANIM_RUN
		AnimalSim.AnimalState.EAT:  candidates = ANIM_EAT
		AnimalSim.AnimalState.FLEE: candidates = ANIM_FLEE
		AnimalSim.AnimalState.HUNT: candidates = ANIM_HUNT
		AnimalSim.AnimalState.SOAR: candidates = ANIM_SOAR
		AnimalSim.AnimalState.DEAD: candidates = ANIM_DEAD
		_: candidates = ANIM_IDLE

	var prefix: String = _type_prefix(animal_type)

	for cand in candidates:
		var c: String = str(cand)
		# Try "Wolf_Walk_A", then "Walk_A"
		if player.has_animation(prefix + "_" + c):
			player.play(prefix + "_" + c)
			return
		if player.has_animation(c):
			player.play(c)
			return

	# Last resort: whatever is first in the library
	var all := player.get_animation_list()
	if all.size() > 0:
		player.play(str(all[0]))

func _type_prefix(t: int) -> String:
	match t:
		AnimalSim.AnimalType.DEER:   return "Deer"
		AnimalSim.AnimalType.WOLF:   return "Wolf"
		AnimalSim.AnimalType.SHEEP:  return "Sheep"
		AnimalSim.AnimalType.HORSE:  return "Deer"   # wears the deer model
		AnimalSim.AnimalType.COW:    return "Cow"
		AnimalSim.AnimalType.RABBIT: return "Rabbit"
		AnimalSim.AnimalType.EAGLE:  return "Eagle"
		AnimalSim.AnimalType.FOX:    return "Fox"
		AnimalSim.AnimalType.PIG:    return "Pig"
		AnimalSim.AnimalType.BEAR:   return "Bear"
	return "Animal"

# ── Helpers ──────────────────────────────────────────────────────────────────

func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var result: AnimationPlayer = _find_anim_player(child)
		if result:
			return result
	return null

## Species drawn in a flat coat even if their model has a texture.
const FLAT_COAT := [3]   # HORSE (borrowing the deer's body)

## Some files hold several bodies on top of each other; show just one.
const SHOW_ONLY: Dictionary = {
	4: ["cow-cattle-horns"],   # COW: also cow-cattle, Cow_NoHorns, Horns_Seperated
	9: ["BearGrizzly"],        # BEAR: also BearWild
}

## The FBX materials come in glossy and some lack their texture. Each is
## swapped for a matte copy (the shared atlas where the texture is missing),
## graded by LookStyle, so animals sit in the same light as people and land.
var _matte: Dictionary = {}   # [original material, type] -> matte copy

func _ensure_texture(node: Node, animal_type: int = -1) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if SHOW_ONLY.has(animal_type) and not (str(mi.name) in SHOW_ONLY[animal_type]):
			mi.visible = false
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var src := mi.mesh.surface_get_material(i)
				mi.set_surface_override_material(i, _matte_of(src, animal_type))
	for child in node.get_children():
		_ensure_texture(child, animal_type)

## A model that shipped without its texture (sheep, wolf, rabbit) gets a flat
## species colour: the shared atlas doesn't match their UVs (it came out
## rainbow-striped).
func _matte_of(src: Material, animal_type: int) -> StandardMaterial3D:
	var key := [src, animal_type]
	if _matte.has(key):
		return _matte[key]
	var m := StandardMaterial3D.new()
	var tex: Texture2D = (src as BaseMaterial3D).albedo_texture if src is BaseMaterial3D else null
	if tex and not (animal_type in FLAT_COAT):
		m.albedo_texture = tex
		m.albedo_color = LookStyle.g(Color(1, 1, 1))
	else:
		m.albedo_color = LookStyle.g(Color(FALLBACK_COLORS.get(animal_type, Color(0.7, 0.7, 0.7))))
	m.roughness = 0.95
	m.metallic_specular = 0.2
	_matte[key] = m
	return m

## The look changed (T): rebuild the shared material and re-dress everyone.
func restyle() -> void:
	_matte.clear()
	for id in _instances:
		var e: Dictionary = _instances[id]
		var n: Node = e.get("node")
		if n: _ensure_texture(n, int(e.get("type", -1)))

## Height of a model as it renders, in its own space (before we scale it).
## Skinned meshes are measured through their skin's bind pose: the FBX unit
## scale lives there, so the raw mesh box can be 100x too small.
static func _model_height(root: Node3D) -> float:
	var box := AABB()
	var any := false
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.visible:
			continue
		var b := _local_xf(root, m) * m.get_aabb()
		var sk := m.get_node_or_null(m.skeleton) as Skeleton3D
		if sk and m.skin and m.skin.get_bind_count() > 0:
			var bi := m.skin.get_bind_bone(0)
			if bi < 0:
				bi = sk.find_bone(m.skin.get_bind_name(0))
			if bi >= 0:
				b = _local_xf(root, sk) * (sk.get_bone_global_rest(bi) * m.skin.get_bind_pose(0)) * m.get_aabb()
		box = b if not any else box.merge(b)
		any = true
	if not any and root is MeshInstance3D and (root as MeshInstance3D).mesh:
		return (root as MeshInstance3D).get_aabb().size.y
	return box.size.y if any else 0.0

## n's transform relative to root (works before either is in the tree).
static func _local_xf(root: Node, n: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t

## A plain four-legged figure (1 m tall before scaling) for a model that
## didn't import. Faces +Z like the FBX ones.
func _make_fallback(animal_type: int) -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = LookStyle.g(Color(FALLBACK_COLORS.get(animal_type, Color(0.7, 0.7, 0.7))))
	mat.roughness = 0.95
	var parts := [
		[Vector3(0.36, 0.34, 0.95), Vector3(0, 0.66, 0)],          # body
		[Vector3(0.16, 0.36, 0.18), Vector3(0, 0.86, 0.48)],       # neck
		[Vector3(0.18, 0.18, 0.34), Vector3(0, 0.98, 0.62)],       # head
	]
	for lx in [-0.12, 0.12]:
		for lz in [-0.36, 0.36]:
			parts.append([Vector3(0.09, 0.52, 0.09), Vector3(lx, 0.26, lz)])
	for p in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = p[0]
		mi.mesh = bm
		mi.position = p[1]
		mi.material_override = mat
		root.add_child(mi)
	return root

func clear() -> void:
	for id in _instances:
		var entry: Dictionary = _instances[id] as Dictionary
		var node: Node3D = entry.get("node") as Node3D
		if node:
			node.queue_free()
	_instances.clear()
