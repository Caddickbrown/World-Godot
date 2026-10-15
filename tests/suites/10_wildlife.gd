extends RefCounted
## Wild things (AmbientLife + AmbientRenderer): whales, fish, frogs, birds,
## robins, butterflies, midges, bees and their nests. See docs/features/wildlife.md.

func _world(s: int = 7) -> World:
	var w := World.new(s)
	w.heightfield = Heightfield.new().build(w)
	return w

func _type_at(w: World, p: Vector2) -> int:
	return int(w.get_tile_f(p.x / World.TILE_SIZE, p.y / World.TILE_SIZE).get("type", -1))

func run(t) -> void:
	var w := _world()
	var life := AmbientLife.new().setup(w)
	_placement(t, w, life)
	_whales(t, w, life)
	_times_and_seasons(t, w)
	_fishing(t, w, life)
	_bees_and_honey(t, w, life)
	_no_dice_no_meddling(t, w)
	_renderer(t, w, life)
	_moments(t)
	_main(t)

func _placement(t, w: World, life: AmbientLife) -> void:
	t.check("whales live offshore (%d)" % life.whales.size(), life.whales.size() == AmbientLife.WHALES
		and life.whales.all(func(x): return _type_at(w, x.pos) == World.TileType.DEEP_WATER))
	var sea := life.shoals.filter(func(s): return not s.river)
	var river := life.shoals.filter(func(s): return s.river)
	t.check("fish shoal in the shallows (%d) and rivers (%d)" % [sea.size(), river.size()],
		sea.size() == AmbientLife.SEA_SHOALS and sea.all(func(s): return _type_at(w, s.pos) == World.TileType.WATER)
		and river.all(func(s): return bool(w.get_tile_f(s.pos.x / 2.0, s.pos.y / 2.0).get("river", false)) or _type_at(w, s.pos) == World.TileType.WATER))
	t.check("fish swim under the surface, not on it", sea.all(func(s): return s.y < 0.0 and s.y > -0.5))
	t.check("bees nest in the woods (%d nests)" % life.hives.size(), life.hives.size() >= 3
		and life.hives.all(func(h): return World.has_woods(w.get_tile(h.tile.x, h.tile.y))))
	t.check("...hanging above the ground, not at sea level", life.hives.all(func(h): return h.y > w.surface_y(h.pos.x / 2.0, h.pos.y / 2.0) + 1.0))
	t.check("frogs sit on land by fresh water (%d)" % life.frogs.size(), life.frogs.size() > 0
		and life.frogs.all(func(f): return w.is_walkable(f.pos.x / 2.0, f.pos.y / 2.0) or bool(w.get_tile_f(f.pos.x / 2.0, f.pos.y / 2.0).get("river", false))))
	t.check("counts are capped", life.flocks.size() * AmbientLife.BIRDS_PER_FLOCK + life.robins.size() + life.butterflies.size()
		+ life.bees.size() + life.frogs.size() + life.swarms.size() <= 30 + 8 + 28 + 24 + 14 + 8)

func _whales(t, w: World, life: AmbientLife) -> void:
	var wh: AmbientLife.Whale = life.whales[0]
	life._whale_state(wh, AmbientLife.WhaleState.BREACH, AmbientLife.BREACH_TIME)
	life.tick(AmbientLife.BREACH_TIME * 0.5, 12.0, "Summer")
	t.check("a breaching whale clears the water (%.1f m)" % wh.y, wh.y > 3.0)
	life.tick(AmbientLife.BREACH_TIME * 0.45, 12.0, "Summer")
	t.check("...and comes down in a splash", wh.splash > 0.5)
	life.drain_events()
	var breaches := 0
	var spouts := 0
	var dry := 0
	for i in 1200:
		life.tick(2.0, 12.0, "Summer")
		for x in life.whales:
			if x.spout > 0.5: spouts += 1
			if _type_at(w, x.pos) != World.TileType.DEEP_WATER: dry += 1
		breaches += life.drain_events().filter(func(e): return e["kind"] == "breach").size()
	t.check("whales surface and blow (%d samples)" % spouts, spouts > 0)
	t.check("over 20 game days they breach now and then (%d)" % breaches, breaches >= 3 and breaches < 200)
	t.check("...and never swim into the shallows (%d)" % dry, dry == 0)
	t.check("shoals stay in the water", life.shoals.all(func(s): return life._fish_water(s.pos, s.river)))

