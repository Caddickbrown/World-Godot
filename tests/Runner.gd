extends Node
## Test runner: unit checks on the simulation, then integration checks that boot
## Main.tscn and drive the two views. Run headless via tests/run_ci.sh.
## Every behaviour added or fixed gets a check here (AGENTS.md).

var _checks := 0
var _failures := 0

func check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL: ", label)

func _ready() -> void:
	seed(20261014)
	print("== unit")
	_test_seasons()
	_test_world_surface_and_capacity()
	_test_conflict_needs_rival_settlements_and_hunger()
	_test_thoughts()
	_test_names_unique()
	_test_wanderer_movement()
	_test_idea_ledger()
	_test_story_keeper()
	_test_hunches()
	_test_island_and_heightfield()
	_test_wildlife_stays_on_land()
	_test_families_and_fire()
	_test_teaching_hunting_moving_grief()
	_test_larder()
	_test_living_woods()
	_test_discovery_conditions()
	_run_suites()
	print("== integration")
	await _test_main_views()
	print("== %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

## Feature suites: every tests/suites/*.gd is a RefCounted with
## `func run(t) -> void` that calls t.check(label, ok) (and may use the
## helpers here: t._adult(x, z), t._graph(), t._first_tile(...)). New areas
## add a file there instead of editing this one.
func _run_suites() -> void:
	var dir := DirAccess.open("res://tests/suites")
	if dir == null:
		return
	var names: Array = []
	for f in dir.get_files():
		if f.ends_with(".gd"):
			names.append(f)
	names.sort()
	for f in names:
		print("== suite ", f)
		var suite = load("res://tests/suites/" + f).new()
		suite.run(self)

# ── Unit ─────────────────────────────────────────────────────────────────────

func _test_seasons() -> void:
	check("day 1 is spring", TimeSystem.season_for_day(1) == "Spring")
	check("day 7 is still spring", TimeSystem.season_for_day(TimeSystem.SEASON_DAYS) == "Spring")
	check("day 8 is summer", TimeSystem.season_for_day(TimeSystem.SEASON_DAYS + 1) == "Summer")
	check("winter comes fourth", TimeSystem.season_for_day(3 * TimeSystem.SEASON_DAYS + 1) == "Winter")
	check("the year turns back to spring", TimeSystem.season_for_day(4 * TimeSystem.SEASON_DAYS + 1) == "Spring")
	var w := World.new(7)
	w.day = TimeSystem.SEASON_DAYS + 1
	check("World.get_season agrees with TimeSystem", w.get_season() == "summer")
	check("a new clock starts in spring", TimeSystem.new().season == "Spring")

func _test_world_surface_and_capacity() -> void:
	var w := World.new(42)
	var tile: Dictionary = w.get_tile(10, 10)
	check("surface_y is elevation x HEIGHT_SCALE",
		is_equal_approx(w.surface_y(10.5, 10.5), float(tile["elevation"]) * World.HEIGHT_SCALE))
	check("surface_y off the map is 0", w.surface_y(-5.0, -5.0) == 0.0)
	check("capacity never exceeds max_population", w.get_carrying_capacity() <= w.max_population)
	w.max_population = 60
	w._capacity_cache = -1
	check("capacity follows a lowered max_population", w.get_carrying_capacity() == 60)

func _test_conflict_needs_rival_settlements_and_hunger() -> void:
	var a := Agent.new(10.0, 10.0)
	var b := Agent.new(10.5, 10.0)
	var history := HistoryLog.new()
	var conflict := ConflictSystem.new()
	var settlements := SettlementSystem.new()
	conflict.settlement_system = settlements
	a.needs["hunger"] = 0.1
	b.needs["hunger"] = 0.1
	conflict._delta = 1000.0  # make the roll certain so only the rules decide
	conflict._check_agent_conflict(a, b, 1, history)
	check("people with no settlement never clash", not conflict.is_in_conflict(a))

	var s1 := SettlementSystem.Settlement.new()
	s1.id = 1
	s1.member_ids = [a.agent_id, b.agent_id]
	settlements.settlements = [s1]
	settlements._reindex_members()
	conflict._check_agent_conflict(a, b, 1, history)
	check("neighbours from one settlement never clash", not conflict.is_in_conflict(a))

	var s2 := SettlementSystem.Settlement.new()
	s2.id = 2
	s2.member_ids = [b.agent_id]
	s1.member_ids = [a.agent_id]
	settlements.settlements = [s1, s2]
	settlements._reindex_members()
	a.needs["hunger"] = 0.9
	b.needs["hunger"] = 0.9
	conflict._check_agent_conflict(a, b, 1, history)
	check("well-fed rivals don't clash", not conflict.is_in_conflict(a))
	b.needs["hunger"] = 0.1
	conflict._check_agent_conflict(a, b, 1, history)
	check("hungry rivals side by side clash", conflict.is_in_conflict(a) and conflict.is_in_conflict(b))

	# The clash chance is per second, not per frame.
	var c := Agent.new(20.0, 20.0)
	var d := Agent.new(20.5, 20.0)
	c.needs["hunger"] = 0.1
	s1.member_ids = [a.agent_id, c.agent_id]
	s2.member_ids = [b.agent_id, d.agent_id]
	settlements._reindex_members()
	conflict._delta = 1.0 / 60.0
	var clashed_frames := 0
	for i in 60:
		c.set_meta("conflict_cooldown", 0.0)
		d.set_meta("conflict_cooldown", 0.0)
		conflict._check_agent_conflict(c, d, 1, history)
		if conflict.is_in_conflict(c):
			clashed_frames += 1
	check("one second of frames gives about 0.2 clashes, not 12 (got %d)" % clashed_frames, clashed_frames <= 3)

func _test_names_unique() -> void:
	var seen: Dictionary = {}
	var dupes := 0
	for i in 600:
		var n := Agent._random_name()
		if seen.has(n): dupes += 1
		seen[n] = true
	check("no two people share a name (%d repeats in 600)" % dupes, dupes == 0)

func _test_thoughts() -> void:
	var a := Agent.new(5.0, 5.0)
	a.age = a.max_age * 0.4
	a._update_life_stage()
	a.needs["hunger"] = 0.1
	check("a starving person thinks about food", AgentThoughts.thought(a).contains("hungry"))
	a.needs["hunger"] = 0.9
	a.state = Agent.State.SLEEPING
	check("a sleeper is asleep", AgentThoughts.doing(a) == "asleep")
	a.needs["hunger"] = 0.1
	check("a hungry sleeper dreams, not frets", AgentThoughts.thought(a) == "Zzz…")
	a.state = Agent.State.WANDERING
	a.is_dead = true
	a.death_cause = "old_age"
	check("the dead have no thoughts", AgentThoughts.thought(a).is_empty())
	check("death cause reads as words", AgentThoughts.doing(a) == "gone (old age)")

func _test_wanderer_movement() -> void:
	var w := World.new(1234)
	var wand := Wanderer.new()
	add_child(wand)
	wand.world = w
	# Find walkable ground with water (or rock) directly east of it.
	var shore := Vector2(-1, -1)
	for z in range(2, w.height - 2):
		for x in range(2, w.width - 2):
			if w.is_walkable(x + 0.5, z + 0.5) and not w.is_walkable(x + 1.5, z + 0.5):
				shore = Vector2(x + 0.5, z + 0.5)
				break
		if shore.x >= 0:
			break
	check("found a shore to test on", shore.x >= 0)
	wand.place_at(shore)
	wand.cam_yaw = 0.0  # camera looks toward -z; the stick's +x is world +x
	for i in 60:
		wand.step(1.0 / 30.0, Vector2(1, 0), false)
	check("the wanderer can't walk into the sea or up a cliff", w.is_walkable(wand.tile_pos.x, wand.tile_pos.y))
	check("...and stops at the water's edge", wand.tile_pos.x < shore.x + 0.5)
	var before := wand.tile_pos
	for i in 30:
		wand.step(1.0 / 30.0, Vector2(-1, 0), true)
	check("running away from the shore covers ground", wand.tile_pos.distance_to(before) > 2.0)

	var deep := Vector2(-1, -1)
	for z in w.height:
		for x in w.width:
			if int(w.get_tile(x, z)["type"]) == World.TileType.DEEP_WATER:
				deep = Vector2(x + 0.5, z + 0.5)
	if deep.x >= 0:
		wand.place_at(deep)
		check("placing in the sea lands on dry ground", w.is_walkable(wand.tile_pos.x, wand.tile_pos.y))
	wand.queue_free()

const TEST_ALBUM := "user://test_album.json"

func _adult(x: float = 10.0, z: float = 10.0) -> Agent:
	var a := Agent.new(x, z)
	a.age = a.max_age * 0.4
	a._update_life_stage()
	a.is_adult = true
	return a

func _graph() -> ConceptGraph:
	var f := FileAccess.open("res://data/concepts.json", FileAccess.READ)
	return ConceptGraph.new(JSON.parse_string(f.get_as_text()))

func _test_idea_ledger() -> void:
	var g := _graph()
	var ledger := IdeaLedger.new()
	ledger.setup(g.concepts)
	var people: Array = []
	for i in 10:
		people.append(_adult())
	ledger.recount(people, 1)
	check("an idea nobody has is a seed", ledger.stage_of("fire") == IdeaLedger.Stage.SEED)
	people[0].knowledge["fire"] = true
	ledger.recount(people, 1)
	check("one holder in ten: sprouting", ledger.stage_of("fire") == IdeaLedger.Stage.SPROUT)
	for i in 5:
		people[i].knowledge["fire"] = true
	ledger.recount(people, 2)
	check("half the world: in bloom", ledger.stage_of("fire") == IdeaLedger.Stage.BLOOM)
	people[0].knowledge["herbalism"] = true
	ledger.recount(people, 2)
	people[0].is_dead = true
	people[0].health = 0.0
	var changes: Array = ledger.recount(people, 3, [people[0]])
	check("the last holder dying wilts the idea", ledger.stage_of("herbalism") == IdeaLedger.Stage.WILTED)
	var named := changes.filter(func(c): return c["id"] == "herbalism")
	check("...and the ledger names who took it with them", not named.is_empty() and named[0]["last_holder"] == people[0].agent_name)
	check("the dead don't count as holders", int(ledger.ideas["fire"]["holders"]) == 4)
	var how: Dictionary = ledger.note_discovery("herbalism", "Pip", 5)
	check("finding a lost idea counts as rediscovery", how["refound"] and not how["first"])

func _test_story_keeper() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_ALBUM))
	var g := _graph()
	var a := _adult(10, 10)
	var b := _adult(11, 10)
	var people: Array = [a, b]
	var keeper := StoryKeeper.new()
	var seen := [false]
	keeper.witness_fn = func(_p, _ids): return seen[0]
	keeper.setup(g, people, TEST_ALBUM)
	check("a new world opens the chronicle", keeper.chronicle.size() == 1)

	# Read-only: a full tick must leave everyone exactly as they were.
	a.bonded_partner_id = b.agent_id
	b.bonded_partner_id = a.agent_id
	a.knowledge["fire"] = true
	var snap := func(x: Agent) -> Array:
		return [x.pos, x.target, x.state, x.needs.duplicate(), x.knowledge.duplicate(), x.bonded_partner_id,
			x.health, x.age, x.speech_bubble, x.get_meta_list()]
	var before := [snap.call(a), snap.call(b)]
	keeper.tick(StoryKeeper.RECOUNT_INTERVAL + 0.1, people, 2, 10.0, 2)
	check("the story never changes the people it watches", [snap.call(a), snap.call(b)] == before)
	var pair_lines := keeper.chronicle.filter(func(e): return e["text"].contains("paired up"))
	check("a pairing is noticed once", pair_lines.size() == 1)
	keeper.tick(0.1, people, 2, 10.0, 2)
	check("...and not told twice", keeper.chronicle.filter(func(e): return e["text"].contains("paired up")).size() == 1)
	check("both lives remember the partner", keeper.life_of(a).partner == b.agent_name and keeper.life_of(b).partner == a.agent_name)
	check("unwatched pairing isn't in the album", not keeper.moments.is_unlocked("pairing"))

	seen[0] = true
	keeper.on_discovery(a, "honey_gathering")
	check("a first discovery is told", keeper.chronicle[-1]["text"].contains("first to think of"))
	check("...goes in their life story", "honey_gathering" in keeper.life_of(a).firsts)
	check("...and, watched, unlocks a moment", keeper.moments.is_unlocked("first_idea"))
	keeper.on_discovery(b, "honey_gathering")
	check("a second discoverer isn't 'first'", not keeper.chronicle[-1]["text"].contains(b.agent_name + " was the first"))

	for i in StoryKeeper.TEACHER_THRESHOLD:
		keeper.on_spread(_adult(), a, "honey_gathering")
	check("teaching ten people is a moment", keeper.moments.is_unlocked("teacher"))
	check("...and counted in their life", keeper.life_of(a).total_taught() == StoryKeeper.TEACHER_THRESHOLD)

	a.is_dead = true
	a.death_cause = "old_age"
	keeper.on_death(a)
	var line: String = keeper.life_of(a).last_line
	check("a life ends on a line naming what they're remembered for (%s)" % line,
		line.begins_with(a.agent_name + ", who first thought of") and StoryKeeper.DEATH_PHRASES["old_age"].any(func(ph): return line.contains(ph)))
	check("the dead keep their story", not keeper.life_of(a).alive() and keeper.lives.has(a.agent_id))

	# The album persists across worlds.
	var again := StoryKeeper.new()
	again.setup(g, [], TEST_ALBUM)
	check("the album survives a new world", again.moments.is_unlocked("first_idea") and again.moments.is_unlocked("teacher"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_ALBUM))

