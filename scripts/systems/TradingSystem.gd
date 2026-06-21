class_name TradingSystem
extends RefCounted

## Peer-to-peer item trading between agents who know the "trade" concept.

var _trade_cooldowns: Dictionary = {}  # agent_id (int) → float countdown

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func tick(delta: float, agents: Array, item_defs: Dictionary, day: int, history_log: HistoryLog) -> void:
	# Decrement all trade cooldowns
	var expired_ids: Array = []
	for key in _trade_cooldowns:
		var agent_id: int = int(key)
		var cd: float = float(_trade_cooldowns[agent_id])
		cd = maxf(0.0, cd - delta)
		if cd <= 0.0:
			expired_ids.append(agent_id)
		else:
			_trade_cooldowns[agent_id] = cd
	for agent_id in expired_ids:
		_trade_cooldowns.erase(agent_id)

	# Collect agents eligible to initiate a trade
	for entry in agents:
		var agent := entry as Agent
		if agent == null:
			continue
		if agent.is_dead:
			continue
		if int(agent.state) != int(Agent.State.SOCIALIZING):
			continue
		if not agent.knowledge.has("trade"):
			continue
		if _trade_cooldowns.has(agent.agent_id):
			continue

		var partner: Agent = _find_partner(agent, agents)
		if partner == null:
			continue
		if _trade_cooldowns.has(partner.agent_id):
			continue

		var traded: bool = _try_trade(agent, partner, item_defs)
		if traded:
			_trade_cooldowns[agent.agent_id] = 5.0
			_trade_cooldowns[partner.agent_id] = 5.0
			# The item that changed hands is logged inside _try_trade via the
			# returned value — we log here with a generic message since
			# _try_trade returns only bool.  See _try_trade_logged() variant below.


func _find_partner(agent: Agent, agents: Array) -> Agent:
	var best: Agent = null
	var best_dist: float = INF

	for entry in agents:
		var candidate := entry as Agent
		if candidate == null:
			continue
		if candidate.agent_id == agent.agent_id:
			continue
		if candidate.is_dead:
			continue
		if not candidate.knowledge.has("trade"):
			continue
		if _trade_cooldowns.has(candidate.agent_id):
			continue

		var dist: float = agent.pos.distance_to(candidate.pos)
		if dist <= 3.0 and dist < best_dist:
			best_dist = dist
			best = candidate

	return best


func _try_trade(a: Agent, b: Agent, item_defs: Dictionary) -> bool:
	# Find something a has surplus of (>2) that b lacks (<1)
	var a_offer_id: String = ""
	var b_offer_id: String = ""

	for stack_entry in a.inventory.stacks:
		var stack_a: Dictionary = stack_entry as Dictionary
		var item_a: String = String(stack_a.get("item_id", ""))
		var qty_a: float = float(stack_a.get("quantity", 0.0))
		if qty_a <= 2.0 or item_a.is_empty():
			continue
		# Check b lacks this item
		var b_has_qty: float = _get_qty(b, item_a)
		if b_has_qty < 1.0:
			a_offer_id = item_a
			break

	if a_offer_id.is_empty():
		return false

	for stack_entry in b.inventory.stacks:
		var stack_b: Dictionary = stack_entry as Dictionary
		var item_b: String = String(stack_b.get("item_id", ""))
		var qty_b: float = float(stack_b.get("quantity", 0.0))
		if qty_b <= 2.0 or item_b.is_empty():
			continue
		if item_b == a_offer_id:
			continue  # No same-item swaps
		# Check a lacks this item
		var a_has_qty: float = _get_qty(a, item_b)
		if a_has_qty < 1.0:
			b_offer_id = item_b
			break

	if b_offer_id.is_empty():
		return false

	# Execute the swap
	a.inventory.remove(a_offer_id, 1.0)
	b.inventory.add(a_offer_id, 1.0, item_defs)

	b.inventory.remove(b_offer_id, 1.0)
	a.inventory.add(b_offer_id, 1.0, item_defs)

	return true


## Extended variant that also logs the trade. Called from tick() when we need
## the traded item name in the log message.
func _try_trade_logged(a: Agent, b: Agent, item_defs: Dictionary, day: int, history_log: HistoryLog) -> bool:
	var a_offer_id: String = ""
	var b_offer_id: String = ""

	for stack_entry in a.inventory.stacks:
		var stack_a: Dictionary = stack_entry as Dictionary
		var item_a: String = String(stack_a.get("item_id", ""))
		var qty_a: float = float(stack_a.get("quantity", 0.0))
		if qty_a <= 2.0 or item_a.is_empty():
			continue
		var b_has_qty: float = _get_qty(b, item_a)
		if b_has_qty < 1.0:
			a_offer_id = item_a
			break

	if a_offer_id.is_empty():
		return false

	for stack_entry in b.inventory.stacks:
		var stack_b: Dictionary = stack_entry as Dictionary
		var item_b: String = String(stack_b.get("item_id", ""))
		var qty_b: float = float(stack_b.get("quantity", 0.0))
		if qty_b <= 2.0 or item_b.is_empty():
			continue
		if item_b == a_offer_id:
			continue
		var a_has_qty: float = _get_qty(a, item_b)
		if a_has_qty < 1.0:
			b_offer_id = item_b
			break

	if b_offer_id.is_empty():
		return false

	a.inventory.remove(a_offer_id, 1.0)
	b.inventory.add(a_offer_id, 1.0, item_defs)

	b.inventory.remove(b_offer_id, 1.0)
	a.inventory.add(b_offer_id, 1.0, item_defs)

	var msg: String = "%s traded %s with %s" % [a.agent_name, a_offer_id, b.agent_name]
	history_log.add("trade", msg, day)

	return true

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _get_qty(agent: Agent, item_id: String) -> float:
	for stack_entry in agent.inventory.stacks:
		var stack: Dictionary = stack_entry as Dictionary
		if String(stack.get("item_id", "")) == item_id:
			return float(stack.get("quantity", 0.0))
	return 0.0
