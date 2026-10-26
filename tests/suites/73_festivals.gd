extends RefCounted
## Festivals and the year's rhythm (FestivalSystem), what they look like
## (FestivalRenderer), what the story makes of them, and the "something's
## happening" hints (Hints), which only ever move the camera.

const LAND := [World.TileType.GRASS, World.TileType.FOREST, World.TileType.WOODLAND, World.TileType.BEACH]

func run(t) -> void:
	_calendar(t)
	_harvest(t)
	_midsummer_and_mourning(t)
	_agent_at_festival(t)
	_story(t)
	_renderer(t)
	_hints(t)
	_hints_move_only_the_camera(t)

func _world() -> World:
	var w := World.new(7)
	w.heightfield = Heightfield.new().build(w)
	return w

## A grass tile with open land all round it (people can walk anywhere near).
func _open_grass(w: World) -> Vector2:
	for z in range(10, w.height - 10):
		for x in range(10, w.width - 10):
			if int(w.get_tile(x, z)["type"]) != World.TileType.GRASS:
				continue
			var ok := true
			for dz in range(-6, 7):
				for dx in range(-6, 7):
					if not int(w.get_tile(x + dx, z + dz)["type"]) in LAND:
						ok = false
			if ok:
				return Vector2(x + 0.5, z + 0.5)
	return Vector2(-1, -1)

func _camp(t, w: World, ideas: Array, people: int = 6) -> Dictionary:
	var c := _open_grass(w)
	var ss := SettlementSystem.new()
	ss.world = w
	var s := SettlementSystem.Settlement.new()
	s.id = 3
	s.name = "Testvale"
	s.centre = c
	var agents: Array = []
	for i in people:
		var a: Agent = t._adult(c.x + float(i % 3) - 1.0, c.y + float(i / 3) - 0.5)
		a.needs["hunger"] = 0.6
		agents.append(a)
		s.member_ids.append(a.agent_id)
	for id in ideas:
		s.knowledge_pool[id] = true
	ss.settlements.append(s)
	ss._reindex_members()
	return {"ss": ss, "s": s, "agents": agents}

## Wind the clock to `hour` on day `day`.
func _at(day: int, hour: float) -> TimeSystem:
	var ts := TimeSystem.new()
	ts.game_time = (float(day - 1) + hour / 24.0) * TimeSystem.DAY_LENGTH
	return ts

func _calendar(t) -> void:
	var s := SettlementSystem.Settlement.new()
	s.id = 1
	s.knowledge_pool = {"calendar": true}
	t.check("with a calendar, midsummer is the fourth day of summer (day %d)" % FestivalSystem.day_of(s, "midsummer", 0),
		FestivalSystem.day_of(s, "midsummer", 0) == 11)
	t.check("...and comes round again a year later", FestivalSystem.day_of(s, "midsummer", 1) == 11 + TimeSystem.SEASON_DAYS * 4)
	var shifts := {}
	for id in 6:
		var u := SettlementSystem.Settlement.new()
		u.id = id
		var sh := FestivalSystem.day_shift(u, "harvest")
		shifts[sh] = true
		if absi(sh) > 1:
			shifts["bad"] = true
	t.check("without one, camps guess the day within one either way (fixed, never rolled)",
		not shifts.has("bad") and shifts.size() >= 2)
	var bare := SettlementSystem.Settlement.new()
	t.check("no farming, no harvest feast", not FestivalSystem.knows_for(bare, "harvest"))
	bare.knowledge_pool = {"fire": true}
	t.check("fire alone isn't a midsummer festival", not FestivalSystem.knows_for(bare, "midsummer"))
	bare.knowledge_pool["art"] = true
	t.check("...fire and art are", FestivalSystem.knows_for(bare, "midsummer"))

