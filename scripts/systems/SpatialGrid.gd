class_name SpatialGrid
extends RefCounted

const CELL_SIZE := 4.0

# "cx,cz" → Array of Agent
var _grid: Dictionary = {}

# agent_id → Vector2 (last known pos)
var _positions: Dictionary = {}

# agent_id → Agent, so id-based queries can still resolve without a rebuild
var _agents_by_id: Dictionary = {}

# ── Build / clear ─────────────────────────────────────────────────────────────

func update(agents: Array) -> void:
	_grid.clear()
	_positions.clear()
	_agents_by_id.clear()

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
		cell.append(a)
		_positions[a.agent_id] = a.pos
		_agents_by_id[a.agent_id] = a

func clear() -> void:
	_grid.clear()
	_positions.clear()
	_agents_by_id.clear()

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
			for entry in cell:
				var a: Agent = entry as Agent
				if a == null:
					continue
				var dx: float = a.pos.x - pos.x
				var dz: float = a.pos.y - pos.y
				if dx * dx + dz * dz <= radius_sq:
					result.append(a.agent_id)

	return result

# Returns the Agents within `radius` of `pos`. Cells hold Agent references, so
# this touches only the overlapping cells — it never walks the full population.
# `_all_agents` is accepted for call-site compatibility and is unused.
func get_nearby_agents(pos: Vector2, radius: float, _all_agents: Array = []) -> Array:
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
			for entry in (_grid[key] as Array):
				var a: Agent = entry as Agent
				if a == null:
					continue
				var dx: float = a.pos.x - pos.x
				var dz: float = a.pos.y - pos.y
				if dx * dx + dz * dz <= radius_sq:
					result.append(a)
	return result

func get_agent(agent_id: int) -> Agent:
	return _agents_by_id.get(agent_id, null) as Agent
