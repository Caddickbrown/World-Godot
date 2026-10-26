extends RefCounted
## Ideas are lost, and found again (feat/ideas, docs/features/ideas.md): the
## last holder dying loses an idea and leaves a ghost; the ledger and the
## chronicle record it; a lost idea is easier to think of near its ghost;
## finding it again is told, with how long it was gone.

func run(t) -> void:
	_loss(t)
	_ghost_bonus(t)
	_story(t)
	_camp_pool(t)
	_crafts_fragile(t)

func _loss(t) -> void:
	var g: ConceptGraph = t._graph()
	var mara: Agent = t._adult(20, 20)
	var ivo: Agent = t._adult(40, 40)
	var people := [mara, ivo]
	g._grant(mara, "fire")
	g._grant(ivo, "fire")
	g._grant(mara, "pottery")
	mara.is_dead = true
	mara.health = 0.0
	var lost: Array = g.note_death(mara, people, 6, Vector2(25, 20))
	t.check("the last who knew pottery dying loses it (lost: %s)" % str(lost), lost == ["pottery"])
	t.check("...but not fire, which Ivo still holds", not g.memory.is_lost("fire"))
	var ghost: Dictionary = g.memory.ghosts.get("pottery", {})
	t.check("a ghost stays where Mara died and at her hearth",
		ghost.get("last_name", "") == mara.agent_name and (ghost.get("places", []) as Array).size() == 2)
	t.check("the loss is an event for the story", g.drain_events().any(func(e): return e["type"] == "lost" and e["concept_id"] == "pottery"))
	t.check("a second death doesn't lose it twice", g.note_death(mara, people, 7).is_empty() and g.memory.lost_total == 1)

func _ghost_bonus(t) -> void:
	var g: ConceptGraph = t._graph()
	var w := World.new(7)
	var meadow: Vector2i = t._first_tile(w, [World.TileType.GRASS])
	var at := Vector2(meadow.x + 0.5, meadow.y + 0.5)
	var dead: Agent = t._adult(at.x, at.y)
	dead.knowledge["cooking"] = true
	dead.knowledge["fermentation"] = true
	dead.is_dead = true
	g.note_death(dead, [dead], 3)
	t.check("near a ghost the odds are better (x%.1f)" % g.memory.bonus("fermentation", at), g.memory.bonus("fermentation", at) > 1.0)
	t.check("far from it they are not", g.memory.bonus("fermentation", at + Vector2(IdeaMemory.GHOST_RADIUS + 5, 0)) == 1.0)
	t.check("ideas never lost have no ghost", g.memory.bonus("fire", at) == 1.0 and not g.memory.is_lost("fire"))
	# Seen working: the same person, many tries, near the ghost and far from it.
	var tile := w.get_tile(meadow.x, meadow.y)
	var near_n := _tries(g, w, tile, at, 4000)
	var far_n := _tries(g, w, tile, at + Vector2(IdeaMemory.GHOST_RADIUS * 3, 0), 4000)
	t.check("fermentation is found again more often near its ghost (%d near, %d far)" % [near_n, far_n], near_n > far_n * 2)
	# Finding it lays the ghost to rest.
	var finder: Agent = t._adult(at.x, at.y)
	finder.knowledge["cooking"] = true
	g.memory.note_refound("fermentation", finder, 9)
	t.check("found again: the ghost is gone, the finding remembered",
		not g.memory.is_lost("fermentation") and bool(g.memory.refound["fermentation"]["near"]) and g.memory.refound_total >= 1)

## How many of n tries a cook (knows cooking) thinks of fermentation at `at`.
func _tries(g: ConceptGraph, w: World, tile: Dictionary, at: Vector2, n: int) -> int:
	var saved := ConceptGraph.discovery_pace
	ConceptGraph.discovery_pace = 30.0
	var found := 0
	var a: Agent = Agent.new(at.x, at.y)
	a.age = a.max_age * 0.4
	a.is_adult = true
	for i in n:
		a.knowledge = {"cooking": true, "fire": true}
		a.pos = at
		# The ghost must stay for every try: a find would lay it to rest.
		var ghost: Dictionary = g.memory.ghosts.get("fermentation", {}).duplicate(true)
		if g.check_discovery(a, tile, 0.05, w, [a]) == "fermentation":
			found += 1
		g.memory.ghosts["fermentation"] = ghost
	g.drain_events()
	ConceptGraph.discovery_pace = saved
	return found