func _harvest(t) -> void:
	var w := _world()
	var camp := _camp(t, w, ["agriculture", "calendar"])
	var s = camp["s"]
	var agents: Array = camp["agents"]
	var fs := FestivalSystem.new()
	var started: Array = []
	var ended: Array = []
	fs.festival_started.connect(func(k, p): started.append([k, p]))
	fs.festival_ended.connect(func(k, p): ended.append([k, p]))
	var early := _at(17, 15.0)
	fs.tick(1.1, agents, camp["ss"], early, w)
	t.check("no feast before the hour", fs.active.is_empty())
	var ts := _at(17, 17.2)   # the third day of autumn, evening
	fs.tick(1.1, agents, camp["ss"], ts, w)
	t.check("the harvest feast starts on its day and hour", fs.active.size() == 1 and fs.active[0]["kind"] == "harvest")
	t.check("...and says so to anyone listening (festival_started)", started.size() == 1 and started[0][0] == "harvest"
		and absf((started[0][1] as Vector3).y - w.surface_y(fs.active[0]["focus"].x, fs.active[0]["focus"].y)) < 0.01)
	s.food_store = 1.5
	var before: float = s.food_store
	for a in agents:
		before += a.needs["hunger"]
	fs.tick(1.1, agents, camp["ss"], ts, w)
	var come := agents.filter(func(a): return a.state == Agent.State.FESTIVAL and a.festival == "harvest")
	t.check("the camp comes to the table (%d/%d)" % [come.size(), agents.size()], come.size() == agents.size())
	var focus: Vector2 = fs.active[0]["focus"]
	t.check("...each to a place at it", agents.all(func(a): return a.target.distance_to(focus) < FestivalSystem.table_length(fs.active[0])))
	var seats := {}
	for a in agents:
		seats["%.2f,%.2f" % [a.target.x, a.target.y]] = true
	t.check("...no two in one seat", seats.size() == agents.size())
	for a in agents:
		a.pos = a.target
	fs.tick(1.1, agents, camp["ss"], ts, w)
	var after: float = s.food_store
	for a in agents:
		after += a.needs["hunger"]
	var events := fs.drain_events()
	var told := events.filter(func(e): return e["kind"] == "gathered")
	t.check("once gathered, it's told", told.size() == 1 and str(told[0]["text"]).contains("long table"))
	t.check("the feast shares out the larder (store %.2f -> %.2f), making no food" % [1.5, s.food_store],
		s.food_store < 1.5 and absf(after - before) < 0.001)
	t.check("...and the album can have it while it lasts", events.any(func(e): return e["kind"] == "ongoing" and e["moment"] == "fest_harvest"))
	var hungry: Agent = agents[0]
	hungry.needs["hunger"] = 0.1
	fs.tick(0.1, agents, camp["ss"], ts, w)
	t.check("someone gone hungry leaves to eat", hungry.state != Agent.State.FESTIVAL and hungry.festival == "")
	var end := _at(17, 21.2)
	fs.tick(1.1, agents, camp["ss"], end, w)
	t.check("it ends at its hour", fs.active.is_empty() and ended.size() == 1)
	t.check("...everyone goes back to their day", agents.all(func(a): return a.state != Agent.State.FESTIVAL and a.festival == ""))
	t.check("...in good spirits", agents.slice(1).all(func(a): return a.ritual_morale > 0.0))
	fs.tick(1.1, agents, camp["ss"], _at(17, 18.0), w)
	t.check("once a year", fs.active.is_empty())
	fs.tick(1.1, agents, camp["ss"], _at(17 + 28, 17.5), w)
	t.check("...and again next autumn", fs.active.size() == 1)