func _test_hunches() -> void:
	var g := _graph()
	var ledger := IdeaLedger.new()
	ledger.setup(g.concepts)
	var people: Array = []
	for i in 6:
		var p := _adult()
		p.knowledge["fire"] = true   # cooking, pottery... become possible
		people.append(p)
	ledger.recount(people, 1)
	var h := Hunches.new()
	var made: Array = h.offer(people, ledger, g.concepts, 1)
	var first_to := made.filter(func(x): return x["kind"] == "first_to")
	check("the game asks who'll think of something first", not first_to.is_empty())
	if first_to.is_empty():
		return
	var q: Dictionary = first_to[0]
	check("...offering real candidates and 'someone else'", (q["options"] as Array).size() == 4 and Hunches.SOMEONE_ELSE in q["options"])
	h.pick(int(q["id"]), q["options"][0])
	var done: Array = h.on_discovery(q["concept"], q["options"][0], false, true, 2)
	check("a right call adds a glimmer", done.size() == 1 and done[0]["correct"] and h.glimmers == 1)
	check("open hunches are capped", h.offer(people, ledger, g.concepts, 2).size() + h.open.size() <= Hunches.MAX_OPEN)

func _test_island_and_heightfield() -> void:
	var w := World.new(7)
	var edge_land := 0
	for i in w.width:
		for t in [w.get_tile(i, 0), w.get_tile(i, w.height - 1), w.get_tile(0, i), w.get_tile(w.width - 1, i)]:
			if not (int(t["type"]) in [World.TileType.WATER, World.TileType.DEEP_WATER]):
				edge_land += 1
	check("the world is an island: sea all round the edge (%d land edge tiles)" % edge_land, edge_land == 0)
	var hf := Heightfield.new().build(w)
	w.heightfield = hf
	var wet_land := 0
	var dry_sea := 0
	for z in w.height:
		for x in w.width:
			var t := int(w.get_tile(x, z)["type"])
			var h := hf.height_at_tile(x + 0.5, z + 0.5)
			if t in [World.TileType.WATER, World.TileType.DEEP_WATER] and h >= 0.0:
				dry_sea += 1
			elif w.is_walkable(x + 0.5, z + 0.5) and h <= 0.0:
				wet_land += 1
	check("no sea tile stands above the water (%d)" % dry_sea, dry_sea == 0)
	check("no walkable tile is under the sea (%d)" % wet_land, wet_land == 0)
	check("surface_y follows the smooth ground", is_equal_approx(w.surface_y(40.5, 40.5), maxf(hf.height_at_tile(40.5, 40.5), 0.0)))

	var env := EnvironmentRenderer.new()
	add_child(env)
	env.setup(w)
	var tree_tile := Vector2i(-1, -1)
	for z in w.height:
		for x in w.width:
			if env.tree_count_on(x, z) > 0 and World.has_woods(w.get_tile(x, z)):   # felling is for woods
				tree_tile = Vector2i(x, z)
				break
		if tree_tile.x >= 0:
			break
	check("the woods have trees", tree_tile.x >= 0)
	if tree_tile.x >= 0:
		var tile := w.get_tile(tree_tile.x, tree_tile.y)
		tile["tree_cut"] = true
		env.refresh_tile(tree_tile.x, tree_tile.y)
		# (The headless renderer keeps no MultiMesh data, so ask the flora.)
		check("a felled tree disappears", not env.trees_shown_on(tree_tile.x, tree_tile.y))
		tile["tree_cut"] = false
		env.refresh_tile(tree_tile.x, tree_tile.y)
		check("...and grows back", env.trees_shown_on(tree_tile.x, tree_tile.y))
	env.queue_free()

