extends RefCounted
## Cultures (feat/cultures): camps with their own character, weddings between
## camps, feuds that mend, daughter camps. docs/features/cultures.md.

func run(t) -> void:
	_traits(t)
	_daughters(t)
	_pins(t)
	_wedding(t)
	_feud(t)
	_split(t)
	_story(t)
	_look(t)

func _camp(id: int, centre: Vector2, members: Array) -> SettlementSystem.Settlement:
	var s := SettlementSystem.Settlement.new()
	s.id = id
	s.name = "Camp%d" % id
	s.centre = centre
	s.member_ids = members.duplicate()
	return s

func _traits(t) -> void:
	var a := Culture.make(7, 1)
	var a2 := Culture.make(7, 1)
	t.check("a culture is derived, not rolled: same seed and camp, same ways",
		a.dye_i == a2.dye_i and a.roof_i == a2.roof_i and a.deco_i == a2.deco_i and a.density == a2.density)
	var differ := 0
	for id in range(2, 8):
		var b := Culture.make(7, id)
		if b.dye_i != a.dye_i or b.roof_i != a.roof_i or b.deco_i != a.deco_i:
			differ += 1
	t.check("other camps have other ways (%d of 6 differ)" % differ, differ >= 5)
	var c := Culture.make(7, 1, {"dye": [a.dye_i], "roof": [a.roof_i], "deco": [a.deco_i]})
	t.check("a new camp avoids the dye, roof and decoration a living camp already has",
		c.dye_i != a.dye_i and c.roof_i != a.roof_i and c.deco_i != a.deco_i)
	a.refresh({})
	t.check("a camp that knows nothing eats berries and makes a folk craft",
		a.food == "berries and nuts" and Culture.FOLK_CRAFTS.has(a.craft))
	var v := a.version
	a.refresh({"weaving": true})
	t.check("one craft idea isn't yet a craft of its own", Culture.FOLK_CRAFTS.has(a.craft))
	var changed := a.refresh({"weaving": true, "fishing": true, "dyeing": true})
	t.check("knowledge gives a camp its craft and its favourite food",
		a.craft in ["baskets", "dyed cloth"] and a.food == "smoked fish" and changed.has("craft"))
	a.refresh({"weaving": true, "fishing": true, "dyeing": true, "pottery": true, "music": true})
	t.check("...and what it's known for sticks", a.craft in ["baskets", "dyed cloth"])
	t.check("...and dyeing brightens its cloth (redrawn)", a.dyed and a.version > v)
	a.refresh({"fishing": true}, false)
	t.check("...no fish for a camp far from the water", a.food != "smoked fish")
	# Two camps that know the same things still differ in what they love.
	var all := {"weaving": true, "pottery": true, "woodworking": true, "music": true, "art": true,
		"fishing": true, "agriculture": true, "hunting": true, "cooking": true, "dairy": true}
	var picks: Dictionary = {}
	for id in range(1, 9):
		var k := Culture.make(3, id)
		k.refresh(all)
		picks[k.food + "/" + k.craft] = true
	t.check("camps knowing the same ideas still have their own tastes (%d kinds)" % picks.size(), picks.size() >= 4)
	t.check("a culture describes itself", a.describe().contains("roofs"))

func _daughters(t) -> void:
	var m := Culture.make(11, 4)
	m.refresh({"weaving": true})
	var d := Culture.daughter_of(m, 9, 4, "Ash Vale")
	t.check("a daughter keeps her mother's dye, drifted", d.dye_i == m.dye_i and absf(d.hue_shift - m.hue_shift) >= 0.05)
	t.check("...and knows whose daughter she is", d.mother_id == 4 and d.generation == 1 and d.mother_name == "Ash Vale")
	t.check("...her look differs from her mother's", d.dye() != m.dye())
	var before := d.hue_shift
	d.drift(0.02)
	t.check("daughters drift, and are redrawn", d.hue_shift != before and d.version > 0)
	var taken := {"Ash Vale": true}
	var n := m.daughter_name("Ash Vale", taken)
	t.check("a daughter is named in her mother's style (%s)" % n, n != "Ash Vale" and n.contains("Ash Vale"))
	taken[n] = true
	t.check("...never a name in use", m.daughter_name("Ash Vale", taken) != n)