func _midsummer_and_mourning(t) -> void:
	var w := _world()
	var camp := _camp(t, w, ["fire", "music", "animism", "calendar"])
	var agents: Array = camp["agents"]
	var fs := FestivalSystem.new()
	var ts := _at(11, 19.5)
	fs.tick(1.1, agents, camp["ss"], ts, w)
	fs.tick(1.1, agents, camp["ss"], ts, w)
	t.check("midsummer: a camp with fire and belief dances", fs.active.size() == 1 and fs.active[0]["kind"] == "midsummer"
		and agents.all(func(a): return a.festival_pose == FestivalSystem.POSE_DANCE))
	var a: Agent = agents[0]
	var t0 := a.target
	ts.game_time += 2.0
	fs.tick(0.05, agents, camp["ss"], ts, w)
	t.check("...round the fire, the ring turning (%.2f tiles)" % a.target.distance_to(t0), a.target.distance_to(t0) > 0.3
		and absf(a.target.distance_to(fs.active[0]["focus"]) - t0.distance_to(fs.active[0]["focus"])) < 0.01)
	t.check("...with music when they know it", bool(fs.active[0]["music"]))
	# The day of remembering needs someone to remember.
	var fs2 := FestivalSystem.new()
	var s = camp["s"]
	for p in agents:
		p.state = Agent.State.WANDERING
		p.festival = ""
	t.check("no dead, no day of remembering", not fs2.opens(s, "mourning", 20, 16.5))
	var gone: Agent = t._adult(s.centre.x, s.centre.y)
	gone.agent_name = "Oru"
	s.member_ids.append(gone.agent_id)
	camp["ss"]._reindex_members()
	fs2.note_death(gone, camp["ss"])
	t.check("...a death in the camp, and it's kept", fs2.opens(s, "mourning", 20, 16.5))
	fs2.tick(1.1, agents, camp["ss"], _at(20, 16.5), w)
	t.check("...at the shrine", fs2.active.size() == 1 and fs2.active[0]["focus"].distance_to(s.centre + SettlementRenderer.SHRINE_AT) < 0.01)
	fs2.tick(1.1, agents, camp["ss"], _at(20, 16.5), w)
	for p in agents:
		p.pos = p.target
		p.mourning = 30.0
	fs2.tick(1.1, agents, camp["ss"], _at(20, 16.6), w)
	var told := fs2.drain_events().filter(func(e): return e["kind"] == "gathered")
	t.check("...naming who they remember", told.size() == 1 and str(told[0]["text"]).contains("Oru"))
	fs2.tick(1.1, agents, camp["ss"], _at(20, 19.0), w)
	t.check("remembering together eases grief", agents.all(func(p): return p.mourning <= 15.0))
	t.check("...and the dead are not remembered twice", not fs2.opens(s, "mourning", 20 + 28, 16.5))

## In the real Agent.tick: they walk to the festival and stay until let go.
func _agent_at_festival(t) -> void:
	var w := _world()
	var camp := _camp(t, w, ["fire", "oral_tradition", "calendar"], 4)
	var agents: Array = camp["agents"]
	var g: ConceptGraph = t._graph()
	var fs := FestivalSystem.new()
	var ts := _at(25, 17.5)   # midwinter
	fs.tick(1.1, agents, camp["ss"], ts, w)
	fs.tick(1.1, agents, camp["ss"], ts, w)
	t.check("midwinter: a camp with fire and stories hangs out lights", fs.active.size() == 1 and fs.active[0]["kind"] == "midwinter")
	var a: Agent = agents[0]
	for i in 60:
		for p in agents:
			p.tick(0.1, w, agents, g, 1.0, {}, "winter", ts, ts.day, null, camp["ss"], null)
		fs.tick(0.1, agents, camp["ss"], ts, w)
	t.check("they walk to their place and stay (%s, %.2f away)" % [Agent.State.keys()[a.state], a.pos.distance_to(a.target)],
		a.state == Agent.State.FESTIVAL and a.pos.distance_to(a.target) < 0.3)
	t.check("...sitting round the fire, where stories carry", a.at_fire)
	t.check("...facing it", a.facing.dot((fs.active[0]["focus"] - a.pos).normalized()) > 0.9)
	t.check("their thoughts say where they are", AgentThoughts.doing(a).contains("midwinter") and AgentThoughts.thought(a) != "")

func _story(t) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(t.TEST_ALBUM))
	var keeper := StoryKeeper.new()
	var a: Agent = t._adult()
	keeper.setup(t._graph(), [a], t.TEST_ALBUM)
	var seen := [false]
	keeper.witness_fn = func(_p, _ids): return seen[0]
	keeper.on_festival({"kind": "gathered", "festival": "harvest", "pos": Vector2(10, 10), "ids": [a.agent_id],
		"text": "Testvale brought the harvest in.", "moment": "fest_harvest", "note": "n", "life": "Ate at the harvest table.", "people": [a]})
	t.check("a festival goes in the chronicle", keeper.recent("people", 1)[0]["text"] == "Testvale brought the harvest in.")
	t.check("...and in the stories of those there", keeper.life_of(a).events.any(func(e): return e["text"] == "Ate at the harvest table."))
	t.check("not seen, not in the album", not keeper.moments.is_unlocked("fest_harvest"))
	seen[0] = true
	keeper.on_festival({"kind": "ongoing", "festival": "harvest", "pos": Vector2(10, 10), "ids": [a.agent_id], "moment": "fest_harvest", "note": "n"})
	t.check("...seen while it lasts, it is", keeper.moments.is_unlocked("fest_harvest"))
	var ids: Array = Moments.DEFS.keys()
	var first := ids.find("fest_planting")
	var mine := ids.slice(first, first + 5)
	t.check("the festival moments are one block in the album", first >= 0 and mine.all(func(x): return str(x).begins_with("fest_"))
		and FestivalSystem.KINDS.values().all(func(r): return Moments.DEFS.has(r["moment"])))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(t.TEST_ALBUM))

