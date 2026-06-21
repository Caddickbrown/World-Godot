class_name Inventory

const DEFAULT_MAX_WEIGHT := 10.0

var stacks: Array = []  # [{ item_id, quantity, freshness }]
var max_weight: float = DEFAULT_MAX_WEIGHT

func has(item_id: String) -> bool:
	for s in stacks:
		if s["item_id"] == item_id and s["quantity"] > 0:
			return true
	return false

func add(item_id: String, qty: float, item_defs: Dictionary) -> float:
	if item_defs.is_empty(): return 0.0
	var def: Dictionary = item_defs.get(item_id, {})
	var weight_per: float = float(def.get("weight", 0.1))
	var current_w: float = current_weight(item_defs)
	var space: float = (max_weight - current_w) / weight_per
	var can_add := minf(qty, space)
	if can_add <= 0.0: return 0.0

	for s in stacks:
		if s["item_id"] == item_id:
			s["quantity"] += can_add
			return can_add

	stacks.append({"item_id": item_id, "quantity": can_add, "freshness": 1.0})
	return can_add

func remove(item_id: String, qty: float) -> void:
	for i in range(stacks.size() - 1, -1, -1):
		var s: Dictionary = stacks[i]
		if s["item_id"] == item_id:
			s["quantity"] -= qty
			if s["quantity"] <= 0.0:
				stacks.remove_at(i)
			return

func current_weight(item_defs: Dictionary) -> float:
	var w := 0.0
	for s in stacks:
		var def: Dictionary = item_defs.get(s["item_id"], {})
		w += float(s["quantity"]) * float(def.get("weight", 0.1))
	return w

func is_full(item_id: String, item_defs: Dictionary) -> bool:
	var def: Dictionary = item_defs.get(item_id, {})
	var weight_per: float = float(def.get("weight", 0.1))
	return current_weight(item_defs) + weight_per > max_weight

func get_best_food(item_defs: Dictionary) -> Dictionary:
	var best := {}
	var best_value := -1.0
	for s in stacks:
		if s["quantity"] <= 0.0: continue
		var def: Dictionary = item_defs.get(s["item_id"], {})
		if def.get("category", "") != "food": continue
		var hunger_val: float = float(def.get("effects", {}).get("hunger", 0.0))
		if hunger_val > best_value:
			best_value = hunger_val
			best = s
	return best

func tick_spoilage(delta: float, item_defs: Dictionary, mult: float = 1.0) -> void:
	for i in range(stacks.size() - 1, -1, -1):
		var s: Dictionary = stacks[i]
		var def: Dictionary = item_defs.get(s["item_id"], {})
		var spoil_rate: float = float(def.get("spoil_rate", 0.0))
		if spoil_rate <= 0.0: continue
		s["freshness"] = maxf(0.0, s.get("freshness", 1.0) - spoil_rate * delta * mult)
		if s["freshness"] <= 0.0:
			stacks.remove_at(i)

func drop_all() -> Array:
	var out := stacks.duplicate(true)
	stacks.clear()
	return out