func _test_wildlife_stays_on_land() -> void:
	var w := World.new(7)
	var sim := AnimalSim.new()
	sim.spawn_wildlife(w)
	for i in 1800:  # a minute of animal life at 30 fps
		sim.tick(1.0 / 30.0, w)
	var wet := 0
	var cornered := 0
	var alive := 0
	for a in sim.animals:
		if a.state == AnimalSim.AnimalState.DEAD or a.animal_type == AnimalSim.AnimalType.EAGLE:
			continue
		alive += 1
		if not w.is_walkable(a.pos.x, a.pos.y): wet += 1
		if a.pos.x < 32.0 and a.pos.y < 32.0: cornered += 1
	check("land animals stay on land (%d of %d in the sea)" % [wet, alive], wet == 0)
	check("...and don't all drift to the old 32-tile corner (%d of %d)" % [cornered, alive], cornered < alive / 2)

func _test_families_and_fire() -> void:
	var w := World.new(99)
	var pts: Array = w.get_spawn_points(3)
	var graph := ConceptGraph.new([])
	var parent := _adult(float(pts[0]["x"]), float(pts[0]["z"]))
	var child := Agent.new(parent.pos.x, parent.pos.y)
	child.age = child.max_age * 0.15
	child._update_life_stage()
	child.parents = [parent.agent_id]
	parent.children = [child.agent_id]
	# A child far from its parent heads back.
	child.pos = parent.pos + Vector2(6, 0)
	if not w.is_walkable(child.pos.x, child.pos.y):
		child.pos = parent.pos + Vector2(0, 1)
	var ts := TimeSystem.new()
	ts.game_time = TimeSystem.DAY_LENGTH * (11.0 / 24.0)  # midday
	child._decide_action(w, [parent, child], graph, ts)
	check("a straying child heads back to a parent", child.target.distance_to(parent.pos) < 2.0)
	# A hungry child is fed by a parent with food to spare.
	child.pos = parent.pos + Vector2(0.5, 0)
	child.needs["hunger"] = 0.2
	parent.needs["hunger"] = 0.9
	parent.social_timer = 0.0
	parent._try_socialise(0.1, [parent, child], graph)
	check("a parent feeds a hungry child", child.needs["hunger"] > 0.3 and parent.fed_children == 1)

	# Dusk: a settled adult goes to sit by the hearth, and sits.
	var st := SettlementSystem.new()
	var s1 := SettlementSystem.Settlement.new()
	s1.id = 1
	s1.centre = parent.pos
	s1.member_ids = [parent.agent_id]
	st.settlements = [s1]
	st._reindex_members()
	parent._settlement_system = st
	ts.game_time = TimeSystem.DAY_LENGTH * (18.5 / 24.0)
	parent.pos = s1.centre + Vector2(5, 0)
	parent._decide_action(w, [parent], graph, ts)
	check("at dusk a settled person walks to the fire", parent.state == Agent.State.WANDERING and parent.target.distance_to(s1.centre) <= Agent.FIRE_RING_MAX + 0.1)
	parent.pos = parent.target
	parent._decide_action(w, [parent], graph, ts)
	check("...and sits down round it", parent.state == Agent.State.SOCIALIZING)
	parent.tick(0.1, w, [parent], graph, 1.0, {}, "spring", ts, 1, null, st)
	check("...at the fire", parent.at_fire)
	ts.game_time = TimeSystem.DAY_LENGTH * (21.0 / 24.0)
	parent.tick(0.1, w, [parent], graph, 1.0, {}, "spring", ts, 1, null, st)
	check("night ends the evening at the fire", not parent.at_fire)

