extends RefCounted
## Generations and legacy (feat/generations; docs/features/generations.md):
## the family register, names that carry on, legends at the fire, the family
## twig, and lives pressed into the album.

const ALBUM := "user://test_generations_album.json"

func run(t) -> void:
	_register(t)
	_naming(t)
	_four_generations(t)
	_legends(t)
	_fading_and_myth(t)
	_telling_is_per_second(t)
	_no_global_dice(t)
	_story_and_album(t)
	_twig(t)

## A small family: two founders, a child, a grandchild.
func _family(t, lt: LineageTracker) -> Dictionary:
	var gp_a: Agent = t._adult(10, 10)
	var gp_b: Agent = t._adult(10.5, 10)
	lt.setup([gp_a, gp_b], 77)
	var mum: Agent = t._adult(11, 10)
	lt.note_birth(mum, gp_a, gp_b, 2, [gp_a, gp_b])
	var dad: Agent = t._adult(11, 11)
	lt.note_birth(dad, null, null, 2, [gp_a, gp_b, mum])
	dad.bonded_partner_id = mum.agent_id
	mum.bonded_partner_id = dad.agent_id
	lt.tick(LineageTracker.CHECK_INTERVAL, [gp_a, gp_b, mum, dad])
	return {"gp_a": gp_a, "gp_b": gp_b, "mum": mum, "dad": dad}

func _register(t) -> void:
	var lt := LineageTracker.new()
	var f := _family(t, lt)
	var kid: Agent = t._adult(12, 10)
	lt.note_birth(kid, f["mum"], f["dad"], 4, f.values())
	t.check("the register knows a child's parents", lt.person(kid.agent_id)["parents"] == [f["mum"].agent_id, f["dad"].agent_id])
	t.check("...and the grandparents, two steps up", f["gp_a"].agent_id in lt.ancestors(kid.agent_id, 2))
	t.check("grandparents see their grandchild", kid.agent_id in lt.descendants(f["gp_a"].agent_id, 2))
	t.check("relations read both ways", lt.relation(kid.agent_id, f["gp_b"].agent_id) == "grandparent"
		and lt.relation(f["gp_b"].agent_id, kid.agent_id) == "grandchild" and lt.relation(f["mum"].agent_id, f["dad"].agent_id) == "partner")
	# The dead stay in the register after burial.
	f["gp_a"].is_dead = true
	lt.note_death(f["gp_a"], 5, null, f.values())
	t.check("the dead stay in the register", int(lt.person(f["gp_a"].agent_id)["died_day"]) == 5)

func _naming(t) -> void:
	var lt := LineageTracker.new()
	var f := _family(t, lt)
	var named := 0
	var wrong := 0
	var living := [f["mum"], f["dad"], f["gp_b"]]
	# Nobody is named after a living grandparent.
	for i in 60:
		var c: Agent = t._adult(12, 10)
		lt.note_birth(c, f["mum"], f["dad"], 3, living)
		if int(lt.person(c.agent_id)["named_for"]) >= 0:
			wrong += 1
	t.check("no child is named for a living grandparent (%d)" % wrong, wrong == 0)
	f["gp_a"].is_dead = true
	lt.note_death(f["gp_a"], 4, null, living)
	var gp_name: String = f["gp_a"].agent_name
	var ev_named := 0
	for i in 400:
		var c: Agent = t._adult(12, 10)
		lt.note_birth(c, f["mum"], f["dad"], 5, living)
		if int(lt.person(c.agent_id)["named_for"]) == f["gp_a"].agent_id:
			named += 1
			if c.agent_name != gp_name:
				wrong += 1
	for e in lt.drain_events():
		if e["kind"] == "named":
			ev_named += 1
	var share := float(named) / 400.0
	t.check("some children carry a dead grandparent's name (%.2f, want about %.2f)" % [share, LineageTracker.NAMED_FOR_GRANDPARENT],
		absf(share - LineageTracker.NAMED_FOR_GRANDPARENT) < 0.08)
	t.check("...they really have the name, and each naming is an event", wrong == 0 and ev_named == named)
	# A name already worn by someone living is not given again.
	var holder: Agent = t._adult(1, 1)
	holder.agent_name = gp_name
	var again := 0
	for i in 100:
		var c: Agent = t._adult(12, 10)
		lt.note_birth(c, f["mum"], f["dad"], 5, living + [holder])
		if c.agent_name == gp_name:
			again += 1
	t.check("no two living people share a namesake's name", again == 0)
	# Deterministic: the same register, seed and child id give the same pick.
	var pick_a := lt.pick_namesake(999999, [f["mum"].agent_id], {})
	var pick_b := lt.pick_namesake(999999, [f["mum"].agent_id], {})
	t.check("naming is a function of the world, not the moment", pick_a == pick_b)

