class_name SpatialGrid
extends RefCounted

const CELL_SIZE := 4.0

# "cx,cz" → Array of agent_id ints
var _grid: Dictionary = {}

# agent_id → Vector2 (last known pos)
var _positions: Dictionary = {}

# ── Build / clear ─────────────────────────────────────────────────────────────

func update(agents: Array) -> void:
	_grid.clear()
	_positions.clear()

	for agent in agents:
		var a: Agent = agent as Agent
		if a == null or a.is_dead:
			continue
		var cx: int = int(floorf(a.pos.x / CELL_SIZE))
		var cz: int = int(floorf(a.pos.y / CELL_SIZE))
		var key: String = "%d,%d" % [cx, cz]
		if not _grid.has(key):
			_grid[key] = []
		var cell: Array = _grid[key] as Array
		cell.append(a.agent_id)
		_positions[a.agent_id] = a.pos

func clear() -> void:
	_grid.clear()
	_positions.clear()

# ── Queries ───────────────────────────────────────────────────────────────────

func get_nearby(pos: Vector2, radius: float) -> Array:
	var result: Array = []

	var min_cx: int = int(floorf((pos.x - radius) / CELL_SIZE))
	var max_cx: int = int(ceilf((pos.x + radius) / CELL_SIZE))
	var min_cz: int = int(floorf((pos.y - radius) / CELL_SIZE))
	var max_cz: int = int(ceilf((pos.y + radius) / CELL_SIZE))

	var radius_sq: float = radius * radius

	for cz in range(min_cz, max_cz + 1):
		for cx in range(min_cx, max_cx + 1):
			var key: String = "%d,%d" % [cx, cz]
			if not _grid.has(key):
				continue
			var cell: Array = _grid[key] as Array
			for id in cell:
				var agent_id: int = int(id)
				if not _positions.has(agent_id):
					continue
				var apos: Vector2 = _positions[agent_id] as Vector2
				var dx: float = apos.x - pos.x
				var dz: float = apos.y - pos.y
				if dx * dx + dz * dz <= radius_sq:
					result.append(agent_id)

	return result

func get_nearby_agents(pos: Vector2, radius: float, all_agents: Array) -> Array:
	var id_set: Array = get_nearby(pos, radius)
	if id_set.is_empty():
		return []

	# Build a temporary id → Agent lookup.
	var id_map: Dictionary = {}
	for agent in all_agents:
		var a: Agent = agent as Agent
		if a == null:
			continue
		id_map[a.agent_id] = a

	var result: Array = []
	for id in id_set:
		var agent_id: int = int(id)
		if id_map.has(agent_id):
			result.append(id_map[agent_id])

	return result
