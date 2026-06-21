class_name AgentRenderer
extends Node3D

const TILE_SIZE := World.TILE_SIZE

# EverydayMotion characters — rigged male/female with separate animation FBXes.
# Preferred over Synty characters because they have actual walk/idle animations.
const MALE_PATH   := "res://assets/characters/male.FBX"
const FEMALE_PATH := "res://assets/characters/female.FBX"
const ANIM_IDLE_M := "res://assets/animations/male_idle.FBX"
const ANIM_RUN_M  := "res://assets/animations/male_run.FBX"
const ANIM_IDLE_F := "res://assets/animations/female_idle.FBX"
const ANIM_RUN_F  := "res://assets/animations/female_run.FBX"
# Fallback: Synty combined FBX if EverydayMotion not imported yet
const CHARACTER_PATH := "res://assets/characters/FantasyKingdom_Characters.fbx"
# Scale: EverydayMotion models are in Unity cm units, ~180 cm tall
const CHARACTER_SCALE := 0.008

var agents: Array = []
var _agent_nodes: Dictionary = {}   # agent_id → { node, anim }

var _male_scene: PackedScene        # EverydayMotion male
var _female_scene: PackedScene      # EverydayMotion female
var _synty_scene: PackedScene       # Synty fallback
var _anim_idle_m: PackedScene
var _anim_run_m: PackedScene
var _anim_idle_f: PackedScene
var _anim_run_f: PackedScene
var _synty_mat: StandardMaterial3D

# Tint materials for state
var _mat_selected: StandardMaterial3D
var _mat_dead: StandardMaterial3D
var _fallback_mesh: SphereMesh

func _ready() -> void:
	_synty_mat = SyntyMaterial.make()

	_mat_selected = _synty_mat.duplicate() as StandardMaterial3D
	_mat_selected.albedo_color = Color(1.0, 0.95, 0.2)
	_mat_selected.emission_enabled = true
	_mat_selected.emission = Color(0.4, 0.35, 0.0)

	_mat_dead = StandardMaterial3D.new()
	_mat_dead.albedo_color = Color(0.4, 0.4, 0.42)
	_mat_dead.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_fallback_mesh = SphereMesh.new()
	_fallback_mesh.radius = 0.18
	_fallback_mesh.height = 0.36

	# Try EverydayMotion first, then Synty as fallback
	_male_scene   = _try_load(MALE_PATH)
	_female_scene = _try_load(FEMALE_PATH)
	_anim_idle_m  = _try_load(ANIM_IDLE_M)
	_anim_run_m   = _try_load(ANIM_RUN_M)
	_anim_idle_f  = _try_load(ANIM_IDLE_F)
	_anim_run_f   = _try_load(ANIM_RUN_F)
	if _male_scene == null:
		_synty_scene = _try_load(CHARACTER_PATH)

func _try_load(path: String) -> PackedScene:
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is PackedScene: return res as PackedScene
	return null

func setup(p_agents: Array) -> void:
	agents = p_agents
	for a in agents:
		_add_node(a)

func add_agent(agent: Agent) -> void:
	agents.append(agent)
	_add_node(agent)

func _add_node(agent: Agent) -> void:
	var root: Node3D
	var anim_player: AnimationPlayer = null

	# Pick gender by agent id
	var use_female: bool = (agent.agent_id % 2 == 0)
	var char_scene: PackedScene = _female_scene if use_female else _male_scene

	if char_scene:
		var inst := char_scene.instantiate()
		if inst is Node3D:
			root = inst as Node3D
			anim_player = _find_anim_player(root)
			# Inject animations from separate motion FBXes
			if anim_player:
				_inject_anims(anim_player, use_female)
				if anim_player.has_animation("idle"):
					anim_player.play("idle")
				else:
					_play_first(anim_player)
		else:
			inst.queue_free()
			root = null

	if root == null and _synty_scene:
		var inst := _synty_scene.instantiate()
		if inst is Node3D:
			root = inst as Node3D
			_show_one_character(root, agent.agent_id)
			SyntyMaterial.apply_to(root, _synty_mat)
		else:
			inst.queue_free()

	if root == null:
		root = _make_fallback()

	root.scale = Vector3(CHARACTER_SCALE, CHARACTER_SCALE, CHARACTER_SCALE)
	add_child(root)
	_agent_nodes[agent.agent_id] = {"node": root, "anim": anim_player, "prev_state": -1}

