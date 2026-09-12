extends SceneTree

# Exercise harness. `tools/check.sh` only boots the project, which proves the
# scripts PARSE — it does not catch an invalid property access on a typed
# object, because GDScript reports that only when the line actually runs.
# This drives the simulation's code paths directly so those surface as errors.
#
#   godot --headless --script res://tools/smoke.gd

var _failures: int = 0
var _checks: int = 0

func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL: ", label)

func _init() -> void:
	print("=== smoke: building world ===")
	var world := World.new(1234)
	_check("world generated", world.tiles.size() == world.height)
	_check("row width", (world.tiles[0] as Array).size() == world.width)

	var concepts: Array = _load_json("res://data/concepts.json")
	var items_raw: Array = _load_json("res://data/items.json")
	var item_defs: Dictionary = {}
	for it in items_raw:
		item_defs[it["id"]] = it
	_check("concepts loaded", concepts.size() > 0)
	_check("items loaded", item_defs.size() > 0)

	var graph := ConceptGraph.new(concepts)
	var time_system := TimeSystem.new()
	var weather := WeatherSystem.new()
	var tile_items := TileItems.new()
	var settlements := SettlementSystem.new()
	var history := HistoryLog.new()
	var spatial := SpatialGrid.new()
	var ecology := EcologySystem.new()
	var disease := DiseaseSystem.new()
	var lineage := LineageTracker.new()
	var population := PopulationManager.new()
	var animal_sim := AnimalSim.new()
	animal_sim.spawn_wildlife(world)
	_check("wildlife spawned", animal_sim.animals.size() > 0)

	# ── agents ──────────────────────────────────────────────────────────────
	var agents: Array = []
	for p in world.get_spawn_points(24):
		agents.append(Agent.new(float(p["x"]), float(p["z"])))
	_check("agents spawned", agents.size() > 0)

	# Founders should start near each other, not scattered across the map.
	var max_sep := 0.0
	for a in agents:
		for b in agents:
			max_sep = maxf(max_sep, a.pos.distance_to(b.pos))
	_check("founders clustered (max separation %.1f < 40 tiles)" % max_sep, max_sep < 40.0)

	# ── give every concept to one agent so gated paths are reachable ────────
	var scholar: Agent = agents[0]
	for c in concepts:
		scholar.knowledge[str(c["id"])] = true

	# ── drive the full tick with every optional system attached ─────────────
	print("=== smoke: ticking ===")
	# Run at high speed so many in-game days elapse and the slow emergent
	# paths (settlement formation, vocations, journeys) actually execute.
	time_system.set_speed(20.0)
	var day := 1
	for step in range(6000):
		var gd := time_system.update(1.0 / 60.0)
		if gd <= 0.0:
			continue
		day = time_system.day
		world.day = day
		weather.update(gd, time_system.season)
		world.update_resources(gd, time_system.season.to_lower())
		world.update_depletion(gd)
		spatial.update(agents)
		for a in agents:
			if a.is_dead:
				continue
			a.tick(gd, world, agents, graph, weather.energy_drain_mult_at(a.pos.x, a.pos.y),
				   item_defs, time_system.season.to_lower(), time_system, day,
				   tile_items, settlements, spatial)
		settlements.tick(gd, agents, graph, day, history, spatial)
		ecology.tick(gd, world, agents, day, history)
		disease.tick(gd, agents, day, history, settlements)
		tile_items.tick_spoilage(gd, item_defs, 1.0)
		animal_sim.tick(gd, world)
		world.update_glaciers(gd, weather.temperature)
		world.decay_trade_traffic(day)
		world.update_nests(gd)

		var live_counts: Dictionary = {}
		for a in animal_sim.animals:
			if a.health <= 0.0:
				continue
		population.tick(gd, world, day, live_counts, history)
		population.get_spawn_requests()
		population.get_cull_requests()

		# Births, mirroring Main.gd — without them the population can only
		# decline and the run says nothing about whether the world is viable.
		var alive_now := 0
		for a in agents:
			if not a.is_dead and a.health > 0.0:
				alive_now += 1
		var capacity := world.get_carrying_capacity()
		for evt in graph.drain_birth_events():
			if alive_now >= capacity:
				break
			var bx := float(evt["x"])
			var bz := float(evt["z"])
			if not world.is_walkable(bx, bz):
				continue
			var child := Agent.new(bx, bz)
			if evt.has("parent_a_personality") and evt.has("parent_b_personality"):
				child.personality = Agent.inherit_personality(
					evt["parent_a_personality"] as Dictionary,
					evt["parent_b_personality"] as Dictionary)
			agents.append(child)
			alive_now += 1
		for evt in graph.drain_events():
			if str(evt.get("type", "")) == "discovery":
				lineage.record(str(evt["concept_id"]), agents[0], day)

		# Prune the dead so the array does not grow without bound.
		if step % 600 == 0:
			var living: Array = []
			for a in agents:
				if not a.is_dead and a.health > 0.0:
					living.append(a)
			agents = living

	print("  reached day ", day)
	_check("lineage recorded discoveries", lineage.all_discoveries().size() > 0)
	_check("population survived to the end of the run", _living(agents) > 0)

	# ── directly exercise the paths a short run may not reach ───────────────
	print("=== smoke: direct API exercise ===")

	# Ground item pickup: drop something under an agent and tick it.
	var picker: Agent = agents[0]
	var px := int(floor(picker.pos.x))
	var pz := int(floor(picker.pos.y))
	tile_items.drop(px, pz, "berries", 3.0)
	_check("tile has items before pickup", tile_items.has_items(px, pz))
	picker._item_defs = item_defs
	picker._tile_items = tile_items
	picker._pick_up_ground_items(world)
	_check("ground items picked up", picker.inventory.has("berries"))

	# Trade cargo loading reads Inventory.stacks — the exact bug boot missed.
	picker.inventory.add("wood", 6.0, item_defs)
	var cargo: Array = picker._load_trade_cargo()
	_check("trade cargo loaded", cargo.size() > 0)

	# Memory.
	picker._current_day = 5
	var food_before: int = (picker.memory["food_sources"] as Array).size()
	picker._remember_food_source(px + 40, pz + 40, World.TileType.GRASS)
	var food_after: Array = picker.memory["food_sources"]
	var found := false
	for e_v in food_after:
		var e: Dictionary = e_v
		if int(e["x"]) == px + 40 and int(e["z"]) == pz + 40:
			found = true
	_check("food source remembered (had %d)" % food_before, found)
	var danger_before: int = (picker.memory["dangers"] as Array).size()
	picker.remember_danger(px + 2, pz + 2, "wolf")
	_check("danger remembered", (picker.memory["dangers"] as Array).size() > danger_before
		or danger_before >= Agent.MEMORY_DANGER_CAP)
	_check("danger penalty applied", picker._danger_penalty(float(px + 2), float(pz + 2)) > 0.0)

	# Memory caps.
	for i in range(40):
		picker._remember_food_source(px + i, pz, World.TileType.GRASS)
	_check("food memory capped", (picker.memory["food_sources"] as Array).size() <= Agent.MEMORY_FOOD_CAP)
	for i in range(40):
		picker.remember_danger(px + i, pz, "wolf")
	_check("danger memory capped", (picker.memory["dangers"] as Array).size() <= Agent.MEMORY_DANGER_CAP)

	# Seasonal scoring.
	var grass_tile := {"type": World.TileType.GRASS}
	var stone_tile := {"type": World.TileType.STONE}
	_check("winter favours grass over stone",
		picker._seasonal_tile_score(grass_tile, "winter") > picker._seasonal_tile_score(stone_tile, "winter"))
	_check("summer is neutral",
		is_equal_approx(picker._seasonal_tile_score(stone_tile, "summer"), 1.0))

	# Vocation promotion.
	var voc: Agent = agents[1]
	voc.knowledge["organisation"] = true
	voc.knowledge["agriculture"] = true
	voc.personality["industriousness"] = 1.0
	voc.pos = scholar.pos
	var promoted := voc.maybe_promote_vocation(agents)
	_check("vocation promotion returns a bool", promoted or not promoted)
	if promoted:
		_check("promoted into a tier-2 vocation",
			int(Agent.get_tasks()[voc.task]["tier"]) == 2)

	# Family lookup.
	var parent: Agent = agents[2]
	var child: Agent = agents[3]
	child.parents.append(parent.agent_id)
	parent.children.append(child.agent_id)
	var fam: Dictionary = child.get_family(agents)
	_check("family resolves parent", (fam["parents"] as Array).size() == 1)

	# Zonal weather must actually differ across the map.
	var w_a := weather.energy_drain_mult_at(2.0, 2.0)
	var w_b := weather.energy_drain_mult_at(float(world.width - 3), float(world.height - 3))
	_check("weather query returns sane multiplier", w_a > 0.0 and w_b > 0.0)

	var alive := 0
	var vocationed := 0
	var infected := 0
	for a in agents:
		if not a.is_dead and a.health > 0.0:
			alive += 1
		if not a.task.is_empty():
			vocationed += 1
		if a.infected:
			infected += 1
	print("  alive=%d/%d  with-vocation=%d  infected=%d  settlements=%d  discoveries=%d"
		% [alive, agents.size(), vocationed, infected,
		   settlements.get_settlements().size(), graph.get_discovered_concepts().size()])

	print("  animals=%d  outbreak=%s" % [animal_sim.animals.size(), str(disease.outbreak_active)])
	print("=== smoke: %d checks, %d failures ===" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

func _living(agents: Array) -> int:
	var n := 0
	for a in agents:
		if not a.is_dead and a.health > 0.0:
			n += 1
	return n

func _load_json(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var json := JSON.new()
	var err := json.parse(f.get_as_text())
	f.close()
	if err != OK:
		return []
	return json.data as Array
