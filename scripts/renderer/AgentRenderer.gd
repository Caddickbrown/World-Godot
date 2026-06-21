class_name AgentRenderer
extends Node3D

const TILE_SIZE := World.TILE_SIZE

var agents: Array = []
var _agent_nodes: Dictionary = {}  # agent_id → Node3D

var _base_mesh: SphereMesh
var _mat_normal: StandardMaterial3D
var _mat_selected: StandardMaterial3D
var _mat_sleeping: StandardMaterial3D
var _mat_gathering: StandardMaterial3D
var _mat_dead: StandardMaterial3D

func _ready() -> void:
	_base_mesh = SphereMesh.new()
	_base_mesh.radius = 0.18
	_base_mesh.height = 0.36

	_mat_normal = _make_mat(Color(0.95, 0.80, 0.55))     # skin tone
	_mat_selected = _make_mat(Color(1.0, 0.95, 0.2))     # gold
	_mat_sleeping = _make_mat(Color(0.55, 0.65, 0.95))   # blue
	_mat_gathering = _make_mat(Color(0.60, 0.90, 0.45))  # green
	_mat_dead = _make_mat(Color(0.4, 0.4, 0.4))          # grey

func _make_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func setup(p_agents: Array) -> void:
	agents = p_agents
	for a in agents:
		_add_node(a)

func add_agent(agent: Agent) -> void:
	agents.append(agent)
	_add_node(agent)

func _add_node(agent: Agent) -> void:
	var node := MeshInstance3D.new()
	node.mesh = _base_mesh
	node.material_override = _mat_normal
	add_child(node)
	_agent_nodes[agent.agent_id] = node

func update() -> void:
	for agent in agents:
		var node: MeshInstance3D = _agent_nodes.get(agent.agent_id)
		if node == null:
			_add_node(agent)
			node = _agent_nodes[agent.agent_id]

		var tile := Vector3(agent.pos.x * TILE_SIZE, 0.28, agent.pos.y * TILE_SIZE)
		node.position = tile
		node.visible = true

		# Color by state
		if agent.is_dead:
			node.material_override = _mat_dead
		elif agent.selected:
			node.material_override = _mat_selected
		elif agent.state == Agent.State.SLEEPING:
			node.material_override = _mat_sleeping
		elif agent.state == Agent.State.GATHERING:
			node.material_override = _mat_gathering
		else:
			# Tint by faction if set
			var mat := _mat_normal
			if agent.get("faction", 0) > 0:
				# slight faction color variation
				pass
			node.material_override = mat

	# Remove nodes for dead/removed agents
	var active_ids: Array = agents.filter(func(a): return not a.is_dead).map(func(a): return a.agent_id)
	for id in _agent_nodes.keys():
		if not (id in active_ids):
			_agent_nodes[id].visible = false