func _four_generations(t) -> void:
	var lt := LineageTracker.new()
	var f := _family(t, lt)
	var kid: Agent = t._adult(12, 10)
	lt.note_birth(kid, f["mum"], f["dad"], 4, f.values())
	lt.drain_events()
	var gkid: Agent = t._adult(12, 11)
	lt.note_birth(gkid, kid, null, 6, f.values() + [kid])
	var four := lt.drain_events().filter(func(e): return e["kind"] == "four_generations")
	t.check("a great-grandparent alive at a birth is four generations", four.size() == 1
		and int(four[0]["elder_id"]) in [f["gp_a"].agent_id, f["gp_b"].agent_id])

func _legends(t) -> void:
	var lt := LineageTracker.new()
	var f := _family(t, lt)
	var g: ConceptGraph = t._graph()
	lt.setup([], 77, g.concepts)
	lt.record("fire", f["gp_a"], 1)
	f["gp_a"].is_dead = true
	lt.note_death(f["gp_a"], 3, null, f.values())
	t.check("the first to make fire becomes a legend", lt.is_legend(f["gp_a"].agent_id)
		and lt.legends[f["gp_a"].agent_id]["deed"] == "first made fire")
	t.check("...known to the family who outlive them", (lt.legends[f["gp_a"].agent_id]["knew"] as Dictionary).has(f["mum"].agent_id))
	f["dad"].is_dead = true
	lt.note_death(f["dad"], 3, null, f.values())
	t.check("an ordinary life is not a legend", not lt.is_legend(f["dad"].agent_id))
	# A mother of many is.
	var many: Agent = t._adult(5, 5)
	lt.note_birth(many, null, null, 1, [])
	for i in LineageTracker.LEGEND_CHILDREN:
		lt.note_birth(t._adult(5, 6), many, null, 2, [])
	many.is_dead = true
	lt.note_death(many, 4, null, [])
	t.check("a parent of many is a legend", lt.is_legend(many.agent_id) and str(lt.legends[many.agent_id]["deed"]).begins_with("raised"))
	# An elder who knew her tells it at the fire; those beside them hear it.
	var mum: Agent = f["mum"]
	mum.age = mum.life_expectancy * 0.8
	mum.at_fire = true
	var kid: Agent = t._adult(11.5, 10)
	kid.at_fire = true
	var told := ""
	for i in 600:
		lt.tick(1.0, [mum, kid])
		if mum.speech_bubble != "":
			told = mum.speech_bubble
			break
	t.check("an elder tells a legend at the fire (%s)" % told, told.contains(f["gp_a"].agent_name) and told.contains("first made fire"))
	t.check("...in their own words (a parent)", told.begins_with("My parent"))
	t.check("...and the child beside them heard it", kid.heard_legend == told and (lt.legends[f["gp_a"].agent_id]["heard"] as Dictionary).has(kid.agent_id))
	t.check("listening in shows what they heard at the fire", AgentThoughts.thought(kid) == told)
	var evs := lt.drain_events().filter(func(e): return e["kind"] == "told")
	t.check("the telling is an event for the story", evs.size() == 1 and bool(evs[0]["first"]))
	var away: Agent = t._adult(40, 40)
	away.age = away.life_expectancy * 0.8
	away.at_fire = true
	var stranger_told := false
	for i in 300:
		lt.tick(1.0, [away])
		if away.speech_bubble != "":
			stranger_told = true
	t.check("an elder who never knew them has nothing to tell", not stranger_told)

