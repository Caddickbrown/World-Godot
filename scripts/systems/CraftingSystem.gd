class_name CraftingSystem
extends RefCounted

## Knowledge-gated crafting, read from data/items.json: an item with
## "craftFrom" (its ingredients, one entry per unit) can be made by someone who
## knows every idea in its "knowledge". People craft when they're idle and
## carry more than a recipe needs. The recipes used to be a second, hand-kept
## copy of the data here, and disagreed with it (bread needed "fire_making",
## an idea that doesn't exist); nobody carried anything, so nothing was made.
## The first of each thing made is told in the chronicle.

## How often (seconds) an agent can auto-craft
const AUTO_CRAFT_INTERVAL: float = 30.0

var _made: Dictionary = {}   # item id -> true once someone has made one

## recipe id (= the item made) -> {requires: [idea ids], ingredients: [{item, qty}], output: {item, qty}}
static var _cache: Dictionary = {}
static var _cache_of: int = -1

static func recipes(item_defs: Dictionary) -> Dictionary:
	if _cache_of == item_defs.hash():
		return _cache
	var out := {}
	for id in item_defs:
		var def: Dictionary = item_defs[id]
		if not def.has("craftFrom"):
			continue
		var counts := {}
		for ing in def["craftFrom"]:
			counts[str(ing)] = float(counts.get(str(ing), 0.0)) + 1.0
		var ings: Array = []
		for k in counts:
			ings.append({"item": k, "qty": counts[k]})
		out[str(id)] = {"requires": def.get("knowledge", []), "ingredients": ings,
			"output": {"item": str(id), "qty": 1.0}}
	_cache = out
	_cache_of = item_defs.hash()
	return out

func _knows_all(agent: Agent, ideas: Array) -> bool:
	for k in ideas:
		if not agent.knowledge.has(str(k)):
			return false
	return true

func try_craft(agent: Agent, recipe_id: String, item_defs: Dictionary) -> bool:
	var all := recipes(item_defs)
	if not all.has(recipe_id):
		return false
	var recipe: Dictionary = all[recipe_id]
	if not _knows_all(agent, recipe["requires"]):
		return false
	for ing in recipe["ingredients"]:
		if agent.inventory.quantity_of(str(ing["item"])) < float(ing["qty"]):
			return false
	for ing in recipe["ingredients"]:
		agent.inventory.remove(str(ing["item"]), float(ing["qty"]))
	agent.inventory.add(str(recipe["output"]["item"]), float(recipe["output"]["qty"]), item_defs)
	return true

func get_available_recipes(agent: Agent, item_defs: Dictionary) -> Array:
	var available: Array = []
	var all := recipes(item_defs)
	var ids := all.keys()
	ids.sort()
	for rid in ids:
		var recipe: Dictionary = all[rid]
		if not _knows_all(agent, recipe["requires"]):
			continue
		var ok := true
		for ing in recipe["ingredients"]:
			if agent.inventory.quantity_of(str(ing["item"])) < float(ing["qty"]):
				ok = false
				break
		if ok:
			available.append(rid)
	return available

func tick(delta: float, agents: Array, item_defs: Dictionary, day: int, history_log: HistoryLog) -> void:
	for entry in agents:
		var agent := entry as Agent
		if agent == null or agent.is_dead or agent.inventory.stacks.is_empty():
			continue
		if int(agent.state) != int(Agent.State.WANDERING):
			continue
		var timer: float = maxf(0.0, float(agent.get_meta("craft_timer", 0.0)) - delta)
		agent.set_meta("craft_timer", timer)
		if timer > 0.0:
			continue
		var available: Array = get_available_recipes(agent, item_defs)
		if available.is_empty():
			agent.set_meta("craft_timer", 3.0)   # look again in a while, not every frame
			continue
		var chosen_id: String = String(available[0])
		if try_craft(agent, chosen_id, item_defs):
			agent.set_meta("craft_timer", AUTO_CRAFT_INTERVAL)
			var iname := str(item_defs.get(chosen_id, {}).get("name", chosen_id)).to_lower()
			agent.say("A %s!" % iname, 3.0)
			if not _made.has(chosen_id):
				_made[chosen_id] = true
				history_log.add("craft", "%s made the first %s" % [agent.agent_name, iname], day)
