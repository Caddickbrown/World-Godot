extends RefCounted
## Animal minds: deaths that stick, packs and herds, fear of people, taming,
## riding, and animation clips that match what the animal is doing.

func run(t) -> void:
	var w := World.new(7)
	w.heightfield = Heightfield.new().build(w)
	_deaths(t, w)
	_groups_and_fear(t, w)
	_taming_and_riding(t, w)
	_clips(t)

func _meadow(t, w: World) -> Vector2:
	var m: Vector2i = t._first_tile(w, [World.TileType.GRASS])
	return Vector2(m.x + 0.5, m.y + 0.5)

func _deaths(t, w: World) -> void:
	var sim := AnimalSim.new()
	var p := _meadow(t, w)
	var deer := sim.spawn_one(AnimalSim.AnimalType.DEER, p.x, p.y)
	deer.health = 0.0   # PopulationManager's cull used to stop here: it kept walking
	sim.tick(0.1, w)
	t.check("a culled animal actually dies", deer.state == AnimalSim.AnimalState.DEAD and deer.cause == "culled")
	sim.tick(AnimalSim.CORPSE_SECONDS + 1.0, w)
	sim.tick(0.1, w)
	t.check("...and leaves the list once its body is gone", not sim.animals.has(deer))
	var cow := sim.spawn_one(AnimalSim.AnimalType.COW, p.x, p.y)
	cow.home = p
	cow.home_settlement = 1
	cow.health = 0.0
	sim.tick(0.1, w)
	t.check("a camp's kept animal is spared the cull", cow.state != AnimalSim.AnimalState.DEAD)

func _groups_and_fear(t, w: World) -> void:
	var sim := AnimalSim.new()
	sim.spawn_wildlife(w)
	t.check("wolves run in packs (%d)" % sim.group_count(AnimalSim.AnimalType.WOLF), sim.group_count(AnimalSim.AnimalType.WOLF) >= 1)
	var herd_types := [AnimalSim.AnimalType.DEER, AnimalSim.AnimalType.HORSE, AnimalSim.AnimalType.SHEEP, AnimalSim.AnimalType.COW]
	var herds := 0
	for ht in herd_types:
		herds += sim.group_count(ht)
	t.check("grazers drift in herds (%d)" % herds, herds >= 2)
	# A deer with a person walking up to it keeps its distance.
	var lone := AnimalSim.new()
	var p := _meadow(t, w)
	var deer := lone.spawn_one(AnimalSim.AnimalType.DEER, p.x, p.y)
	var walker: Agent = t._adult(p.x + 1.5, p.y)
	lone.people = [walker]
	var start := deer.pos.distance_to(walker.pos)
	for i in 60:
		lone.tick(0.1, w)
	t.check("a deer keeps its distance from people (%.1f -> %.1f tiles)" % [start, deer.pos.distance_to(walker.pos)],
		deer.pos.distance_to(walker.pos) > start + 0.5 or deer.fear > 0.3)

func _taming_and_riding(t, w: World) -> void:
	var sim := AnimalSim.new()
	var p := _meadow(t, w)
	var minds := AnimalMinds.new()
	minds.setup(w, sim)
	var ts := TimeSystem.new()
	var keeper: Agent = t._adult(p.x, p.y)
	keeper.knowledge["animal_domestication"] = true
	keeper.needs["hunger"] = 0.9
	var wolf := sim.spawn_one(AnimalSim.AnimalType.WOLF, p.x + 2.0, p.y)
	wolf.fed_timer = 9999.0   # not hungry: no one is in danger here
	var tamed := false
	for i in 200:
		minds.tick(1.0, [keeper], null, ts)
		if minds.dog_of(keeper) != null:
			tamed = true
			break
		wolf.pos = keeper.pos + Vector2(2.0, 0)
	t.check("someone who knows domestication tames a wolf into a dog", tamed and wolf.owner_id == keeper.agent_id)
	var rider: Agent = t._adult(p.x, p.y + 2.0)
	rider.knowledge["horse_taming"] = true
	var horse := sim.spawn_one(AnimalSim.AnimalType.HORSE, rider.pos.x + 0.5, rider.pos.y)
	minds._tame(horse, rider)
	t.check("a gentled horse is someone's", minds.horse_of(rider) == horse)
	rider.state = Agent.State.WANDERING
	rider.target = rider.pos + Vector2(12, 0)
	minds.tick(0.1, [keeper, rider], null, ts)
	t.check("...who rides it on a long trip", rider.riding_horse_id == horse.anim_id and horse.ridden)
	rider.pos += Vector2(0.6, 0)
	minds.tick(0.1, [keeper, rider], null, ts)
	t.check("...and the horse goes where the rider goes", horse.pos.distance_to(rider.pos) < 0.01)
	t.check("riding across grass is faster than walking (x%.1f)" % rider.ride_mult, rider.ride_mult > 1.2)

func _clips(t) -> void:
	var deer := ["deer_attack", "deer_death", "deer_idle 2", "deer_idle breath", "deer_idle to run", "deer_idle to walk", "deer_run", "deer_run to idle", "deer_walk", "deer_walk to idle"]
	t.check("a deer at rest breathes, it doesn't attack", AnimalRenderer.clip_for(deer, AnimalSim.AnimalState.IDLE) == "deer_idle breath")
	t.check("...walks with its walk, not a transition", AnimalRenderer.clip_for(deer, AnimalSim.AnimalState.WALK) == "deer_walk")
	t.check("...and runs when it flees", AnimalRenderer.clip_for(deer, AnimalSim.AnimalState.FLEE) == "deer_run")
	var cow := ["Attack", "Death", "Eat", "Idle1", "Idle2", "Run", "Sleep", "Sleep-Stand", "Walk"]
	t.check("a cow standing still idles (was 'Attack')", AnimalRenderer.clip_for(cow, AnimalSim.AnimalState.IDLE) == "Idle1")
	t.check("...and grazes", AnimalRenderer.clip_for(cow, AnimalSim.AnimalState.EAT) == "Eat")
	t.check("a one-clip model plays its clip", AnimalRenderer.clip_for(["Take 001"], AnimalSim.AnimalState.WALK) == "Take 001")