func _test_teaching_hunting_moving_grief() -> void:
	var g := _graph()
	# Teaching: with every allowed transfer made certain, only the rules decide.
	var old_pace := ConceptGraph.spread_pace
	ConceptGraph.spread_pace = 1000.0
	var adult := _adult()
	var infant := Agent.new(10, 10)
	infant._update_life_stage()
	adult.knowledge["pottery"] = true      # era 2: a craft
	adult.knowledge["fire"] = true         # era 1: anyone can copy it
	g.try_spread(adult, infant, 1.0)
	check("an infant picks up a simple idea", infant.knowledge.has("fire"))
	check("...but not a craft", not infant.knowledge.has("pottery"))
	var child := Agent.new(10, 10)
	child.age = child.max_age * 0.15
	child._update_life_stage()
	child.knowledge["pottery"] = true
	var learner := _adult()
	g.try_spread(child, learner, 1.0)
	check("a child can't teach a craft", not learner.knowledge.has("pottery"))
	g.try_spread(adult, learner, 1.0)
	check("an adult can", learner.knowledge.has("pottery"))
	ConceptGraph.spread_pace = old_pace

	# Hunting: a hungry hunter next to a deer brings it down and shares it.
	var w := World.new(99)
	var pts: Array = w.get_spawn_points(2)
	var hunter := _adult(float(pts[0]["x"]), float(pts[0]["z"]))
	hunter.knowledge["hunting"] = true
	hunter.needs["hunger"] = 0.3
	var friend := _adult(hunter.pos.x + 1.0, hunter.pos.y)
	friend.needs["hunger"] = 0.3
	var sim := AnimalSim.new()
	var deer := sim.spawn_one(AnimalSim.AnimalType.DEER, hunter.pos.x + 0.5, hunter.pos.y)
	var hunts := HuntingSystem.new()
	var kills: Array = hunts.tick(0.1, [hunter, friend], sim)
	check("a hungry hunter brings down a deer", kills.size() == 1 and deer.state == AnimalSim.AnimalState.DEAD)
	check("...eats", hunter.needs["hunger"] > 0.9)
	check("...and shares it", friend.needs["hunger"] > 0.5 and int(kills[0]["shared"]) == 1)
	var fed := _adult(hunter.pos.x, hunter.pos.y)
	fed.knowledge["hunting"] = true
	fed.needs["hunger"] = 0.9
	sim.spawn_one(AnimalSim.AnimalType.DEER, fed.pos.x + 0.5, fed.pos.y)
	check("a well-fed hunter leaves the deer alone", HuntingSystem.new().tick(0.1, [fed], sim).is_empty())

	# Migration: a camp on stripped land moves, and keeps its people.
	var ss := SettlementSystem.new()
	ss.world = w
	var camp := SettlementSystem.Settlement.new()
	camp.id = 9
	camp.centre = hunter.pos
	camp.member_ids = [hunter.agent_id, friend.agent_id]
	ss.settlements = [camp]
	ss._reindex_members()
	for dz in range(-6, 7):
		for dx in range(-6, 7):
			var t := w.get_tile(int(camp.centre.x) + dx, int(camp.centre.y) + dz)
			if not t.is_empty(): w.set_food(t, 0.0)
	var start := camp.centre
	var hist := HistoryLog.new()
	for d in range(1, 4):
		ss._last_eval_day = d
		ss._check_migration(d, hist)
	check("a camp on stripped land moves (%.1f tiles)" % camp.centre.distance_to(start), camp.centre.distance_to(start) >= SettlementSystem.MOVE_MIN - 0.1)
	check("...and says so", hist.entries.any(func(e): return str(e["msg"]).contains("packed up and moved")))
	ss._update_membership([hunter, friend])
	check("...keeping its people while they walk", camp.member_ids.size() == 2)
	hunter.pos = camp.centre
	friend.pos = camp.centre + Vector2(1, 0)
	ss._update_membership([hunter, friend])
	check("...and settling once they arrive", camp.moving_until_day == -1 and camp.member_ids.size() == 2)

	# Grief.
	var widow := _adult()
	var base := widow.speed_mult
	widow.grieve("Oru")
	check("grief slows them", widow.speed_mult < base)
	check("...and fills their thoughts", AgentThoughts.thought(widow).contains("Oru"))
	var other := _adult()
	other.reproduction_cooldown = 0.0
	widow.reproduction_cooldown = 0.0
	var births := g.birth_events.size()
	widow._try_reproduce(other, g)
	check("...and nobody starts a family while grieving", g.birth_events.size() == births)

