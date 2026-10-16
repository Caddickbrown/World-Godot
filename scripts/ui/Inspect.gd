class_name Inspect
extends RefCounted
## What's under the cursor, in words, for the inspect card: an animal, a
## building, or the ground itself. Reads the world, never writes it.

const ANIMAL_REACH := 1.6      # tiles
const STATE_WORDS := {
	AnimalSim.AnimalState.IDLE: "standing", AnimalSim.AnimalState.WALK: "wandering",
	AnimalSim.AnimalState.RUN: "running", AnimalSim.AnimalState.EAT: "grazing",
	AnimalSim.AnimalState.FLEE: "fleeing", AnimalSim.AnimalState.HUNT: "hunting",
	AnimalSim.AnimalState.SOAR: "soaring", AnimalSim.AnimalState.DEAD: "dead",
}
const TILE_WORDS := {
	World.TileType.DEEP_WATER: "Open sea", World.TileType.WATER: "Shallow water", World.TileType.BEACH: "Beach",
	World.TileType.GRASS: "Meadow", World.TileType.WOODLAND: "Woodland", World.TileType.FOREST: "Pine forest",
	World.TileType.DESERT: "Dry ground", World.TileType.STONE: "Bare rock", World.TileType.MOUNTAIN: "Mountain",
	World.TileType.GLACIER: "Ice", World.TileType.LAVA: "Lava",
}

## {kind: "animal"|"building"|"ground", title, lines: [String]} for a point in world metres.
static func describe(main: Node, p: Vector3) -> Dictionary:
	var tile_pos := Vector2(p.x, p.z) / World.TILE_SIZE
	var a := _animal_at(main, tile_pos)
	if a:
		return _animal(main, a)
	var b := _building_at(main, Vector2(p.x, p.z))
	if not b.is_empty():
		return {"kind": "building", "title": str(b["name"]),
			"lines": ["Raised day %d" % int(b["day"]), "At %s" % str(b.get("settlement_name", ""))]}
	return _ground(main, tile_pos)

static func _animal_at(main: Node, tp: Vector2) -> AnimalSim.Animal:
	if main.animal_sim == null:
		return null
	var best: AnimalSim.Animal = null
	var best_d := ANIMAL_REACH
	for an in main.animal_sim.animals:
		if an.state == AnimalSim.AnimalState.DEAD:
			continue
		var d: float = an.pos.distance_to(tp)
		if d < best_d:
			best_d = d
			best = an
	return best

static func _animal(main: Node, an: AnimalSim.Animal) -> Dictionary:
	var kind := str(AnimalSim.AnimalType.keys()[an.animal_type]).capitalize()
	var lines: Array = []
	var owner_name := ""
	if an.owner_id >= 0:
		var o = main._find_agent(an.owner_id)
		owner_name = o.agent_name if o else ""
	if an.animal_type == AnimalSim.AnimalType.WOLF and owner_name != "":
		kind = "Dog"
		lines.append("%s's dog" % owner_name)
	elif an.animal_type == AnimalSim.AnimalType.HORSE and owner_name != "":
		lines.append("%s's horse%s" % [owner_name, ", ridden" if an.ridden else ""])
	elif an.home_settlement >= 0:
		lines.append("Kept at camp")
	elif an.group_id >= 0:
		lines.append("One of a %s" % ("pack" if an.animal_type == AnimalSim.AnimalType.WOLF else "herd"))
	lines.push_front("%s · %s" % [kind, STATE_WORDS.get(an.state, "about")])
	return {"kind": "animal", "title": kind, "lines": lines}

static func _building_at(main: Node, wp: Vector2) -> Dictionary:
	if main.settlement_renderer == null:
		return {}
	var best := {}
	var best_d := INF
	for sid in main.settlement_renderer.sites:
		for site in main.settlement_renderer.sites[sid]:
			if str(site["kind"]) in ["walls", "fields", "dwelling"]:
				continue   # big rings and plots: the ground underneath reads better
			var d: float = (site["pos"] as Vector2).distance_to(wp)
			if d < float(site["radius"]) and d < best_d:
				best_d = d
				best = site
	return best

static func _ground(main: Node, tp: Vector2) -> Dictionary:
	var tile: Dictionary = main.world.get_tile_f(tp.x, tp.y)
	if tile.is_empty():
		return {"kind": "ground", "title": "Open sea", "lines": []}
	var title := str(TILE_WORDS.get(int(tile["type"]), "Ground"))
	var lines: Array = []
	if bool(tile.get("river", false)):
		title = "River"
	if World.has_woods(tile):
		var g := float(tile.get("growth", 1.0))
		if bool(tile.get("tree_cut", false)):
			lines.append("Felled: stumps, a sapling soon")
		elif g < 0.3:
			lines.append("Seedlings coming up")
		elif g < 0.8:
			lines.append("Young trees")
		if bool(tile.get("planted", false)):
			lines.append("Planted by people")
	if float(tile.get("burnt", 0.0)) > 0.0:
		lines.append("Burnt: black snags")
	if bool(tile.get("flooded", false)):
		lines.append("Under floodwater")
	if float(tile.get("drought", 0.0)) > 0.0:
		lines.append("Parched by drought")
	if float(tile.get("blight", 0.0)) > 0.0:
		lines.append("Blighted")
	var food: float = main.world.food_of(tile)
	if int(tile["type"]) in [World.TileType.GRASS, World.TileType.WOODLAND, World.TileType.FOREST]:
		lines.append("Food: " + ("plenty" if food > 0.7 else ("some" if food > 0.3 else "picked bare")))
	if main.path_renderer and float(main.path_renderer.wear_at(int(tp.x), int(tp.y))) > 0.4:
		lines.append("A worn path")
	return {"kind": "ground", "title": title, "lines": lines}