func _times_and_seasons(t, w: World) -> void:
	var life := AmbientLife.new().setup(w)
	life.tick(60.0, 12.0, "Summer")
	t.check("summer noon: butterflies and bees are out", life.butterflies.any(func(b): return b.shown) and life.bees.any(func(b): return b.shown))
	t.check("...birds are flying, no swarms", life.flocks.all(func(f): return f.birds.all(func(b): return not b.perched))
		and life.swarms.all(func(s): return s.level == 0.0))
	var alt := 0.0
	for f in life.flocks:
		for b in f.birds: alt += b.pos.y - w.surface_y(b.pos.x / 2.0, b.pos.z / 2.0)
	alt /= float(life.flocks.size() * AmbientLife.BIRDS_PER_FLOCK)
	t.check("flocks fly well above the ground (%.1f m)" % alt, alt > 3.0 and alt < 25.0)
	life.tick(10.0, 19.0, "Summer")
	t.check("dusk: midges swarm", life.swarms.all(func(s): return s.level > 0.9))
	life.drain_events()
	life.tick(30.0, 20.5, "Summer")
	t.check("frogs croak after dusk", life.frogs.any(func(f): return f.croaking and f.croak > 0.0))
	life.tick(120.0, 23.0, "Summer")
	t.check("night: the birds roost in the trees", life.flocks.all(func(f): return f.birds.all(func(b): return b.perched)))
	t.check("...the butterflies and bees are gone, and the robins", not life.butterflies.any(func(b): return b.shown)
		and not life.bees.any(func(b): return b.shown) and not life.robins.any(func(r): return r.shown))
	t.check("...and the midges", life.swarms.all(func(s): return s.level < 0.01))
	life.tick(60.0, 12.0, "Winter")
	t.check("winter: no butterflies, bees, frogs or swarms", not life.butterflies.any(func(b): return b.shown)
		and not life.bees.any(func(b): return b.shown) and not life.frogs.any(func(f): return f.shown))
	life.tick(10.0, 19.0, "Winter")
	t.check("...not even at dusk", life.swarms.all(func(s): return s.level == 0.0))
	t.check("...but robins stay all winter", life.robins.any(func(r): return r.shown))
	life.tick(60.0, 12.0, "Autumn")
	var n := life.butterflies.filter(func(b): return b.shown).size()
	t.check("autumn keeps a few butterflies (%d)" % n, n > 0 and n < life.butterflies.size() / 2)
	life.tick(60.0, 12.0, "Summer", [], true)
	t.check("rain sends butterflies and bees in", not life.butterflies.any(func(b): return b.shown)
		and not life.bees.any(func(b): return b.shown))
	# The chorus: one event per evening, from where the frogs are.
	var life2 := AmbientLife.new().setup(w)
	life2.tick(1.0, 17.0, "Summer")
	life2.tick(1.0, 18.5, "Summer")
	var chorus := life2.drain_events().filter(func(e): return e["kind"] == "chorus")
	life2.tick(1.0, 19.0, "Summer")
	t.check("the frogs strike up once an evening (%d)" % chorus.size(), not chorus.is_empty()
		and life2.drain_events().filter(func(e): return e["kind"] == "chorus").is_empty())

func _fishing(t, w: World, life: AmbientLife) -> void:
	life.attach()
	var s: AmbientLife.Shoal = life.shoals[0]
	s.stock = s.max_stock
	var by := s.pos / World.TILE_SIZE
	var far := Vector2(-50, -50)
	var near_catch := life.catch_at(by)
	t.check("fishing beside a shoal catches more (%.2f) than far from one (%.2f)" % [near_catch, life.catch_at(far)],
		near_catch > 1.2 and is_equal_approx(life.catch_at(far), AmbientLife.FISH_NONE))
	t.check("...and thins it", s.stock == s.max_stock - 1)
	for i in s.max_stock:
		life.catch_at(by)
	t.check("a fished-out shoal gives little", s.stock == 0 and life.catch_at(by) < 0.8)
	life.tick(AmbientLife.FISH_REGROW * 3.0 + 1.0, 12.0, "Summer")
	t.check("...then fills again", s.stock >= 3)
	t.check("a world without shoals fishes as before", AmbientLife.fish_catch(World.new(3), by) == 1.0)
	t.check("the agent hook finds this world's shoals", AmbientLife.of(w) == life)
	# The one Agent.gd hook: the yield after a fishing spell.
	s.stock = s.max_stock
	var yields := []
	for at in [by, far]:
		var a: Agent = t._adult(at.x, at.y)
		a.state = Agent.State.FISHING
		a.rest_timer = 0.01
		a.needs["hunger"] = 0.1
		a.tick(0.02, w, [a], t._graph())
		yields.append(a.needs["hunger"] - 0.1)
	t.check("a fisher by a shoal eats better (%.2f vs %.2f)" % yields, yields[0] > yields[1] + 0.2)

