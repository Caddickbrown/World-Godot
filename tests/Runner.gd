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
	_test_wanderer_movement()
	print("== integration")
	await _test_main_views()
	print("== %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

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

# ── Integration ──────────────────────────────────────────────────────────────

func _test_main_views() -> void:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for i in 5:
		await get_tree().process_frame
	check("Main builds a world", main.world != null and main.agents.size() == main.AGENT_COUNT)
	var adults: int = main.agents.filter(func(a): return a.life_stage == "adult").size()
	check("founders arrive as adults (%d/%d)" % [adults, main.agents.size()], adults == main.agents.size())
	check("the observer starts in charge", main.observer.active and main.observer.camera.current)

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
	# Stand right beside them and listen in.
	who.pos = main.wanderer.tile_pos + Vector2(0.8, 0)
	who.target = who.pos + Vector2(3, 0)
	who.state = Agent.State.WANDERING
	var near: Agent = main.nearest_agent_to_wanderer()
	check("someone beside you is in reach", near != null)
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

	# A reset mid-walk must not leave the wanderer in charge of a dead camera.
	main.set_view_mode(main.ViewMode.WALK)
	main._init_world()
	await get_tree().process_frame
	check("reset returns to the observer", main.view_mode == main.ViewMode.OBSERVE and main.observer.active)
	main.queue_free()
	await get_tree().process_frame