func _pins(t) -> void:
	var ss := SettlementSystem.new()
	var a: Agent = t._adult(10, 10)
	var b: Agent = t._adult(11, 10)
	var s1 := _camp(1, Vector2(10, 10), [a.agent_id, b.agent_id])
	var s2 := _camp(2, Vector2(40, 10), [])
	ss.settlements = [s1, s2]
	ss._reindex_members()
	ss.pin_member(a.agent_id, s2, 3)
	t.check("a pinned person belongs to their new camp at once", ss.get_settlement_for_agent(a.agent_id) == s2)
	ss._update_membership([a, b])
	ss._apply_pins([a, b])
	ss._reindex_members()
	t.check("...and stays in it on the walk there, out of the old one",
		ss.get_settlement_for_agent(a.agent_id) == s2 and not s1.member_ids.has(a.agent_id))
	a.pos = Vector2(40, 10)
	ss._update_membership([a, b])
	ss._apply_pins([a, b])
	t.check("...until they arrive", not ss.is_pinned(a.agent_id) and s2.member_ids.has(a.agent_id))
	var d := ss.found_camp([b.agent_id], Vector2(70, 10), 1, "New Camp1")
	t.check("a founded camp holds its founders", d.member_ids.has(b.agent_id) and ss.get_settlement_for_agent(b.agent_id) == d)

func _wedding(t) -> void:
	var ss := SettlementSystem.new()
	var cs := CultureSystem.new()
	cs.settlement_system = ss
	cs.concepts = (t._graph() as ConceptGraph).concepts
	var a: Agent = t._adult(10, 10)
	var b: Agent = t._adult(40, 10)
	var kid := Agent.new(10, 10)
	kid.parents = [a.agent_id]
	a.knowledge = {"weaving": true, "fire": true}
	b.knowledge = {"fire": true}
	var others: Array = []
	for i in 4:
		others.append(t._adult(10 + i * 0.3, 10.5))
	var s1 := _camp(1, Vector2(10, 10), [a.agent_id, kid.agent_id] + others.map(func(x): return x.agent_id))
	s1.name = "Old Wood"
	var s2 := _camp(2, Vector2(40, 10), [b.agent_id])
	s2.name = "Ash Vale"
	s2.knowledge_pool = {"fire": true}
	ss.settlements = [s1, s2]
	ss._reindex_members()
	var everyone: Array = [a, b, kid] + others
	cs.tick(0.1, everyone, 1, 12.0)   # first look: who lives where
	for p in everyone:
		p.night_sleeping = true
	cs.tick(CultureSystem.INTERVAL, everyone, 1, 22.0)
	a.bonded_partner_id = b.agent_id
	b.bonded_partner_id = a.agent_id
	var early: Array = cs.tick(CultureSystem.INTERVAL, everyone, 1, 22.5)
	t.check("people not yet settled anywhere don't count as a wedding between camps",
		early.filter(func(e): return e["moment"] == "wedding_camps").is_empty())
	var out: Array = cs.tick(CultureSystem.INTERVAL, everyone, 2, 22.0)   # a second night at home
	for p in everyone:
		p.night_sleeping = false
	out += cs.tick(CultureSystem.INTERVAL, everyone, 3, 12.0)
	var wed: Array = out.filter(func(e): return e["moment"] == "wedding_camps")
	t.check("a couple from two camps is a wedding between camps", wed.size() == 1 and cs.cross_marriages == 1)
	t.check("...the one from the bigger camp moves, with their child",
		ss.get_settlement_for_agent(a.agent_id) == s2 and ss.get_settlement_for_agent(kid.agent_id) == s2)
	t.check("...and brings their ideas: the new camp knows weaving", s2.knowledge_pool.has("weaving"))
	t.check("the chronicle tells it (%s)" % (wed[0]["text"] if not wed.is_empty() else ""),
		not wed.is_empty() and str(wed[0]["text"]).contains("Old Wood") and str(wed[0]["text"]).contains("weaving"))
	t.check("the follow card shows home and birth camp (%s)" % cs.card_line(a),
		cs.card_line(a).begins_with("Of Ash Vale") and cs.card_line(a).contains("first forty"))
	out = cs.tick(CultureSystem.INTERVAL, everyone, 4, 12.0)
	t.check("...told once", out.filter(func(e): return e["moment"] == "wedding_camps").is_empty())