func _first_tile(w: World, types: Array, need_trees: bool = false, env: EnvironmentRenderer = null) -> Vector2i:
	for z in range(4, w.height - 4):
		for x in range(4, w.width - 4):
			var t := w.get_tile(x, z)
			if int(t["type"]) in types and (not need_trees or env.tree_count_on(x, z) > 0):
				return Vector2i(x, z)
	return Vector2i(-1, -1)

func _test_living_woods() -> void:
	var w := World.new(7)
	w.heightfield = Heightfield.new().build(w)
	var fs := ForestSystem.new()

	# Growth: a seedling grows with the season, and fastest in spring.
	var wood := _first_tile(w, [World.TileType.WOODLAND])
	var wt := w.get_tile(wood.x, wood.y)
	wt["growth"] = 0.0
	w.mark_growing(wood.x, wood.y)
	w.drain_flora_dirty()
	for i in ForestSystem.STRIPE_COUNT:
		fs._grow(TimeSystem.DAY_LENGTH * 0.5 / ForestSystem.STRIPE_COUNT, w, "spring")
	var spring_g: float = wt["growth"]
	check("a seedling grows (%.2f after half a spring day)" % spring_g, spring_g > 0.2 and spring_g < 0.5)
	check("...and the flora is told it changed size", w.flora_dirty.has(wood))
	wt["growth"] = 0.0
	w.mark_growing(wood.x, wood.y)
	for i in ForestSystem.STRIPE_COUNT:
		fs._grow(TimeSystem.DAY_LENGTH * 0.5 / ForestSystem.STRIPE_COUNT, w, "winter")
	check("...barely at all in winter (%.3f)" % wt["growth"], float(wt["growth"]) < 0.05)
	wt["growth"] = 1.0

	# Felling: a woodcutter from a camp short of timber fells a grown tree.
	var forest := _first_tile(w, [World.TileType.FOREST])
	var ft := w.get_tile(forest.x, forest.y)
	var axe := _adult(forest.x + 0.5, forest.y + 0.5)
	axe.knowledge["woodcutting"] = true
	axe.needs["hunger"] = 0.9
	var ss := SettlementSystem.new()
	var camp := SettlementSystem.Settlement.new()
	camp.id = 4
	camp.centre = Vector2(forest.x + 2.5, forest.y + 0.5)
	var idle := _adult(forest.x + 0.5, forest.y + 0.5)
	idle.needs["hunger"] = 0.9
	camp.member_ids = [axe.agent_id, idle.agent_id]
	ss.settlements = [camp]
	ss._reindex_members()
	check("no one fells a tree without the idea", fs.tick(0.1, w, [idle], ss, "summer", 1).is_empty())
	var evts: Array = fs.tick(0.1, w, [axe], ss, "summer", 1)
	if evts.is_empty():
		evts = fs.tick(0.1, w, [axe], ss, "summer", 1)
	check("a woodcutter fells a grown tree near camp", not evts.is_empty() and str(evts[0]["kind"]) == "felled")
	check("...leaving a stump", bool(ft["tree_cut"]) and float(ft["growth"]) == 0.0)
	check("...and timber at the camp (%.0f)" % camp.wood_store, camp.wood_store >= ForestSystem.TIMBER_PER_TREE)
	w.update_cut_trees(World.STUMP_SECONDS * 1.3)
	check("the stump sends up a sapling, not a grown tree", not bool(ft["tree_cut"]) and float(ft["growth"]) < 0.1)

	# Forestry: fell and replant; plant a grove on bare ground near home.
	ft["growth"] = 1.0
	camp.wood_store = 0.0
	axe.knowledge["forestry"] = true
	fs._rest.clear()
	evts = fs.tick(0.1, w, [axe], ss, "summer", 1)
	if evts.is_empty():
		evts = fs.tick(0.1, w, [axe], ss, "summer", 1)
	var fell_tile: Vector2i = evts[0]["tile"] if not evts.is_empty() else Vector2i(-1, -1)
	var rt := w.get_tile(fell_tile.x, fell_tile.y)
	check("someone who knows forestry replants what they fell",
		not evts.is_empty() and str(evts[0]["kind"]) == "replanted" and not bool(rt["tree_cut"]) and bool(rt["planted"]))
	var meadow := _first_tile(w, [World.TileType.GRASS])
	for dz in range(-8, 9):
		for dx in range(-8, 9):
			var t := w.get_tile(meadow.x + dx, meadow.y + dz)
			if not t.is_empty() and int(t["type"]) in [World.TileType.WOODLAND, World.TileType.FOREST]:
				t["type"] = World.TileType.GRASS
	camp.centre = Vector2(meadow.x + 0.5, meadow.y + 0.5)
	camp.wood_store = 999.0
	var planter := _adult(meadow.x + 4.5, meadow.y + 0.5)
	planter.knowledge["forestry"] = true
	planter.needs["hunger"] = 0.9
	camp.member_ids = [planter.agent_id]
	ss._reindex_members()
	var planted := false
	for i in 4:
		for e in fs.tick(0.1, w, [planter], ss, "summer", 1):
			if str(e["kind"]) == "planted":
				var pt := w.get_tile(e["tile"].x, e["tile"].y)
				planted = int(pt["type"]) == World.TileType.WOODLAND and bool(pt["planted"]) and float(pt["growth"]) < 0.1
		if planted: break
		var job: Dictionary = fs._job.get(planter.agent_id, {})
		if not job.is_empty():
			planter.pos = Vector2(job["tile"].x + 0.5, job["tile"].y + 0.5)
	check("...and plants a grove on bare ground near home", planted)

	# Timber builds hamlets.
	var hamlet := SettlementSystem.Settlement.new()
	hamlet.member_ids = [1, 2, 3, 4, 5]
	ss.settlements = [hamlet]
	var hist := HistoryLog.new()
	ss._check_tier_upgrades([], hist, 1)
	check("a camp without timber stays tents", hamlet.tier == 0)
	hamlet.wood_store = SettlementSystem.HAMLET_TIMBER + 1.0
	ss._check_tier_upgrades([], hist, 1)
	check("...and with it builds huts, spending the timber", hamlet.tier == 1 and hamlet.wood_store < 2.0)

	# Fire: a wood burns to snags, which fall a day later.
	var env := EnvironmentRenderer.new()
	add_child(env)
	env.setup(w)
	var burn := _first_tile(w, [World.TileType.FOREST], true, env)
	var fire := FireSystem.new()
	var bkey := "%d,%d" % [burn.x, burn.y]
	fire._fires[bkey] = 0.0
	fire._extinguish(bkey, w, 0.0, 1, HistoryLog.new())
	var bt := w.get_tile(burn.x, burn.y)
	env.refresh_tile(burn.x, burn.y)
	check("a burnt wood stands as black snags", float(bt["burnt"]) > 0.0 and env.snags_shown_on(burn.x, burn.y) > 0 \
		and not env.trees_shown_on(burn.x, burn.y))
	for i in ForestSystem.STRIPE_COUNT:
		fs._grow(FireSystem.BURNT_SECONDS * 1.2 / ForestSystem.STRIPE_COUNT, w, "summer")
	env.refresh_tile(burn.x, burn.y)
	check("...which fall, leaving open ground for the woods to seed", float(bt["burnt"]) == 0.0 and env.snags_shown_on(burn.x, burn.y) == 0)

	# The flora draws what the tile is now: stumps, and seedlings small.
	var stump := _first_tile(w, [World.TileType.FOREST], true, env)
	w.cut_tree(stump.x, stump.y)
	env.refresh_tile(stump.x, stump.y)
	check("a felled tile shows stumps, not trees", env.stumps_shown_on(stump.x, stump.y) > 0 and not env.trees_shown_on(stump.x, stump.y))
	env.queue_free()

