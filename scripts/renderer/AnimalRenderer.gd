class_name AnimalRenderer
extends Node3D

const TILE_SIZE     := World.TILE_SIZE
const EAGLE_HEIGHT  := 3.5  # Y above ground for soaring eagles

# FBX path for each AnimalType int value
const MESH_PATHS: Dictionary = {
	0: "res://assets/animals/Deer/SKM_Deer_Animations.fbx",
	1: "res://assets/animals/Wolf/SKM_Wolf_Animations.fbx",
	2: "res://assets/animals/Sheep/SKM_Sheep_Animations.fbx",
	3: "res://assets/animals/Horse/SKM_Horse_Animations.fbx",
	4: "res://assets/animals/Cow/SKM_Cow_Animations.fbx",
	5: "res://assets/animals/Rabbit/SKM_Rabbit_Rig.fbx",
	6: "res://assets/animals/Eagle/SKM_Eagle_Animations.fbx",
	7: "res://assets/animals/Fox/SKM_Fox.fbx",
	8: "res://assets/animals/Pig/SKM_Pig_Animations.fbx",
	9: "res://assets/animals/Bear/SKM_Bear_Animations.fbx",
}

# Uniform scale applied to each instantiated FBX scene
const MESH_SCALES: Dictionary = {
	0: 0.25,  # DEER
	1: 0.28,  # WOLF
	2: 0.22,  # SHEEP
	3: 0.30,  # HORSE
	4: 0.28,  # COW
	5: 0.18,  # RABBIT
	6: 0.22,  # EAGLE
	7: 0.20,  # FOX
	8: 0.22,  # PIG
	9: 0.32,  # BEAR
}

# Fallback box colours when FBX not yet imported
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
var _atlas_tex: Texture2D        # shared atlas; applied when FBX material is missing texture

# Per-animal visual state: anim_id → { node, anim, prev_state }
var _instances: Dictionary = {}

var world: World  # for ground height; set by Main

func setup(sim: AnimalSim) -> void:
	_sim = sim
	var tex := load("res://assets/textures/Atlas_COL_1k_LPAA.png")
	if tex is Texture2D:
		_atlas_tex = tex as Texture2D
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
		if inst is Node3D:
			root = inst as Node3D
			anim_player = _find_anim_player(inst)
			_ensure_texture(inst)
		else:
			inst.queue_free()
			root = _make_fallback(type_int)
	else:
		root = _make_fallback(type_int)

	var s: float = float(MESH_SCALES.get(type_int, 0.25))
	root.scale = Vector3(s, s, s)
	add_child(root)

	var entry := {
		"node":       root,
		"anim":       anim_player,
		"prev_state": -1,
	}
	_instances[animal.anim_id] = entry

	if anim_player:
		_play_for_state(anim_player, animal.state, animal.animal_type)

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
		AnimalSim.AnimalType.HORSE:  return "Horse"
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

func _ensure_texture(node: Node) -> void:
	# If a MeshInstance3D has no albedo texture, apply the shared atlas.
	# This handles cases where Godot's FBX importer can't locate the texture file.
	if not _atlas_tex: return
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for surf_idx in range(mi.mesh.get_surface_count()):
				var mat := mi.get_active_material(surf_idx)
				if mat is StandardMaterial3D:
					var sm := mat as StandardMaterial3D
					if sm.albedo_texture == null:
						var new_mat := sm.duplicate() as StandardMaterial3D
						new_mat.albedo_texture = _atlas_tex
						mi.set_surface_override_material(surf_idx, new_mat)
	for child in node.get_children():
		_ensure_texture(child)

func _make_fallback(animal_type: int) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.35, 0.35, 0.35)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	var col: Color = Color(FALLBACK_COLORS.get(animal_type, Color(0.7, 0.7, 0.7)))
	mat.albedo_color = col
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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
