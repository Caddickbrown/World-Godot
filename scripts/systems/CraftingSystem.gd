class_name CraftingSystem
extends RefCounted

## Knowledge-gated crafting with auto-craft behaviour for wandering agents.

const RECIPES: Dictionary = {
	"stone_tool": {
		"requires_knowledge": "stone_tools",
		"ingredients": [
			{"item": "stone", "qty": 1.0},
			{"item": "wood", "qty": 1.0}
		],
		"output": {"item": "stone_tool", "qty": 1.0}
	},
	"rope": {
		"requires_knowledge": "weaving",
		"ingredients": [
			{"item": "plant_fibre", "qty": 2.0}
		],
		"output": {"item": "rope", "qty": 1.0}
	},
	"campfire_kit": {
		"requires_knowledge": "fire",
		"ingredients": [
			{"item": "wood", "qty": 3.0}
		],
		"output": {"item": "campfire_kit", "qty": 1.0}
	},
	"flour": {
		"requires_knowledge": "agriculture",
		"ingredients": [
			{"item": "wild_grain", "qty": 3.0}
		],
		"output": {"item": "flour", "qty": 1.0}
	},
	"bread": {
		"requires_knowledge": "fire",
		"ingredients": [
			{"item": "flour", "qty": 1.0}
		],
		"output": {"item": "bread", "qty": 1.0}
	},
	"medicine_bundle": {
		"requires_knowledge": "medicine",
		"ingredients": [
			{"item": "herbs", "qty": 3.0}
		],
		"output": {"item": "medicine", "qty": 1.0}
	}
}

# How often (seconds) an agent can auto-craft
const AUTO_CRAFT_INTERVAL: float = 30.0

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func try_craft(agent: Agent, recipe_id: String, item_defs: Dictionary) -> bool:
	if not RECIPES.has(recipe_id):
		return false

	var recipe: Dictionary = RECIPES[recipe_id] as Dictionary
	var required_knowledge: String = String(recipe.get("requires_knowledge", ""))

	if not agent.knowledge.has(required_knowledge):
		return false

	var ingredients: Array = recipe.get("ingredients", []) as Array
	# Verify all ingredients are present
	for entry in ingredients:
		var ing: Dictionary = entry as Dictionary
		var item_id: String = String(ing.get("item", ""))
		var qty_needed: float = float(ing.get("qty", 1.0))
		if not agent.inventory.has(item_id):
			return false
		if _get_qty(agent, item_id) < qty_needed:
			return false

	# Consume ingredients
	for entry in ingredients:
		var ing: Dictionary = entry as Dictionary
		var item_id: String = String(ing.get("item", ""))
		var qty_needed: float = float(ing.get("qty", 1.0))
		agent.inventory.remove(item_id, qty_needed)

	# Add output
	var output: Dictionary = recipe.get("output", {}) as Dictionary
	var out_item: String = String(output.get("item", ""))
	var out_qty: float = float(output.get("qty", 1.0))
	if not out_item.is_empty():
		agent.inventory.add(out_item, out_qty, item_defs)

	return true


func get_available_recipes(agent: Agent) -> Array:
	var available: Array = []
	for recipe_id in RECIPES:
		var rid: String = String(recipe_id)
		var recipe: Dictionary = RECIPES[rid] as Dictionary
		var required_knowledge: String = String(recipe.get("requires_knowledge", ""))

		if not agent.knowledge.has(required_knowledge):
			continue

		var ingredients: Array = recipe.get("ingredients", []) as Array
		var can_craft: bool = true
		for entry in ingredients:
			var ing: Dictionary = entry as Dictionary
			var item_id: String = String(ing.get("item", ""))
			var qty_needed: float = float(ing.get("qty", 1.0))
			if _get_qty(agent, item_id) < qty_needed:
				can_craft = false
				break

		if can_craft:
			available.append(rid)

	return available


func tick(delta: float, agents: Array, item_defs: Dictionary, day: int, history_log: HistoryLog) -> void:
	for entry in agents:
		var agent := entry as Agent
		if agent == null:
			continue
		if agent.is_dead:
			continue
		if int(agent.state) != int(Agent.State.WANDERING):
			continue

		# Decrement per-agent craft timer
		var timer: float = float(agent.get_meta("craft_timer", 0.0))
		timer = maxf(0.0, timer - delta)
		agent.set_meta("craft_timer", timer)

		if timer > 0.0:
			continue

		# Attempt auto-craft if recipes are available
		var available: Array = get_available_recipes(agent)
		if available.is_empty():
			continue

		# Pick the first available recipe (stable, deterministic order)
		var chosen_id: String = String(available[0])
		var recipe: Dictionary = RECIPES[chosen_id] as Dictionary

		# Only auto-craft when at least one ingredient is surplus (qty > needed)
		if not _has_surplus_ingredients(agent, recipe):
			continue

		var success: bool = try_craft(agent, chosen_id, item_defs)
		if success:
			var output: Dictionary = recipe.get("output", {}) as Dictionary
			var out_item: String = String(output.get("item", ""))
			var msg: String = "%s crafted %s" % [agent.agent_name, out_item]
			history_log.add("craft", msg, day)
			agent.set_meta("craft_timer", AUTO_CRAFT_INTERVAL)

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _get_qty(agent: Agent, item_id: String) -> float:
	for stack_entry in agent.inventory.stacks:
		var stack: Dictionary = stack_entry as Dictionary
		if String(stack.get("item_id", "")) == item_id:
			return float(stack.get("quantity", 0.0))
	return 0.0


func _has_surplus_ingredients(agent: Agent, recipe: Dictionary) -> bool:
	## Returns true if the agent has more than the minimum required for at least
	## one ingredient (i.e. they have something to spare).
	var ingredients: Array = recipe.get("ingredients", []) as Array
	for entry in ingredients:
		var ing: Dictionary = entry as Dictionary
		var item_id: String = String(ing.get("item", ""))
		var qty_needed: float = float(ing.get("qty", 1.0))
		if _get_qty(agent, item_id) > qty_needed:
			return true
	return false