func _test_discovery_conditions() -> void:
	var w := World.new(7)
	var g := _graph()
	var a := _adult(10, 10)
	var inland := Vector2i(-1, -1)
	var shore := Vector2i(-1, -1)
	var by_rock := Vector2i(-1, -1)
	var far_rock := Vector2i(-1, -1)
	for z in range(4, w.height - 4):
		for x in range(4, w.width - 4):
			var t := w.get_tile(x, z)
			if not w.is_walkable(x + 0.5, z + 0.5):
				continue
			var water := ConceptGraph._type_within(w, t, "WATER", 1)
			var rock := ConceptGraph._type_within(w, t, ["STONE", "MOUNTAIN"], ConceptGraph.NEAR_TILES)
			if water and shore.x < 0: shore = Vector2i(x, z)
			if not water and not ConceptGraph._type_within(w, t, "WATER", 3) and inland.x < 0: inland = Vector2i(x, z)
			if rock and int(t["type"]) != World.TileType.STONE and by_rock.x < 0: by_rock = Vector2i(x, z)
			if not rock and far_rock.x < 0: far_rock = Vector2i(x, z)
	var sail: Dictionary = g.concepts["sailing"]
	var stone: Dictionary = g.concepts["stone_tools"]
	check("sailing is thought of by the water", g._conditions_met(a, w.get_tile(shore.x, shore.y), sail, w, []))
	check("...not far inland (the condition used to be ignored)", not g._conditions_met(a, w.get_tile(inland.x, inland.y), sail, w, []))
	check("stone tools come to someone near rock, not only on it", g._conditions_met(a, w.get_tile(by_rock.x, by_rock.y), stone, w, []))
	check("...but not in the middle of a meadow", not g._conditions_met(a, w.get_tile(far_rock.x, far_rock.y), stone, w, []))
	var t0 := w.get_tile(shore.x, shore.y)
	check("'has_concept' conditions are honoured", not g._conditions_met(a, t0,
		{"discovery_conditions": [{"type": "has_concept", "value": "writing"}]}, w, []))

