class_name HuntingSystem
extends RefCounted
## Hunting. The "hunting" idea used to change nothing: no one ever touched an
## animal. Now a hungry adult who knows it stalks the nearest deer or rabbit,
## and a kill feeds them and whoever is close by. Hunted herds thin out, which
## PopulationManager's predator/prey balance then has to answer.

const PREY := [AnimalSim.AnimalType.DEER, AnimalSim.AnimalType.RABBIT]
const HUNT_RANGE := 10.0      # tiles a hunter will go after prey
const KILL_RANGE := 0.9
const HUNGRY_BELOW := 0.55
const MEAT := {AnimalSim.AnimalType.DEER: 0.7, AnimalSim.AnimalType.RABBIT: 0.35}
const SHARE_RADIUS := 4.0
const SHARE_AMOUNT := 0.25
const RETHINK := 0.5          # seconds between a hunter looking for / at prey

var _cooldown: Dictionary = {}   # agent_id -> seconds until they look again

## Returns this tick's kills as [{hunter: Agent, prey_type: int, shared: int}].
func tick(delta: float, agents: Array, animal_sim: AnimalSim, spatial_grid = null) -> Array:
	var kills: Array = []
	if animal_sim == null:
		return kills
	for a in agents:
		if a.is_dead or a.health <= 0.0 or not a.is_adult or not a.knowledge.has("hunting"):
			continue
		if a.state == Agent.State.SLEEPING or a.at_fire or a.needs["hunger"] >= HUNGRY_BELOW:
			continue
		var cd: float = float(_cooldown.get(a.agent_id, 0.0)) - delta
		_cooldown[a.agent_id] = cd
		if cd > 0.0:
			continue
		_cooldown[a.agent_id] = RETHINK
		var prey := _nearest_prey(a, animal_sim)
		if prey == null:
			continue
		var d: float = a.pos.distance_to(prey.pos)
		if d <= KILL_RANGE:
			prey.health = 0.0
			prey.state = AnimalSim.AnimalState.DEAD
			a.needs["hunger"] = minf(1.0, a.needs["hunger"] + float(MEAT.get(prey.animal_type, 0.3)))
			var shared := 0
			var near: Array = spatial_grid.get_nearby_agents(a.pos, SHARE_RADIUS) if spatial_grid != null else agents
			for other in near:
				if other == a or other.is_dead or other.pos.distance_to(a.pos) > SHARE_RADIUS:
					continue
				if other.needs["hunger"] < 0.6:
					other.needs["hunger"] = minf(1.0, other.needs["hunger"] + SHARE_AMOUNT)
					shared += 1
			a.state = Agent.State.WANDERING
			_cooldown[a.agent_id] = 20.0
			kills.append({"hunter": a, "prey_type": prey.animal_type, "shared": shared})
		else:
			# Stalk: aim at where the prey is now.
			a.state = Agent.State.GATHERING
			a.target = prey.pos
			a.needs_check_timer = maxf(a.needs_check_timer, RETHINK + 0.5)
	return kills

func _nearest_prey(a: Agent, animal_sim: AnimalSim) -> AnimalSim.Animal:
	var best: AnimalSim.Animal = null
	var best_d := HUNT_RANGE
	for an in animal_sim.animals:
		if an.state == AnimalSim.AnimalState.DEAD or not (an.animal_type in PREY):
			continue
		var d: float = a.pos.distance_to(an.pos)
		if d < best_d:
			best_d = d
			best = an
	return best

static func prey_name(t: int) -> String:
	return "a deer" if t == AnimalSim.AnimalType.DEER else "a rabbit"