func _renderer(t) -> void:
	var w := _world()
	var camp := _camp(t, w, ["fire", "art", "calendar"])
	var fs := FestivalSystem.new()
	fs.tick(1.1, camp["agents"], camp["ss"], _at(11, 19.5), w)
	var r := FestivalRenderer.new()
	r.world = w
	t.add_child(r)
	seed(4242)
	var expect := randf()
	seed(4242)
	r.sync(fs, 1.0)
	r.sync(fs, 1.0)
	t.check("a festival is drawn (the bonfire)", r.shown_count() == 1)
	t.check("...without touching the simulation's dice", randf() == expect)
	var y: float = (r.get_child(0) as Node3D).position.y
	t.check("...standing on the ground", absf(y - w.surface_y(fs.active[0]["focus"].x, fs.active[0]["focus"].y)) < 0.01)
	fs.active.clear()
	r.sync(fs, 1.0)
	t.check("...and taken down when it ends", r.shown_count() == 0)
	t.remove_child(r)
	r.free()

class FakeMain extends Node:
	var festival_system: FestivalSystem
	var settlement_system
	var time_system: TimeSystem
	var weather_system = null
	var story = null
	var world: World
	var agents: Array = []

func _hints(t) -> void:
	var w := _world()
	var camp := _camp(t, w, ["fire", "art", "calendar"])
	var m := FakeMain.new()
	m.world = w
	m.agents = camp["agents"]
	m.settlement_system = camp["ss"]
	m.festival_system = FestivalSystem.new()
	m.time_system = _at(11, 18.0)
	var soon := Hints.gather(m)
	t.check("a festival about to start is worth a look", soon.any(func(h): return h["kind"] == "festival_soon"))
	m.festival_system.tick(1.1, m.agents, m.settlement_system, _at(11, 19.5), w)
	m.time_system = _at(11, 19.5)
	var baby: Agent = Agent.new(camp["s"].centre.x, camp["s"].centre.y)
	var old: Agent = t._adult(camp["s"].centre.x, camp["s"].centre.y)
	old.age = old.life_expectancy - 5.0
	m.agents.append(baby)
	m.agents.append(old)
	var now := Hints.gather(m)
	t.check("...and one under way, first", not now.is_empty() and now[0]["kind"] == "festival" and str(now[0]["text"]).contains("Testvale"))
	t.check("a new baby and a life near its end are hinted",
		now.any(func(h): return h["kind"] == "birth") and now.any(func(h): return h["kind"] == "fading"))
	var named := false
	for h in now:
		for a in m.agents:
			if str(h["text"]).contains(a.agent_name):
				named = true
	t.check("hints never name anyone (so they can't answer a hunch)", not named)
	m.free()

## The real game: clicking a hint moves the camera and nothing else.
func _hints_move_only_the_camera(t) -> void:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	main.album_path = t.TEST_ALBUM
	t.add_child(main)
	var hud = main.get_node("HUD")
	t.check("the HUD has the hints, on by default", hud.hints != null and hud.hints.main == main)
	var snap := func() -> Array:
		return main.agents.map(func(a): return [a.pos, a.target, a.state, a.needs.duplicate(), a.facing])
	var before: Array = snap.call()
	var gt: float = main.time_system.game_time
	var tile := Vector2(main.world.width * 0.3, main.world.height * 0.7)
	hud.hints.go_to(tile)
	t.check("clicking a hint looks there", Vector2(main.observer.target.x, main.observer.target.z).distance_to(tile * World.TILE_SIZE) < 1.0)
	t.check("...and changes nothing in the world", snap.call() == before and main.time_system.game_time == gt)
	t.remove_child(main)
	main.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(t.TEST_ALBUM))