func _test_larder() -> void:
	var a := _adult(40, 40)
	var b := _adult(41, 40)
	var ss := SettlementSystem.new()
	var camp := SettlementSystem.Settlement.new()
	camp.id = 3
	camp.name = "Testhold"
	camp.centre = Vector2(40, 40)
	camp.member_ids = [a.agent_id, b.agent_id]
	ss.settlements = [camp]
	var hist := HistoryLog.new()
	ss._tick_resources(1.0, [a, b], hist, 1)
	check("a camp's store doesn't fill itself", camp.food_store == 0.0)
	a.needs["hunger"] = 0.9
	a.carrying_food = 0.5
	b.needs["hunger"] = 0.9
	ss._tick_resources(0.01, [a, b], hist, 1)
	check("surplus carried home goes into the store", is_equal_approx(a.carrying_food, 0.0) and camp.food_store > 0.45)
	b.needs["hunger"] = 0.1
	ss._tick_resources(0.01, [a, b], hist, 1)
	check("someone hungry at home eats from it", b.needs["hunger"] > 0.45 and camp.food_store < 0.15)
	check("...and the chronicle notices the first larder", hist.entries.any(func(e): return str(e["msg"]).contains("first larder")))
	b.pos = Vector2(60, 60)
	b.needs["hunger"] = 0.1
	camp.food_store = 1.0
	ss._tick_resources(0.01, [a, b], hist, 1)
	check("...but only when they're home", b.needs["hunger"] < 0.15)
	camp.food_store = 1.0
	ss._tick_resources(TimeSystem.DAY_LENGTH * 2.0, [], hist, 1)
	var plain := camp.food_store
	camp.food_store = 1.0
	camp.knowledge_pool["fermentation"] = true
	ss._tick_resources(TimeSystem.DAY_LENGTH * 2.0, [], hist, 1)
	check("stores spoil (%.2f left after two days), slower with fermentation (%.2f)" % [plain, camp.food_store],
		plain < 0.45 and camp.food_store > 0.7)

# ── Integration ──────────────────────────────────────────────────────────────