func _inject_anims(player: AnimationPlayer, female: bool) -> void:
	var idle_scene: PackedScene = _anim_idle_f if female else _anim_idle_m
	var run_scene:  PackedScene = _anim_run_f  if female else _anim_run_m
	_copy_anim_from_scene(player, idle_scene, "idle")
	_copy_anim_from_scene(player, run_scene,  "run")

func _copy_anim_from_scene(target: AnimationPlayer, scene: PackedScene, rename: String) -> void:
	if scene == null: return
	var inst := scene.instantiate()
	var src: AnimationPlayer = _find_anim_player(inst)
	if src:
		var lib := src.get_animation_library("")
		if lib:
			for anim_name in lib.get_animation_list():
				var anim: Animation = lib.get_animation(str(anim_name))
				var target_lib := target.get_animation_library("")
				if target_lib == null:
					target_lib = AnimationLibrary.new()
					target.add_animation_library("", target_lib)
				if not target_lib.has_animation(rename):
					target_lib.add_animation(rename, anim)
				break  # take first animation from the clip
	inst.queue_free()

func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var result: AnimationPlayer = _find_anim_player(child)
		if result: return result
	return null

func _play_first(player: AnimationPlayer) -> void:
	var all := player.get_animation_list()
	if all.size() > 0: player.play(str(all[0]))

# Show only the Nth MeshInstance3D (determined by agent_id mod count),
# hide all others. This gives visual variety — different characters per agent.
func _show_one_character(root: Node3D, agent_id: int) -> void:
	var meshes: Array = []
	_collect_meshes(root, meshes)
	if meshes.is_empty(): return
	var pick: int = agent_id % meshes.size()
	for i in range(meshes.size()):
		var mi: MeshInstance3D = meshes[i] as MeshInstance3D
		mi.visible = (i == pick)

func _collect_meshes(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out)

func _make_fallback() -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _fallback_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.80, 0.55)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	root.add_child(mi)
	return root

func update() -> void:
	var active_ids: Dictionary = {}
	for agent in agents:
		active_ids[agent.agent_id] = true

		if not _agent_nodes.has(agent.agent_id):
			_add_node(agent)

		var entry: Dictionary = _agent_nodes.get(agent.agent_id, {}) as Dictionary
		var node: Node3D = entry.get("node") as Node3D
		if node == null: continue

		var tx: float = agent.pos.x * TILE_SIZE
		var tz: float = agent.pos.y * TILE_SIZE
		node.position = Vector3(tx, 0.0, tz)
		node.visible = true

		if agent.state != Agent.State.SLEEPING:
			var target_pos := Vector3(float(agent.target.x) * TILE_SIZE, 0.0, float(agent.target.y) * TILE_SIZE)
			var diff := target_pos - node.position
			if diff.length() > 0.1:
				node.rotation.y = atan2(diff.x, diff.z)

		# Animation state transitions
		var anim: AnimationPlayer = entry.get("anim") as AnimationPlayer
		if anim:
			var prev: int = int(entry.get("prev_state", -1))
			if int(agent.state) != prev:
				entry["prev_state"] = int(agent.state)
				_set_anim(anim, agent.state)

		if agent.is_dead:
			node.rotation.x = deg_to_rad(90.0)
		else:
			node.rotation.x = 0.0

	# Hide nodes for removed agents
	for id in _agent_nodes:
		if not active_ids.has(id):
			var entry: Dictionary = _agent_nodes[id] as Dictionary
			var node: Node3D = entry.get("node") as Node3D
			if node: node.visible = false

func _set_anim(player: AnimationPlayer, state: int) -> void:
	var name_to_try: String
	match state:
		Agent.State.SLEEPING:    name_to_try = "idle"
		Agent.State.GATHERING:   name_to_try = "run"
		Agent.State.WANDERING:   name_to_try = "run"
		Agent.State.SOCIALIZING: name_to_try = "idle"
		Agent.State.TRADING:     name_to_try = "idle"
		Agent.State.RITUAL:      name_to_try = "idle"
		Agent.State.PERFORMING:  name_to_try = "idle"
		Agent.State.FISHING:     name_to_try = "idle"
		_:                       name_to_try = "idle"
	if player.has_animation(name_to_try):
		player.play(name_to_try)
	else:
		_play_first(player)
