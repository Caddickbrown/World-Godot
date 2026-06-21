class_name TileItems
extends RefCounted

const MAX_STACKS_PER_TILE := 20

# "x,z" → Array of { "item_id": String, "quantity": float, "freshness": float }
var _tiles: Dictionary = {}

# ── Drop / pickup ─────────────────────────────────────────────────────────────

func drop(x: int, z: int, item_id: String, qty: float) -> void:
	if qty <= 0.0:
		return

	var key: String = "%d,%d" % [x, z]
	if not _tiles.has(key):
		_tiles[key] = []
	var stacks: Array = _tiles[key] as Array

	# Merge into an existing stack with the same item_id.
	for s in stacks:
		var stack: Dictionary = s as Dictionary
		if String(stack.get("item_id", "")) == item_id:
			stack["quantity"] = float(stack.get("quantity", 0.0)) + qty
			return

	# Add a fresh stack.
	stacks.append({"item_id": item_id, "quantity": qty, "freshness": 1.0})

	# Enforce per-tile stack cap — drop the oldest (first) stack.
	while stacks.size() > MAX_STACKS_PER_TILE:
		stacks.pop_front()

func pickup(x: int, z: int, item_id: String, qty: float) -> float:
	var key: String = "%d,%d" % [x, z]
	if not _tiles.has(key):
		return 0.0
	var stacks: Array = _tiles[key] as Array

	var taken: float = 0.0
	var remaining: float = qty

	for i in range(stacks.size() - 1, -1, -1):
		var stack: Dictionary = stacks[i] as Dictionary
		if String(stack.get("item_id", "")) != item_id:
			continue
		var available: float = float(stack.get("quantity", 0.0))
		var take: float = minf(available, remaining)
		stack["quantity"] = available - take
		taken += take
		remaining -= take
		if float(stack.get("quantity", 0.0)) <= 0.0:
			stacks.remove_at(i)
		if remaining <= 0.0:
			break

	if stacks.is_empty():
		_tiles.erase(key)

	return taken

# ── Queries ───────────────────────────────────────────────────────────────────

func get_items(x: int, z: int) -> Array:
	var key: String = "%d,%d" % [x, z]
	if not _tiles.has(key):
		return []
	return _tiles[key] as Array

func has_items(x: int, z: int) -> bool:
	var key: String = "%d,%d" % [x, z]
	if not _tiles.has(key):
		return false
	var stacks: Array = _tiles[key] as Array
	return not stacks.is_empty()

# ── Spoilage ──────────────────────────────────────────────────────────────────

func tick_spoilage(delta: float, item_defs: Dictionary, disaster_mult: float) -> void:
	var keys: Array = _tiles.keys()
	for key in keys:
		var stacks: Array = _tiles[key] as Array
		for i in range(stacks.size() - 1, -1, -1):
			var stack: Dictionary = stacks[i] as Dictionary
			var item_id: String = String(stack.get("item_id", ""))
			var def: Dictionary = item_defs.get(item_id, {}) as Dictionary
			var spoil_rate: float = float(def.get("spoilRate", 0.0))
			if spoil_rate <= 0.0:
				continue
			var fresh: float = float(stack.get("freshness", 1.0))
			fresh = maxf(0.0, fresh - spoil_rate * delta * 2.0 * disaster_mult)
			stack["freshness"] = fresh
			if fresh <= 0.0:
				stacks.remove_at(i)
		if stacks.is_empty():
			_tiles.erase(key)

# ── Agent death drop ──────────────────────────────────────────────────────────

func drop_agent_items(agent: Agent, _world: World) -> void:
	var tx: int = int(agent.pos.x)
	var tz: int = int(agent.pos.y)

	var items: Array = agent.inventory.drop_all()
	for item in items:
		var stack: Dictionary = item as Dictionary
		var item_id: String = String(stack.get("item_id", ""))
		var quantity: float = float(stack.get("quantity", 0.0))
		var freshness: float = float(stack.get("freshness", 1.0))
		if item_id.is_empty() or quantity <= 0.0:
			continue
		var key: String = "%d,%d" % [tx, tz]
		if not _tiles.has(key):
			_tiles[key] = []
		var stacks: Array = _tiles[key] as Array

		# Merge if same item_id already on tile.
		var merged: bool = false
		for s in stacks:
			var existing: Dictionary = s as Dictionary
			if String(existing.get("item_id", "")) == item_id:
				existing["quantity"] = float(existing.get("quantity", 0.0)) + quantity
				# Blend freshness by quantity weighting.
				var old_qty: float = float(existing.get("quantity", quantity)) - quantity
				var total: float = old_qty + quantity
				if total > 0.0:
					existing["freshness"] = (float(existing.get("freshness", 1.0)) * old_qty + freshness * quantity) / total
				merged = true
				break
		if not merged:
			stacks.append({"item_id": item_id, "quantity": quantity, "freshness": freshness})
			while stacks.size() > MAX_STACKS_PER_TILE:
				stacks.pop_front()

# ── Utility ───────────────────────────────────────────────────────────────────

func clear() -> void:
	_tiles.clear()