func _bees_and_honey(t, w: World, life: AmbientLife) -> void:
	life.attach()
	var g: ConceptGraph = t._graph()
	var honey: Dictionary = g.concepts["honey_gathering"]
	var h: AmbientLife.Hive = life.hives[0]
	var a: Agent = t._adult(h.tile.x + 0.5, h.tile.y + 0.5)
	t.check("honey is thought of by a real nest", g._conditions_met(a, w.get_tile(h.tile.x + 2, h.tile.y), honey, w, []))
	var lonely := Vector2i(-1, -1)
	for z in range(4, w.height - 4):
		for x in range(4, w.width - 4):
			if lonely.x < 0 and World.has_woods(w.get_tile(x, z)) and AmbientLife.hive_near(w, w.get_tile(x, z), 8.0) == 0:
				lonely = Vector2i(x, z)
	t.check("...not in any wood without one (it used to be any wood)", lonely.x >= 0
		and not g._conditions_met(a, w.get_tile(lonely.x, lonely.y), honey, w, []))
	var bare := World.new(7)
	t.check("a world with no nests modelled still has bees in its woods",
		g._conditions_met(a, bare.get_tile(lonely.x, lonely.y), honey, bare, []))
	# A honey trip.
	var start := h.pos / World.TILE_SIZE + Vector2(3.0, 0.0)
	var gatherer: Agent = t._adult(start.x, start.y)
	var other: Agent = t._adult(start.x, start.y + 0.5)
	for p in [gatherer, other]:
		p.state = Agent.State.GATHERING
		p.needs["hunger"] = 0.3
		p.target = p.pos + Vector2(-1, 0)
	gatherer.knowledge["honey_gathering"] = true
	h.honey = 1.0
	for i in 60:
		if life.honey_trips.has(gatherer.agent_id): break
		life.tick(1.0, 12.0, "Summer", [gatherer, other])
	var trip: Dictionary = life.honey_trips.get(gatherer.agent_id, {})
	t.check("a hungry gatherer who knows honey heads for the nest", not trip.is_empty() and gatherer.target == trip["spot"])
	t.check("...someone who doesn't know it doesn't", not life.honey_trips.has(other.agent_id) and other.target == other.pos + Vector2(-1, 0))
	life.drain_events()
	gatherer.pos = trip["spot"]
	life.tick(0.1, 12.0, "Summer", [gatherer, other])
	var ev := life.drain_events().filter(func(e): return e["kind"] == "honey")
	t.check("at the nest they eat honey (%.2f)" % gatherer.needs["hunger"], gatherer.needs["hunger"] > 0.6 and h.honey < 0.6 and ev.size() == 1)
	t.check("...and say so", gatherer.speech_bubble == "Honey!")
	var after := h.honey
	life.tick(TimeSystem.DAY_LENGTH * 0.25, 12.0, "Summer")
	t.check("a nest refills over a day", h.honey > after + 0.2)
	h.honey = 0.0
	life.tick(TimeSystem.DAY_LENGTH * 0.25, 12.0, "Winter")
	t.check("...but not in winter", h.honey == 0.0)
	# Wandered off: the trip is dropped and nothing more is changed.
	var b2: Agent = t._adult(start.x, start.y)
	b2.knowledge["honey_gathering"] = true
	b2.state = Agent.State.GATHERING
	b2.needs["hunger"] = 0.3
	h.honey = 1.0
	for i in 60:
		if life.honey_trips.has(b2.agent_id): break
		life.tick(1.0, 12.0, "Summer", [b2])
	b2.state = Agent.State.SLEEPING
	life.tick(0.1, 12.0, "Summer", [b2])
	t.check("a trip ends when they turn to something else", not life.honey_trips.has(b2.agent_id))

func _no_dice_no_meddling(t, w: World) -> void:
	var life := AmbientLife.new().setup(w)
	var a: Agent = t._adult(60, 60)
	a.knowledge["fishing"] = true
	a.state = Agent.State.GATHERING
	a.needs["hunger"] = 0.3
	var before := [a.pos, a.target, a.state, a.needs.duplicate(), a.speech_bubble]
	seed(4242)
	var expect := randf()
	seed(4242)
	life.tick(200.0, 12.0, "Summer", [a])
	life.tick(200.0, 19.0, "Summer", [a])
	t.check("ambient life never rolls the simulation's dice", randf() == expect)
	t.check("...and leaves people who don't know honey alone", [a.pos, a.target, a.state, a.needs, a.speech_bubble] == before)
	var l1 := AmbientLife.new().setup(w)
	var l2 := AmbientLife.new().setup(w)
	l1.tick(300.0, 12.0, "Summer")
	l2.tick(300.0, 12.0, "Summer")
	t.check("the same world gives the same wild things", l1.whales[0].pos == l2.whales[0].pos and l1.flocks[0].birds[3].pos == l2.flocks[0].birds[3].pos)

