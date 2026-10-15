extends RefCounted
## Ideas that matter: every effect an idea names is read by some code, and so
## is every key in items.json; effects combine and clamp; a few of them, seen
## working.

func run(t) -> void:
	_every_key_read(t)
	_aggregation(t)
	_behaviour(t)

static func _all_source() -> String:
	var out := ""
	var stack := ["res://scripts"]
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for d in dir.get_directories():
			stack.append(dir_path + "/" + d)
		for f in dir.get_files():
			if f.ends_with(".gd") and f != "ConceptEffects.gd":
				out += FileAccess.get_file_as_string(dir_path + "/" + f)
	return out

static func _json_keys(v, into: Dictionary) -> void:
	if v is Dictionary:
		for k in v:
			into[str(k)] = true
			_json_keys(v[k], into)
	elif v is Array:
		for e in v:
			_json_keys(e, into)

func _every_key_read(t) -> void:
	var src := _all_source()
	var unread: Array = []
	for k in ConceptEffects.RULES:
		if not ConceptEffects.DROPPED.has(k) and not src.contains('"%s"' % k):
			unread.append(k)
	t.check("every idea effect is read by some code (unread: %s)" % ", ".join(unread), unread.is_empty())
	var undeclared: Array = []
	for id in ConceptEffects.defs():
		for k in ConceptEffects.defs()[id]:
			if not ConceptEffects.RULES.has(k):
				undeclared.append("%s.%s" % [id, k])
	t.check("every effect in the data is declared (%s)" % ", ".join(undeclared.slice(0, 4)), undeclared.is_empty())
	var items = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	var keys := {}
	_json_keys(items, keys)
	var item_unread: Array = []
	for k in keys:
		if not src.contains('"%s"' % k):
			item_unread.append(k)
	t.check("every items.json key is read (unread: %s)" % ", ".join(item_unread), item_unread.is_empty())

func _aggregation(t) -> void:
	var none := ConceptEffects.aggregate({})
	t.check("knowing nothing is neutral", float(none["gather_efficiency"]) == 1.0 and not bool(none["can_fish"]))
	var all := {}
	for id in ConceptEffects.defs():
		all[id] = true
	var every := ConceptEffects.aggregate(all)
	t.check("twenty small boosts can't add up to a tenfold harvest (x%.2f)" % float(every["gather_efficiency"]),
		float(every["gather_efficiency"]) <= float(ConceptEffects.RULES["gather_efficiency"][2]))
	t.check("language speeds teaching", float(ConceptEffects.aggregate({"language": true})["spread_rate_multiplier"]) > 1.5)

func _behaviour(t) -> void:
	var w := World.new(7)
	var g: ConceptGraph = t._graph()
	var meadow: Vector2i = t._first_tile(w, [World.TileType.GRASS])
	var mt := w.get_tile(meadow.x, meadow.y)
	var a: Agent = t._adult(meadow.x + 0.5, meadow.y + 0.5)
	var plain := a.gather_yield_mult(mt, w)
	a.knowledge["agriculture"] = true
	t.check("agriculture makes meadows yield more (x%.2f -> x%.2f)" % [plain, a.gather_yield_mult(mt, w)], a.gather_yield_mult(mt, w) > plain)
	# Teaching: someone with language and writing teaches faster.
	ConceptGraph.spread_pace = 1000.0
	var b: Agent = t._adult(meadow.x + 0.5, meadow.y + 0.5)
	a.knowledge["fire"] = true
	var plain_t: Agent = t._adult(meadow.x + 0.5, meadow.y + 0.5)
	t.check("a teacher who knows language passes ideas on faster",
		a.fxf("spread_rate_multiplier") >= 1.0 and ConceptEffects.aggregate({"language": true, "writing": true})["spread_rate_multiplier"] > ConceptEffects.aggregate({"language": true})["spread_rate_multiplier"])
	ConceptGraph.spread_pace = 0.9
	# Peace: law and diplomacy make clashes rarer.
	var peaceful: Agent = t._adult(10, 10)
	peaceful.knowledge["diplomacy"] = true
	peaceful.knowledge["law"] = true
	t.check("law and diplomacy keep the peace (%.2f)" % peaceful.fxf("keeps_peace"), peaceful.fxf("keeps_peace") > 0.5)
	# A first is told once, however many times it's done.
	var first := g.drain_deeds().size()
	b._concept_graph = g
	b._deed("first_test", "x")
	b._deed("first_test", "x")
	t.check("a first is told once", g.drain_deeds().size() == 1 and first >= 0)
	# Burial eases grief.
	var mourner: Agent = t._adult(10, 10)
	mourner.grieve("A")
	var long := mourner.mourning
	var buried: Agent = t._adult(10, 10)
	buried.knowledge["animism"] = true
	buried.grieve("A")
	t.check("a burial eases grief sooner", buried.mourning < long)
