extends RefCounted
## Places and maps: buildings from ideas, worn paths, the island's history,
## the minimap's colours and what a click says.

func run(t) -> void:
	_buildings(t)
	_paths(t)
	_history(t)
	_inspect(t)

func _settlement(id: int, centre: Vector2, tier: int, ideas: Array) -> SettlementSystem.Settlement:
	var s := SettlementSystem.Settlement.new()
	s.id = id
	s.name = "Testvale"
	s.centre = centre
	s.tier = tier
	s.member_ids = range(12)
	for i in ideas:
		s.knowledge_pool[i] = true
	return s

func _buildings(t) -> void:
	var w := World.new(7)
	w.heightfield = Heightfield.new().build(w)
	var m: Vector2i = t._first_tile(w, [World.TileType.GRASS])
	var r := SettlementRenderer.new()
	r.world = w
	t.add_child(r)
	var bare := _settlement(1, Vector2(m.x + 0.5, m.y + 0.5), 0, [])
	r.sync([bare], {})
	var kinds := func(sid): return (r.sites.get(sid, []) as Array).map(func(x): return str(x["kind"]))
	t.check("a camp that knows nothing has no shrine", not kinds.call(1).has("shrine"))
	var holy := _settlement(2, Vector2(m.x + 0.5, m.y + 0.5), 1, ["animism", "agriculture", "masonry"])
	r.sync([holy], {})
	t.check("animism raises a shrine", kinds.call(2).has("shrine"))
	t.check("agriculture brings fields and a barn", kinds.call(2).has("fields") and kinds.call(2).has("granary"))
	t.check("a hamlet doesn't wall itself in, even with masonry", not kinds.call(2).has("walls"))
	holy.tier = 2
	r.sync([holy], {})
	t.check("...a town does", kinds.call(2).has("walls"))
	r.queue_free()

func _paths(t) -> void:
	var w := World.new(7)
	var ps := PathSystem.new()
	var m: Vector2i = t._first_tile(w, [World.TileType.GRASS])
	var a: Agent = t._adult(m.x + 0.5, m.y + 0.5)
	for i in 30:
		a.pos += Vector2(0.5, 0)
		ps.tick(PathSystem.SAMPLE_SECONDS, [a], w, [], 1)
	var worn := 0.0
	for key in w.trade_traffic:
		worn = maxf(worn, float(w.trade_traffic[key]))
	t.check("walking wears the ground", worn > 0.0)
	var before := worn
	ps.tick(0.1, [], w, [], 2)
	var after := 0.0
	for key in w.trade_traffic:
		after = maxf(after, float(w.trade_traffic[key]))
	t.check("...and an unwalked way greens over day by day", after < before)

func _history(t) -> void:
	var h := IslandHistory.new()
	for i in 5:
		h.add({"t": i * 0.5, "pop": 40 + i, "known": i, "found": i * 2, "camps": 1, "hamlets": 0, "towns": 0})
	t.check("the island's history keeps its samples", h.series("pop").size() == 5 and h.peak_pop == 44)
	for i in IslandHistory.MAX_SAMPLES + 10:
		h.add({"t": 3.0 + i, "pop": 1, "known": 0, "found": 0, "camps": 0, "hamlets": 0, "towns": 0})
	t.check("...thinning the oldest so a long world still fits", h.samples.size() <= IslandHistory.MAX_SAMPLES)

func _inspect(t) -> void:
	var sea := Minimap.colour_of({"type": World.TileType.DEEP_WATER})
	var land := Minimap.colour_of({"type": World.TileType.GRASS})
	t.check("the map tells sea from land", sea.b > sea.g and land.g > land.b)