func _story(t) -> void:
	var g: ConceptGraph = t._graph()
	var mara: Agent = t._adult(10, 10)
	var pip: Agent = t._adult(12, 10)
	mara.agent_name = "Mara"
	pip.agent_name = "Pip"
	var people := [mara, pip]
	var keeper := StoryKeeper.new()
	keeper.setup(g, people, "user://test_album_ideas_lost.json")
	mara.knowledge["fire"] = true
	mara.knowledge["pottery"] = true
	pip.knowledge["fire"] = true
	keeper.tick(StoryKeeper.RECOUNT_INTERVAL, people, 4, 12.0, 2)
	mara.is_dead = true
	mara.health = 0.0
	mara.death_cause = "old_age"
	keeper.on_death(mara)
	keeper.tick(StoryKeeper.RECOUNT_INTERVAL, people, 5, 12.0, 1)
	var rec: Dictionary = keeper.ledger.ideas["pottery"]
	t.check("the ledger records the loss (day %d, with %s)" % [rec["lost_day"], rec["lost_with"]],
		int(rec["times_lost"]) == 1 and int(rec["lost_day"]) == 5 and rec["lost_with"] == "Mara"
		and keeper.ledger.stage_of("pottery") == IdeaLedger.Stage.WILTED)
	var told := keeper.chronicle.any(func(e): return e["text"] == "No one remembers how to fire clay now. Mara was the last.")
	t.check("the chronicle tells it warmly", told)
	t.check("...and so does Mara's life story", keeper.life_of(mara).events.any(func(e): return str(e["text"]).contains("last who knew how to fire clay")))
	t.check("the album has 'An idea lost'", keeper.moments.is_unlocked("idea_lost") and keeper.moments.name_of("idea_lost") == "An idea lost")
	var glyph := PlantGlyph.new().setup(keeper.ledger.stage_of("pottery"), Color.WHITE)
	t.check("a wilted idea is drawn wilted", glyph.stage == IdeaLedger.Stage.WILTED)
	glyph.free()
	# Found again, four days on, near where Mara last knew it.
	keeper.tick(1.0, people, 9, 12.0, 1)
	pip.knowledge["pottery"] = true
	keeper.on_discovery(pip, "pottery")
	var line := "Pip has worked out how to fire clay again, four days after it was lost, not far from where Mara last knew it."
	t.check("finding it again is told with how long it was gone", keeper.chronicle.any(func(e): return e["text"] == line))
	t.check("...and unlocks 'Found again' and 'Where it was left'", keeper.moments.is_unlocked("idea_refound") and keeper.moments.is_unlocked("ghost_found"))
	t.check("the garden shows it growing again", keeper.ledger.stage_of("pottery") != IdeaLedger.Stage.WILTED and keeper.ledger.ideas["pottery"]["refound_by"] == "Pip")
	t.check("days in words", IdeaWords.number(90) == "ninety" and IdeaWords.number(23) == "twenty-three" and IdeaWords.number(1) == "one")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_album_ideas_lost.json"))

## The camp's pool of ideas outlives its people; leaving a camp used to teach
## a random one of them, so lost ideas came back unseen.
func _camp_pool(t) -> void:
	var g: ConceptGraph = t._graph()
	var s := SettlementSystem.Settlement.new()
	var here: Agent = t._adult(10, 10)
	s.member_ids = [here.agent_id]
	here.knowledge["fire"] = true
	t.check("a camp can show what a member still knows", SettlementSystem._member_holds(s, "fire", [here]))
	t.check("...not what only the dead knew", not SettlementSystem._member_holds(s, "pottery", [here]))

func _crafts_fragile(t) -> void:
	pass