func _fading_and_myth(t) -> void:
	for oral in [false, true]:
		var lt := LineageTracker.new()
		var f := _family(t, lt)
		lt.record("fire", f["gp_a"], 1)
		var others: Array = [f["gp_b"], f["mum"], f["dad"]]
		f["gp_a"].is_dead = true
		lt.note_death(f["gp_a"], 3, null, others)
		var newcomer: Agent = t._adult(30, 30)
		if oral:
			newcomer.knowledge["oral_tradition"] = true
		for o in others:
			o.is_dead = true
		lt.drain_events()
		lt.tick(LineageTracker.CHECK_INTERVAL, others + [newcomer])
		var l: Dictionary = lt.legends[f["gp_a"].agent_id]
		var kinds := lt.drain_events().map(func(e): return e["kind"])
		if oral:
			t.check("with oral tradition, a legend outlives all who knew them: a myth", l["myth"] and not l["faded"] and "myth" in kinds)
			newcomer.age = newcomer.life_expectancy * 0.8
			newcomer.at_fire = true
			var said := ""
			for i in 600:
				lt.tick(1.0, [newcomer])
				if newcomer.speech_bubble != "":
					said = newcomer.speech_bubble
					break
			t.check("...and anyone may tell a myth (%s)" % said, said.begins_with("Long ago"))
		else:
			t.check("without it, a legend fades with the last who knew them", l["faded"] and "faded" in kinds)

## Telling is a per-second chance: big and small steps tell about as often.
func _telling_is_per_second(t) -> void:
	var counts: Array = []
	for step in [0.1, 1.0]:
		var lt := LineageTracker.new()
		var f := _family(t, lt)
		lt.record("fire", f["gp_a"], 1)
		f["gp_a"].is_dead = true
		lt.note_death(f["gp_a"], 3, null, [f["mum"]])
		var mum: Agent = f["mum"]
		mum.age = mum.life_expectancy * 0.8
		mum.at_fire = true
		var n := 0
		for i in int(4000.0 / step):
			mum.speech_bubble_timer = 0.0
			mum.speech_bubble = ""
			lt.tick(step, [mum])
			if mum.speech_bubble != "":
				n += 1
		counts.append(n)
	var want := 4000.0 * LineageTracker.TELL_RATE
	t.check("legends are told per second, not per frame (%s, want about %d)" % [str(counts), int(want)],
		absf(counts[0] - want) < want * 0.3 and absf(counts[1] - want) < want * 0.3)

## The register rolls its own dice: the world's dice are untouched.
func _no_global_dice(t) -> void:
	var lt := LineageTracker.new()
	var f := _family(t, lt)
	lt.record("fire", f["gp_a"], 1)
	var babies: Array = []
	for i in 4:
		babies.append(t._adult(12, 12))   # (making a person rolls the world's dice; do it first)
	var mum: Agent = f["mum"]
	mum.age = mum.life_expectancy * 0.8
	mum.at_fire = true
	seed(4242)
	var want := randi()
	seed(4242)
	f["gp_a"].is_dead = true
	lt.note_death(f["gp_a"], 3, null, f.values())
	for i in 200:
		lt.tick(1.0, f.values())
		if i % 50 == 0:
			lt.note_birth(babies[i / 50], f["mum"], f["dad"], 5, f.values())
	t.check("the register never rolls the world's dice", randi() == want)

