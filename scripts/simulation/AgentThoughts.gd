class_name AgentThoughts
## Turns an agent's state into words for the inspector, speech bubbles and the
## walker's "listen in" moment. Pure functions of the agent, so they can be tested
## and never change the simulation.

const DOING := {
	Agent.State.WANDERING:   "wandering",
	Agent.State.GATHERING:   "looking for food",
	Agent.State.SLEEPING:    "asleep",
	Agent.State.SOCIALIZING: "talking with others",
	Agent.State.DISCOVERING: "puzzling something out",
	Agent.State.FISHING:     "fishing",
	Agent.State.PERFORMING:  "performing",
	Agent.State.TRADING:     "trading",
	Agent.State.RITUAL:      "at a gathering",
}

## What the agent is doing, as a short phrase ("looking for food").
static func doing(a: Agent) -> String:
	if a.is_dead:
		return "gone (" + a.death_cause.replace("_", " ") + ")"
	if a.trader_state == "outbound":
		return "on a trading journey"
	if a.trader_state == "returning":
		return "heading home from trading"
	return str(DOING.get(a.state, "wandering"))

## One first-person line: the most pressing thing on their mind.
## Ordered by urgency so the line explains what you see them doing.
static func thought(a: Agent) -> String:
	if a.is_dead:
		return ""
	var hunger: float = float(a.needs.get("hunger", 1.0))
	var energy: float = float(a.needs.get("energy", 1.0))
	if a.state == Agent.State.SLEEPING:
		return "Zzz…"
	if a.infected:
		return "I feel feverish. I should keep away from the little ones."
	if hunger < 0.2:
		return "So hungry. Where did the berries go?"
	if energy < 0.2:
		return "I can barely keep my eyes open."
	if a.discovery_flash > 0.0:
		return "I've worked something out! I must tell the others."
	if a.state == Agent.State.RITUAL:
		return "We stand together, and it feels like home."
	if a.trader_state != "":
		return "The road is long, but they'll want what I carry."
	if a.state == Agent.State.FISHING:
		return "Patience. The fish will come."
	if hunger < 0.45:
		return "I could eat."
	if a.life_stage == "infant" or a.life_stage == "child":
		return "Everything is new. What's that over there?"
	if a.is_elderly:
		return "I remember when none of us knew how to make fire."
	if a.knowledge.is_empty():
		return "There must be a better way to live than this."
	if float(a.personality.get("curiosity", 0.0)) > 0.6:
		return "I wonder what's past those hills."
	if a.bonded_partner_id >= 0:
		return "I should find my partner before dark."
	return "A good day. The weather holds."