func _test_main_views() -> void:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	main.album_path = TEST_ALBUM
	add_child(main)
	for i in 5:
		await get_tree().process_frame
	check("Main builds a world", main.world != null and main.agents.size() == main.AGENT_COUNT)
	var adults: int = main.agents.filter(func(a): return a.life_stage == "adult").size()
	check("founders arrive as adults (%d/%d)" % [adults, main.agents.size()], adults == main.agents.size())
	check("the observer starts in charge", main.observer.active and main.observer.camera.current)
	# Wildlife is visible: the FBX models import at mixed units (a cow came in
	# 4 mm tall), so each species is scaled from its measured height.
	var bad: Array = []
	for an in main.animal_sim.animals:
		var node: Node3D = main.animal_renderer._instances.get(an.anim_id, {}).get("node")
		var h: float = AnimalRenderer._model_height(node) * node.scale.y if node else 0.0
		if h < 0.3 or h > 2.2:
			bad.append("%s %.3fm" % [AnimalSim.AnimalType.keys()[an.animal_type], h])
	check("every animal stands at a size you can see (%s)" % ", ".join(bad.slice(0, 4)), bad.is_empty() and not main.animal_sim.animals.is_empty())
	# The look picker: opening it at the start holds the clock; picking a card
	# switches the look; Begin starts time.
	var look_hud = main.get_node("HUD")
	var was_style := UiTheme.style
	main._set_speed(0.0)
	look_hud.open_look(true)
	check("the look picker opens", look_hud.screen is LookScreen and (look_hud.screen as LookScreen).starting)
	var other_look := "fieldnotes" if was_style == "storybook" else "storybook"
	(look_hud.screen as LookScreen)._choose(other_look)
	await get_tree().process_frame
	check("choosing a card switches the look (and the picker stays open)", UiTheme.style == other_look and look_hud.screen is LookScreen)
	look_hud.close_screen()
	check("Begin starts the clock", main.time_system.speed > 0.0)
	UiTheme.set_style(was_style)
	look_hud.apply_style_change()
	# Close and low over the highest ground, the eye stays above the hill.
	var peak := Vector2(0, 0)
	var peak_h := -INF
	for z in range(0, main.world.height, 2):
		for x in range(0, main.world.width, 2):
			var hh: float = main.world.surface_y(x + 0.5, z + 0.5)
			if hh > peak_h:
				peak_h = hh
				peak = Vector2(x + 0.5, z + 0.5)
	var obs: ObserverCamera = main.observer
	var keep := [obs.distance, obs.angle_v]
	obs.distance = ObserverCamera.ZOOM_MIN
	obs.angle_v = ObserverCamera.TILT_MIN
	obs.look_at_point(Vector3(peak.x, 0, peak.y) * World.TILE_SIZE)
	var cam: Vector3 = obs.camera.position
	check("the eye looks at the hilltop, not sea level (%.1f m)" % obs.target.y, absf(obs.target.y - peak_h) < 0.5)
	check("...and never sinks into the ground",
		cam.y >= main.world.surface_y(cam.x / World.TILE_SIZE, cam.z / World.TILE_SIZE) + 1.0)
	obs.distance = keep[0]
	obs.angle_v = keep[1]

	# A birth adds exactly one person (the renderer once appended them a second
	# time to the shared list, so every child was ticked and counted twice).
	var mum: Agent = main.agents[0]
	var pop_before: int = main.agents.size()
	main.concept_graph.birth_events.append({"x": mum.pos.x, "z": mum.pos.y, "parent_name": mum.agent_name,
		"parent_a_id": mum.agent_id, "parent_b_id": main.agents[1].agent_id})
	main._handle_births()
	var ids := {}
	for a in main.agents: ids[a.agent_id] = true
	check("a birth adds one person, once (%d -> %d)" % [pop_before, main.agents.size()],
		main.agents.size() == pop_before + 1 and ids.size() == main.agents.size())

	# Follow: the eye drifts to the person and stays with them.
	var who: Agent = main.agents[0]
	main.follow(who)
	check("following selects the person", main.selected_agent == who and who.selected)
	for i in 90:
		await get_tree().process_frame
	var at := Vector2(who.pos.x, who.pos.y) * World.TILE_SIZE
	check("the camera catches up with them", Vector2(main.observer.target.x, main.observer.target.z).distance_to(at) < 4.0)
	main.follow(null)
	check("letting go clears the selection", main.selected_agent == null and not who.selected)

	# Walk among them, beside the person we were watching.
	main.observer.look_at_point(Vector3(who.pos.x * World.TILE_SIZE, 0, who.pos.y * World.TILE_SIZE))
	main.set_view_mode(main.ViewMode.WALK)
	await get_tree().process_frame
	check("walking hands the camera to the wanderer", main.wanderer.active and main.wanderer.camera.current)
	check("...and the observer stops listening", not main.observer.active)
	check("the wanderer stands on dry land",
		main.world.is_walkable(main.wanderer.tile_pos.x, main.wanderer.tile_pos.y))
	# Stand right beside them and listen in. Others may wander close too, so
	# the one we hear is whoever is nearest; it must be them, and untouched.
	who.pos = main.wanderer.tile_pos + Vector2(0.3, 0)
	who.target = who.pos + Vector2(3, 0)
	who.state = Agent.State.WANDERING
	var near: Agent = main.nearest_agent_to_wanderer()
	check("someone beside you is in reach", near != null)
	who = near
	var before := [who.pos, who.target, who.state, who.facing, who.speech_bubble, who.needs.duplicate()]
	var heard: Agent = main.listen_to_nearest()
	check("listening in selects them", heard == who and main.selected_agent == who)
	check("...and they never know: nothing about them changes",
		[who.pos, who.target, who.state, who.facing, who.speech_bubble, who.needs] == before)
	await get_tree().process_frame
	var label: Label3D = main.agent_renderer.get_overlay(who.agent_id, "label") as Label3D
	check("their name shows up close", label != null and label.visible and label.text == who.agent_name)
	var bubble: Label3D = main.agent_renderer.get_overlay(who.agent_id, "bubble") as Label3D
	check("...with their thought in a bubble", bubble != null and bubble.visible and bubble.text.begins_with("("))
	check("the wanderer isn't anywhere in the simulation", not ("wanderer" in who) and main.world.get("wanderer") == null)

	main.set_view_mode(main.ViewMode.OBSERVE)
	await get_tree().process_frame
	check("Tab back hands the camera to the observer", main.observer.active and main.observer.camera.current and not main.wanderer.active)
	check("the mouse is free again", Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	check("leaving the ground stops the listening", main.agent_renderer.listening_id == -1)

	main.observer.distance = main.observer.ZOOM_MAX
	await get_tree().process_frame
	var other: Agent = main.agents[1]
	var pin: Node3D = main.agent_renderer.get_overlay(other.agent_id, "pin")
	check("from far away each person gets a pin", pin != null and pin.visible)
	var far_label: Label3D = main.agent_renderer.get_overlay(other.agent_id, "label") as Label3D
	check("...and names are hidden", far_label != null and not far_label.visible)

	# Let the world run: the story fills in from the real simulation.
	main.time_system.set_speed(20.0)
	for i in 240:
		main._process(1.0 / 30.0)
	main.time_system.set_speed(1.0)
	check("the chronicle fills as the world runs (%d entries)" % main.story.chronicle.size(), main.story.chronicle.size() > 5)
	check("every founder has a life story", main.agents.slice(0, main.AGENT_COUNT).all(func(a): return main.story.lives.has(a.agent_id)))

	# Every screen opens and closes in both looks, and the world restyles.
	var hud: GameHud = main.get_node("HUD")
	for style in UiTheme.STYLES:
		UiTheme.set_style(style)
		main.apply_style()
		hud.build()
		for scr in ["lives", "ideas", "album"]:
			hud.open_screen(scr)
			await get_tree().process_frame
			check("the %s screen opens in the %s look" % [scr, style], hud.screen != null and hud.screen_name == scr)
			hud.close_screen()
	check("closing leaves no screen", hud.screen == null)
	UiTheme.set_style("storybook")
	main.apply_style()
	hud.build()

	# A reset mid-walk must not leave the wanderer in charge of a dead camera.
	main.set_view_mode(main.ViewMode.WALK)
	main._init_world()
	await get_tree().process_frame
	check("reset returns to the observer", main.view_mode == main.ViewMode.OBSERVE and main.observer.active)
	main.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_ALBUM))
