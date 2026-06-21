class_name UtilityAI
extends RefCounted

# ---------------------------------------------------------------------------
# Food item IDs recognised as edible
# ---------------------------------------------------------------------------

const FOOD_ITEMS: Array = [
	"berries", "fish", "cooked_fish", "meat", "cooked_meat",
	"bread", "mushrooms", "milk", "eggs"
]

# ---------------------------------------------------------------------------
# Primary API
# ---------------------------------------------------------------------------

## Returns a Dictionary of action_id (String) → score (float), all in [0, 1].
func score_actions(agent: Agent, world: World, item_defs: Dictionary) -> Dictionary:
	var scores: Dictionary = {}

	var hunger: float = float(agent.needs.get("hunger", 0.0))
	var energy: float = float(agent.needs.get("energy", 1.0))

	var sociability: float    = float(agent.personality.get("sociability", 0.0))
	var creativity: float     = float(agent.personality.get("creativity", 0.0))
	var industriousness: float = float(agent.personality.get("industriousness", 0.0))

	# eat: only useful if agent carries food
	if _has_food(agent):
		scores["eat"] = clampf((1.0 - hunger) * 2.0, 0.0, 1.0)
	else:
		scores["eat"] = 0.0

	# sleep
	if energy < 0.4:
		scores["sleep"] = clampf((1.0 - energy) * 2.0, 0.0, 1.0)
	else:
		scores["sleep"] = clampf((1.0 - energy) * 0.5, 0.0, 1.0)

	# gather: hunger drives foraging
	if hunger < 0.6:
		scores["gather"] = clampf((1.0 - hunger) * 1.5, 0.0, 1.0)
	else:
		scores["gather"] = 0.0

	# fish: needs "fishing" knowledge and sufficient hunger
	if agent.knowledge.has("fishing") and hunger < 0.7:
		scores["fish"] = clampf((1.0 - hunger) * 1.2, 0.0, 1.0)
	else:
		scores["fish"] = 0.0

	# socialize: energy-gated
	if energy > 0.5:
		scores["socialize"] = clampf(sociability * 0.8, 0.0, 1.0)
	else:
		scores["socialize"] = 0.0

	# perform: creativity-driven, needs energy and relevant knowledge
	if energy > 0.6 and (agent.knowledge.has("music") or agent.knowledge.has("art")):
		scores["perform"] = clampf(creativity * 0.6, 0.0, 1.0)
	else:
		scores["perform"] = 0.0

	# craft: lightweight ingredient check
	if _can_craft(agent):
		scores["craft"] = clampf(industriousness * 0.5, 0.0, 1.0)
	else:
		scores["craft"] = 0.0

	# trade: social-driven, needs trade knowledge
	if agent.knowledge.has("trade"):
		scores["trade"] = clampf(sociability * 0.4, 0.0, 1.0)
	else:
		scores["trade"] = 0.0

	# wander: constant baseline
	scores["wander"] = 0.2

	return scores


## Returns the action_id with the highest score.
func best_action(agent: Agent, world: World, item_defs: Dictionary) -> String:
	var scores: Dictionary = score_actions(agent, world, item_defs)
	var best_id: String = "wander"
	var best_score: float = -1.0
	for action: Variant in scores.keys():
		var s: float = float(scores[action])
		if s > best_score:
			best_score = s
			best_id = str(action)
	return best_id

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _has_food(agent: Agent) -> bool:
	for item_id: String in FOOD_ITEMS:
		if agent.inventory.has(item_id):
			return true
	return false


func _can_craft(agent: Agent) -> bool:
	if not agent.knowledge.has("stone_tools"):
		return false
	var energy: float = float(agent.needs.get("energy", 0.0))
	return energy > 0.3