func _feud(t) -> void:
	var ss := SettlementSystem.new()
	var cs := CultureSystem.new()
	cs.settlement_system = ss
	var a: Agent = t._adult(10, 10)
	var b: Agent = t._adult(10.5, 10)
	var s1 := _camp(1, Vector2(10, 10), [a.agent_id])
	var s2 := _camp(2, Vector2(30, 10), [b.agent_id])
	ss.settlements = [s1, s2]
	ss._reindex_members()
	var conflict := ConflictSystem.new()
	conflict.settlement_system = ss
	conflict.culture_system = cs
	conflict._delta = 1000.0
	conflict._check_agent_conflict(a, b, 1, HistoryLog.new())
	t.check("well-fed neighbours at peace don't clash", not conflict.is_in_conflict(a))
	cs.feuds[CultureSystem._key(1, 2)] = {"a": 1, "b": 2, "start": 1, "reason": "the hazel thicket between them"}
	conflict._check_agent_conflict(a, b, 1, HistoryLog.new())
	t.check("feuding camps shove each other, fed or not", conflict.is_in_conflict(a))
	t.check("...but a feud harms nobody", not a.is_dead and not b.is_dead and a.health > 0.0 and b.health > 0.0)
	var out: Array = []
	cs._mend_feuds(1 + CultureSystem.FEUD_MAX_DAYS, out)
	t.check("every feud is mended in the end", cs.feuds.is_empty() and out.size() == 1 and out[0]["moment"] == "quarrel_mended")
	t.check("...and not started again at once", cs._feud_cool.get(CultureSystem._key(1, 2), 0) > 1 + CultureSystem.FEUD_MAX_DAYS)

func _split(t) -> void:
	var w := World.new(7)
	var m: Vector2i = t._first_tile(w, [World.TileType.GRASS])
	# A big meadow to found on: find a grass tile with grass round it.
	var ss := SettlementSystem.new()
	ss.world = w
	var cs := CultureSystem.new()
	cs.world = w
	cs.settlement_system = ss
	var centre := Vector2(w.width * 0.5, w.height * 0.5)
	var best := -1.0
	for z in range(20, w.height - 20, 6):
		for x in range(20, w.width - 20, 6):
			if not w.is_walkable(x + 0.5, z + 0.5):
				continue
			var f := ss.food_around(Vector2(x + 0.5, z + 0.5), 8)
			if f > best:
				best = f
				centre = Vector2(x + 0.5, z + 0.5)
	var people: Array = []
	for i in 18:
		people.append(t._adult(centre.x + (i % 4) * 0.4, centre.y + (i / 4) * 0.4))
	for i in range(0, 18, 2):
		people[i].bonded_partner_id = people[i + 1].agent_id
		people[i + 1].bonded_partner_id = people[i].agent_id
	var mother := _camp(0, centre, people.map(func(p): return p.agent_id))
	mother.name = "Ash Vale"
	mother.knowledge_pool = {"weaving": true, "fire": true}
	ss.settlements = [mother]
	ss._next_id = 1
	ss._reindex_members()
	cs.tick(0.1, people, 1, 12.0)
	var founded: Array = []
	for day in range(2, 30):
		for e in cs.tick(CultureSystem.INTERVAL, people, day, 12.0):
			if e["moment"] == "new_camp":
				founded.append(e)
		if not founded.is_empty():
			break
	t.check("a crowded camp splits and founds a daughter camp", founded.size() == 1 and ss.settlements.size() == 2)
	if ss.settlements.size() < 2:
		return
	var d = ss.settlements[1]
	t.check("...with four to eight of its people (%d)" % d.member_ids.size(), d.member_ids.size() >= 4 and d.member_ids.size() <= 8)
	t.check("...a walk away (%.0f tiles), not on top of anyone" % d.centre.distance_to(centre),
		d.centre.distance_to(centre) >= SettlementSystem.FOUNDING_SPACING)
	t.check("...keeping its mother's ideas and ways", d.knowledge_pool.has("weaving") and d.culture.mother_id == 0 and d.culture.dye_i == mother.culture.dye_i)
	t.check("...couples go together", d.member_ids.all(func(id):
		var p = people.filter(func(x): return x.agent_id == id)[0]
		return p.bonded_partner_id < 0 or d.member_ids.has(p.bonded_partner_id)))
	t.check("the chronicle tells it (%s)" % founded[0]["text"], str(founded[0]["text"]).contains("daughter of Ash Vale"))