func _story_and_album(t) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ALBUM))
	var lt := LineageTracker.new()
	var f := _family(t, lt)
	var g: ConceptGraph = t._graph()
	var keeper := StoryKeeper.new()
	keeper.setup(g, f.values(), ALBUM)
	lt.setup([], 77, g.concepts)
	lt.record("fire", f["gp_a"], 1)
	keeper.on_discovery(f["gp_a"], "fire")
	f["gp_a"].is_dead = true
	lt.note_death(f["gp_a"], 3, null, f.values())
	keeper.day = 3
	keeper.on_death(f["gp_a"])
	var mum: Agent = f["mum"]
	mum.age = mum.life_expectancy * 0.8
	mum.at_fire = true
	for i in 600:
		lt.tick(1.0, f.values())
		if mum.speech_bubble != "":
			break
	var kid: Agent = t._adult(12, 10)
	for i in 200:
		kid = t._adult(12, 10)
		lt.note_birth(kid, f["mum"], f["dad"], 4, f.values())
		if int(lt.person(kid.agent_id)["named_for"]) >= 0:
			break
	keeper.on_birth(kid, f["mum"], f["dad"])
	for e in lt.drain_events():
		keeper.on_lineage(e)
	var text := " ".join(keeper.chronicle.map(func(e): return e["text"]))
	t.check("the chronicle tells of the legend", text.contains("legends of"))
	t.check("...of the telling at the fire", text.contains("At the fire, %s told" % mum.agent_name))
	t.check("...and of the child named for them", text.contains("%s is named for %s" % [kid.agent_name, f["gp_a"].agent_name]))
	t.check("the namesake's life remembers it", keeper.life_of(f["gp_a"]).events.any(func(e): return str(e["text"]).contains("named for them")))
	for id in ["named_for", "legend_told"]:
		t.check("moment %s unlocks" % id, keeper.moments.is_unlocked(id))
	for id in ["named_for", "four_generations", "legend_told", "myth", "pressed_life"]:
		t.check("the album has %s" % id, Moments.DEFS.has(id))
	# Press a life: it is kept in the album, across a reload.
	t.check("a life can be pressed", keeper.press_life(f["gp_a"].agent_id, lt, 77))
	t.check("...and it says so", keeper.is_pressed(f["gp_a"].agent_id, 77) and keeper.moments.is_unlocked("pressed_life"))
	keeper.press_life(f["gp_a"].agent_id, lt, 77)
	t.check("pressing twice keeps one page", keeper.moments.pressed.size() == 1)
	var again := Moments.new()
	again.save_path = ALBUM
	again.load_album()
	var pg: Dictionary = again.pressed[0] if again.pressed.size() == 1 else {}
	t.check("a pressed life survives the world (%s)" % str(pg.get("name", "")), str(pg.get("name", "")) == f["gp_a"].agent_name
		and str(pg.get("legend", "")) == "first made fire" and int(pg.get("died_day", -1)) == 3)
	t.check("...with a page to show", PressedLife.span(pg).contains("died day 3") and PressedLife.family(pg) != "")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ALBUM))

func _twig(t) -> void:
	var lt := LineageTracker.new()
	var f := _family(t, lt)
	var kid: Agent = t._adult(12, 10)
	lt.note_birth(kid, f["mum"], f["dad"], 4, f.values())
	var gkid: Agent = t._adult(12, 11)
	lt.note_birth(gkid, kid, null, 6, [])
	for style in UiTheme.STYLES:
		var was := UiTheme.style
		UiTheme.set_style(style)
		var twig := FamilyTwig.new().build(lt, f["mum"].agent_id)
		var ids: Array = twig.nodes.map(func(n): return int(n["id"]))
		t.check("the twig (%s) draws parents, partner, children and grandchildren" % style,
			f["gp_a"].agent_id in ids and f["dad"].agent_id in ids and kid.agent_id in ids and gkid.agent_id in ids)
		t.check("...joined by twigs and a partner line", twig.links.size() == 5 and twig.links.any(func(l): return l[2] == "partner"))
		t.check("...at a size that fits the page", twig.custom_minimum_size.x > 0.0 and twig.custom_minimum_size.x < 800.0)
		var got := [-1]
		twig.chosen.connect(func(id): got[0] = id)
		for ch in twig.get_children():
			if ch is Button and ch.text == kid.agent_name:
				ch.pressed.emit()
		t.check("clicking a relative opens their life", got[0] == kid.agent_id)
		twig.free()
		UiTheme.set_style(was)
	var lines := FamilyTwig.card_lines(lt, f["gp_a"].agent_id)
	t.check("the follow card counts great-grandchildren", lines.any(func(s): return s.contains("great-grandchild")))