func _renderer(t, w: World, life: AmbientLife) -> void:
	life.tick(30.0, 12.0, "Summer")
	var r := AmbientRenderer.new()
	var cam := Camera3D.new()
	t.add_child(cam)
	cam.current = true
	seed(99)
	var expect := randf()
	seed(99)
	t.add_child(r)
	r.setup(life, w)
	var s: AmbientLife.Shoal = life.shoals[0]
	s.stock = s.max_stock
	cam.position = Vector3(s.pos.x, 30.0, s.pos.y + 20.0)
	r.update()
	t.check("drawing never rolls the simulation's dice", randf() == expect)
	t.check("near a shoal you see its fish (%d)" % int(r.drawn.get("fish", 0)), int(r.drawn.get("fish", 0)) >= s.max_stock)
	cam.position = Vector3(-900, 300, -900)
	r.update()
	t.check("far away the small things aren't drawn (LOD)", int(r.drawn.get("fish", 0)) == 0 and int(r.drawn.get("bee", 0)) == 0 and int(r.drawn.get("fly_body", 0)) == 0)
	var wh: AmbientLife.Whale = life.whales[0]
	life._whale_state(wh, AmbientLife.WhaleState.SURFACE, 12.0)
	life.tick(3.0, 12.0, "Summer")
	cam.position = Vector3(wh.pos.x, 120, wh.pos.y + 90)
	r.update()
	t.check("a surfaced whale shows from the sky view", int(r.drawn.get("whales", 0)) >= 1 and (r._whales[0]["root"] as Node3D).visible)
	var h: AmbientLife.Hive = life.hives[0]
	cam.position = Vector3(h.pos.x, h.y + 6.0, h.pos.y + 8.0)
	r.update()
	t.check("by a nest at midday you see its bees (%d)" % int(r.drawn.get("bee", 0)), int(r.drawn.get("bee", 0)) > 0)
	for style in UiTheme.STYLES:
		UiTheme.set_style(style)
		r.restyle()
		t.check("the wild things restyle in the %s look" % style, r.get_child_count() > 10)
	UiTheme.set_style("storybook")
	r.queue_free()
	cam.queue_free()

func _moments(t) -> void:
	var path := "user://test_wild_album.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var story := StoryKeeper.new()
	var seen := [false]
	story.witness_fn = func(_p, _ids): return seen[0]
	story.setup(t._graph(), [], path)
	story.on_wild({"kind": "breach", "pos": Vector2(5, 5)})
	t.check("a breach you didn't see isn't in the album", not story.moments.is_unlocked("whale_breach"))
	seen[0] = true
	story.on_wild({"kind": "breach", "pos": Vector2(5, 5)})
	t.check("...one you did is: %s" % story.moments.name_of("whale_breach"), story.moments.is_unlocked("whale_breach"))
	t.check("the chronicle tells of the first breach only once",
		story.chronicle.filter(func(e): return str(e["text"]).contains("whale")).size() == 1)
	story.on_wild({"kind": "chorus", "pos": Vector2(9, 9)})
	t.check("the frog chorus is a moment", story.moments.is_unlocked("frog_chorus"))
	var a: Agent = t._adult(5, 5)
	story.on_wild({"kind": "honey", "pos": a.pos, "agent_id": a.agent_id}, [a])
	story.on_wild({"kind": "honey", "pos": a.pos, "agent_id": a.agent_id}, [a])
	t.check("wild honey goes in their story, once", story.life_of(a).events.filter(func(e): return str(e["text"]).contains("honey")).size() == 1
		and story.moments.is_unlocked("wild_honey"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _main(t) -> void:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	main.album_path = "user://test_wild_main.json"
	t.add_child(main)
	t.check("Main keeps wild things on its world", main.ambient_life != null and AmbientLife.of(main.world) == main.ambient_life
		and main.ambient_renderer != null and main.ambient_renderer.life == main.ambient_life)
	var c0: float = main.ambient_life.clock
	main.time_system.set_speed(1.0)
	main._process(0.5)
	t.check("...and ticks them with the world", main.ambient_life.clock > c0)
	main.time_system.set_speed(0.0)
	var c1: float = main.ambient_life.clock
	main._process(0.5)
	t.check("...which stand still while paused", main.ambient_life.clock == c1)
	main.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_wild_main.json"))