func _story(t) -> void:
	var sk := StoryKeeper.new()
	sk.moments.save_path = "user://test_cultures_album.json"
	var a: Agent = t._adult(5, 5)
	sk.on_culture({"kind": "people", "text": "A of X married B of Y and moved there.", "pos": Vector2(5, 5), "ids": [a.agent_id],
		"major": true, "moment": "wedding_camps", "note": "A and B", "life": {a.agent_id: "Married B."}}, [a])
	t.check("a wedding between camps goes in the chronicle", sk.chronicle[-1]["text"].contains("married"))
	t.check("...in their life story", sk.life_of(a).events.any(func(e): return e["text"] == "Married B."))
	t.check("...and in the album", sk.moments.is_unlocked("wedding_camps"))
	for id in ["wedding_camps", "new_camp", "quarrel_mended"]:
		t.check("album moment %s exists" % id, Moments.DEFS.has(id))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(sk.moments.save_path))

func _look(t) -> void:
	var w := World.new(7)
	w.heightfield = Heightfield.new().build(w)
	var m: Vector2i = t._first_tile(w, [World.TileType.GRASS])
	var r := SettlementRenderer.new()
	r.world = w
	t.add_child(r)
	var s1 := _camp(1, Vector2(m.x + 0.5, m.y + 0.5), range(9))
	s1.tier = 1
	s1.culture = Culture.make(7, 1)
	var s2 := _camp(2, Vector2(m.x + 0.5, m.y + 0.5), range(9))
	s2.tier = 1
	s2.culture = Culture.make(7, 2, {"dye": [s1.culture.dye_i], "roof": [s1.culture.roof_i], "deco": [s1.culture.deco_i]})
	seed(99)
	var expect := randi()
	seed(99)
	r.sync([s1, s2], {})
	t.check("drawing a camp's culture leaves the world's dice alone", randi() == expect)
	var roofs := func(sid) -> Array:
		var out: Array = []
		var node: Node3D = r._built[sid]["node"]
		for d in node.get_children():
			for ch in d.get_children():
				if ch is MeshInstance3D and (ch.mesh is CylinderMesh) and (ch.mesh as CylinderMesh).top_radius == 0.0 and ch.position.y > 2.0:
					out.append((ch.material_override as StandardMaterial3D).albedo_color.to_html())
		return out
	var r1: Array = roofs.call(1)
	var r2: Array = roofs.call(2)
	t.check("two camps' huts are roofed differently (%d, %d huts)" % [r1.size(), r2.size()],
		not r1.is_empty() and not r2.is_empty() and r1[0] != r2[0])
	var sig: String = r._built[2]["sig"]
	s2.culture.drift(0.05)
	r.sync([s2], {})
	t.check("a camp whose ways drift is redrawn", str(r._built[2]["sig"]) != sig)
	# The plan follows the culture's density.
	s1.culture.density = 0.8
	r._plans.erase(1)
	r._built.erase(1)
	r.sync([s1], {})
	var close: Array = r.sites_of(1).filter(func(x): return x["kind"] == "dwelling").map(func(x): return (x["pos"] as Vector2).distance_to(s1.centre * World.TILE_SIZE))
	s1.culture.density = 1.25
	s1.culture.version += 1
	r._built[1]["node"].queue_free()
	r._built.erase(1)
	r.sync([s1], {})
	var wide: Array = r.sites_of(1).filter(func(x): return x["kind"] == "dwelling").map(func(x): return (x["pos"] as Vector2).distance_to(s1.centre * World.TILE_SIZE))
	var mean := func(a: Array) -> float:
		var sum := 0.0
		for x in a: sum += float(x)
		return sum / maxf(1.0, a.size())
	t.check("a spread-out culture builds wider than a close-built one (%.1f vs %.1f m)" % [mean.call(close), mean.call(wide)],
		mean.call(wide) > mean.call(close))
	# People wear their camp's dye.
	var ss := SettlementSystem.new()
	var a: Agent = t._adult(m.x + 0.5, m.y + 0.5)
	s1.member_ids = [a.agent_id]
	ss.settlements = [s1]
	ss._reindex_members()
	var ar := AgentRenderer.new()
	ar.settlement_system = ss
	var e := {"tribe": -2, "body": MeshInstance3D.new()}
	ar._dress(e, a)
	var worn: Color = (e["body"].material_override as StandardMaterial3D).albedo_color
	t.check("people wear their camp's dye", worn.is_equal_approx(LookStyle.g(s1.culture.dye())))
	e["body"].free()
	ar.free()
	r.queue_free()
