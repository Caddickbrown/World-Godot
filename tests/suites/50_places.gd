extends RefCounted
## Places and maps: buildings from ideas, worn paths, the island's history,
## the minimap's colours and what a click says.

func run(t) -> void:
	_buildings(t)
	_layout(t)
	_paths(t)
	_path_squares(t)
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

## A place grows; it isn't drawn with compasses.
func _layout(t) -> void:
	var w := World.new(7)
	w.heightfield = Heightfield.new().build(w)
	var m: Vector2i = t._first_tile(w, [World.TileType.GRASS])
	var r := SettlementRenderer.new()
	r.world = w
	t.add_child(r)
	var all := ["animism", "agriculture", "masonry", "temple", "church", "woodworking", "irrigation", "coop", "herding"]
	var town := _settlement(3, Vector2(m.x + 0.5, m.y + 0.5), 2, all)
	town.member_ids = range(36)
	r.sync([town], {})
	var sites: Array = r.sites_of(3)
	var homes: Array = sites.filter(func(x): return x["kind"] == "dwelling").map(func(x): return x["pos"])
	var built: Array = sites.filter(func(x): return not x["kind"] in ["walls", "fields", "hearth", "docks", "tree_house"])
	var clash := false
	for i in homes.size():
		for j in range(i + 1, homes.size()):
			if (homes[i] as Vector2).distance_to(homes[j]) < 3.0:
				clash = true
	t.check("a town's houses don't stand in each other (%d up)" % homes.size(), homes.size() >= 6 and not clash)
	var wall: Array = sites.filter(func(x): return x["kind"] == "walls")
	if wall.is_empty():
		t.check("a town with masonry walls itself in", false)
	else:
		var line: PackedVector2Array = wall[0]["line"]
		var c := town.centre * World.TILE_SIZE
		var lo := INF
		var hi := 0.0
		for p in line:
			lo = minf(lo, p.distance_to(c))
			hi = maxf(hi, p.distance_to(c))
		t.check("its wall follows the town, not a circle (%.1f-%.1f m out)" % [lo, hi], hi - lo > 0.25 * (hi + lo) * 0.5)
		t.check("...and everything built stands inside it",
			built.all(func(x): return Geometry2D.is_point_in_polygon(x["pos"], line)))
	# A new house never moves the old ones.
	var small := _settlement(3, town.centre, 2, all)
	small.member_ids = range(15)
	r.sync([small], {})
	var early: Array = r.sites_of(3).filter(func(x): return x["kind"] == "dwelling").map(func(x): return x["pos"])
	var same := early.size() >= 4
	for i in early.size():
		if i >= homes.size() or (early[i] as Vector2).distance_to(homes[i]) > 0.01:
			same = false
	t.check("a place keeps its first houses where they were as it grows", same)
	r.queue_free()

## Worn paths redraw only the squares whose wear moved.
func _path_squares(t) -> void:
	var w := World.new(7)
	w.heightfield = Heightfield.new().build(w)
	var pr := PathRenderer.new()
	pr.world = w
	t.add_child(pr)
	var m: Vector2i = t._first_tile(w, [World.TileType.GRASS])
	for i in 6:
		w.trade_traffic["%d,%d" % [m.x + i, m.y]] = 30.0
	pr.rebuild()
	t.check("a worn way is drawn", pr.wear_at(m.x, m.y) > 0.9 and pr.rebuilt >= 1)
	pr.rebuild()
	t.check("...and not redrawn when nothing changed", pr.rebuilt == 0)
	w.trade_traffic["%d,%d" % [m.x, m.y]] = 8.0
	pr.rebuild()
	t.check("...one changed tile redraws a square or two, not the map", pr.rebuilt >= 1 and pr.rebuilt <= 4)
	pr.queue_free()

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
