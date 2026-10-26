# tools/capture/Capture.gd
# Renders the game to a PNG so changes to the look can be reviewed without the editor.
#
#   godot --path . res://tools/capture/Capture.tscn -- --out=/tmp/shot.png [options]
#
# --seed=N        world seed (also seeds randf, so the same args give the same picture)
# --sim=S         run S game-seconds of simulation first, at 20x, without rendering
# --hour=H        then wind the clock forward to H o'clock and pause it
# --distance=D    observer camera distance (default: the game's 90)
# --tilt=DEG      observer camera tilt; --turn=RAD observer yaw
# --follow        follow (and select) the first living person
# --walk          walk among them, beside the followed person (or at the camera target)
# --listen        (with --walk) listen in on the nearest person
# --yaw=RAD       (with --walk) turn the walker's camera; --cam-distance=D its distance
# --weather=W     clear | rain | storm (set after the sim, cloud fully drawn in)
# --teach=A,B     give every founder these ideas before the sim (to show what they do)
# --burn          set the wood nearest the founders alight before the sim, and look there
# --camp          look at the biggest settlement (after --sim)
# --pair          look between the two nearest settlements (to compare their cultures)
# --animal=T      look at the nearest living animal of type T (deer, wolf, rabbit, ...)
# --wild=K        look at the first of the small wild things: whales | shoals | flocks |
#                 robins | butterflies | swarms | hives | frogs (AmbientLife)
# --season=S      start in spring | summer | autumn | winter (a few days in)
# --rainbow       stand a rainbow where the camera looks (after the sim)
# --disaster=D    drought | flood | blight round where the camera looks
# --rider         follow someone on horseback (after the sim; use --teach=horse_taming)
# --festival=K    hold festival K (midsummer | harvest | midwinter | mourning | planting) at the
#                 biggest camp (after --sim): teach it what it needs, wind to its day, let the
#                 camp gather until --hour (default 1.5 h in), and look there
# --no-hints      hide the HUD's "something's happening" hints
# --inspect       show the inspect card for whatever is where the camera looks
# --no-hud        hide the HUD
# --style=S       UI look: storybook | fieldnotes
# --screen=S      open a full screen: lives | ideas | album
# --twig          (with --screen=lives) open the life with the biggest family tree
# --album-tab=T   (with --screen=album) open a tab: all | firsts | people | ideas | world | pressed
# --press=N       press the N lives with the biggest families into the album first
# --tell          an elder at the fire tells a legend, and the camera looks at them
#                 (use with --hour=20; makes a legend if the world has none yet)
# Needs a display: tools/capture/shots.sh wraps itself in xvfb-run.
extends Node

var _t0 := 0

func _mark(what: String) -> void:
	if OS.get_environment("CAPTURE_PROFILE") != "":
		print("[Capture] %6d ms  %s" % [Time.get_ticks_msec() - _t0, what])

func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	var args := parse_args(OS.get_cmdline_user_args())
	var s := int(args.get("seed", "7"))
	seed(s)
	UiTheme.set_style(str(args.get("style", "storybook")))
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	main.world_seed = s
	main.album_path = "user://capture_album.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(main.album_path))
	add_child(main)
	_mark("main ready")
	await get_tree().process_frame
	_mark("first frame")

	if args.has("teach"):
		for a in main.agents:
			for id in str(args["teach"]).split(","):
				a.knowledge[id] = true
	var burn_at := Vector2(-1, -1)
	if args.has("burn"):
		var c := Vector2.ZERO
		for a in main.agents:
			c += a.pos
		c /= maxf(1.0, main.agents.size())
		var t: Dictionary = main.world.find_nearest(c.x, c.y, [World.TileType.FOREST], 40.0)
		if not t.is_empty():
			burn_at = Vector2(int(t["x"]) + 0.5, int(t["z"]) + 0.5)
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					main.fire_system.start_fire(int(t["x"]) + dx, int(t["z"]) + dz, 40.0, main.time_system.game_time, main.world)
	if args.has("season"):
		var si := TimeSystem.SEASONS.find(str(args["season"]).capitalize())
		if si >= 0:
			main.time_system.game_time = (si * TimeSystem.SEASON_DAYS + 2.5) * TimeSystem.DAY_LENGTH
	if args.has("sim"):
		main.time_system.set_speed(20.0)
		var steps := int(float(args["sim"]) / 20.0 * 30.0)
		for i in steps:
			main._process(1.0 / 30.0)
	var fest_focus := Vector2(-1, -1)
	if args.has("festival"):
		fest_focus = _hold_festival(main, str(args["festival"]), float(args.get("hour", "-1")))
		args.erase("hour")
	if args.has("hour"):
		var ts: TimeSystem = main.time_system
		var want := float(args["hour"]) / 24.0
		var now := ts.time_of_day
		ts.game_time += fposmod(want - now, 1.0) * TimeSystem.DAY_LENGTH
	main.time_system.set_speed(0.0)
	main._process(0.0)
	if args.has("weather"):
		var wx := {"clear": WeatherSystem.WeatherType.CLEAR, "rain": WeatherSystem.WeatherType.RAIN,
			"storm": WeatherSystem.WeatherType.STORM}
		var wt := int(wx.get(str(args["weather"]), WeatherSystem.WeatherType.CLEAR))
		for row in main.weather_system._zones:
			for z in row: z.state = wt
		main.weather_system.current = wt
		main.sky.overcast = {"rain": 0.6, "storm": 1.0}.get(str(args["weather"]), 0.0)
		main._update_sun()
	main._update_sun()
	main._update_hud()

	var obs: ObserverCamera = main.observer
	if args.has("distance"): obs.distance = float(args["distance"])
	if args.has("tilt"): obs.angle_v = deg_to_rad(float(args["tilt"]))
	if args.has("turn"): obs.angle_h = float(args["turn"])
	var who: Agent = null
	for a in main.agents:
		if not a.is_dead and a.health > 0.0:
			who = a
			break
	if args.has("rider"):
		for a in main.agents:
			if not a.is_dead and a.riding_horse_id >= 0:
				who = a
				break
		if who and who.riding_horse_id >= 0:
			main.follow(who)
			obs.look_at_point(Vector3(who.pos.x, 0, who.pos.y) * World.TILE_SIZE)
	if who and (args.has("follow") or args.has("walk")):
		main.follow(who)
		obs.look_at_point(Vector3(who.pos.x, 0, who.pos.y) * World.TILE_SIZE)
	if burn_at.x >= 0.0:
		obs.look_at_point(Vector3(burn_at.x, 0, burn_at.y) * World.TILE_SIZE)
	if args.has("camp") or args.has("town"):
		var big = null
		for st in main.settlement_system.get_settlements():
			if big == null or st.member_ids.size() > big.member_ids.size():
				big = st
		if big and args.has("town"):
			# Everything a town can put up, to see the layout whole.
			big.tier = 2
			for id in ["masonry", "agriculture", "temple", "church", "barn", "woodworking", "irrigation",
					"coop", "herding", "ritual"]:
				big.knowledge_pool[id] = true
			main._update_settlements()
		if big:
			obs.look_at_point(Vector3(big.centre.x, 0, big.centre.y) * World.TILE_SIZE)
			print("[Capture] camp %s: %d people, tier %d, timber %.0f" % [big.name, big.member_ids.size(), big.tier, big.wood_store])
	if fest_focus.x >= 0.0:
		obs.look_at_point(Vector3(fest_focus.x, 0, fest_focus.y) * World.TILE_SIZE)
		if not args.has("distance"): obs.distance = 30.0
	if args.has("tell"):
		var teller := _tell_legend(main)
		if teller:
			who = teller
			main.follow(teller)
			obs.look_at_point(Vector3(teller.pos.x, 0, teller.pos.y) * World.TILE_SIZE)
	if args.has("press"):
		for id in _big_families(main).slice(0, int(args["press"])):
			main.story.press_life(id, main.lineage_tracker, main.world.seed_val)
	if args.has("pair"):
		# Two neighbouring camps side by side, to compare their ways (feat/cultures).
		var all: Array = main.settlement_system.get_settlements()
		var best_d := INF
		var pick: Array = []
		for i in all.size():
			for j in range(i + 1, all.size()):
				var dd: float = all[i].centre.distance_to(all[j].centre)
				if dd < best_d:
					best_d = dd
					pick = [all[i], all[j]]
		if not pick.is_empty():
			var mid: Vector2 = (pick[0].centre + pick[1].centre) * 0.5
			obs.look_at_point(Vector3(mid.x, 0, mid.y) * World.TILE_SIZE)
			for st in pick:
				print("[Capture] %s (%d people): %s" % [st.name, st.member_ids.size(), st.culture.describe() if st.culture else "-"])
	var look_tile := Vector2(obs.target.x, obs.target.z) / World.TILE_SIZE
	if args.has("disaster"):
		var kinds := {"drought": DisasterSystem.DisasterType.DROUGHT, "flood": DisasterSystem.DisasterType.FLOOD,
			"blight": DisasterSystem.DisasterType.BLIGHT}
		if kinds.has(str(args["disaster"])):
			# A flood picks its own place (a river or low shore); the others go
			# where the camera looks.
			var flood := str(args["disaster"]) == "flood"
			main.disaster_system.start(kinds[str(args["disaster"])], main.time_system.day, main.history_log, main.world,
				Vector2(-1, -1) if flood else look_tile)
			if flood:
				var fc: Vector2 = main.disaster_system.centre
				obs.look_at_point(Vector3(fc.x, 0, fc.y) * World.TILE_SIZE)
			main.disaster_system.remaining_time = main.disaster_system.duration * 0.5   # at its height
			main.disaster_system.apply(main.world, main.agents)
			main._flush_tile_changes()
			main.terrain_renderer.flush_all()
	if args.has("rainbow"):
		main.weather_system.force_rainbow(look_tile.x, look_tile.y)
		main.weather_system._rainbow_timer = WeatherSystem.RAINBOW_SECONDS * 0.6   # fully up
	if args.has("rainbow") or args.has("disaster") or args.has("season"):
		main._update_sun()
	if args.has("no-wild") and main.ambient_renderer:
		main.ambient_renderer.visible = false
	if args.has("wild") and main.ambient_life:
		var list = main.ambient_life.get(str(args["wild"]))
		if list is Array and not list.is_empty() and "pos" in list[0]:
			var pick = list[0]
			for it in list:   # a whale at the surface, not one deep in a dive
				if not ("y" in it) or float(it.y) > -1.5:
					pick = it
					break
			if "y" in pick and float(pick.y) < -1.5 and "state" in pick:
				# None up just now: bring this one to the surface for the shot
				# (ambient life only; the people's world is untouched).
				main.ambient_life._whale_state(pick, AmbientLife.WhaleState.SURFACE, 30.0)
				pick.y = -0.45
			var p: Vector2 = pick.pos
			obs.look_at_point(Vector3(p.x, 0, p.y))
			print("[Capture] wild %s at %s%s" % [args["wild"], str(p), (" y %.2f" % float(pick.y)) if "y" in pick else ""])
	if args.has("animal"):
		var want := str(args["animal"]).to_upper()
		var pick = null
		for an in main.animal_sim.animals:
			if an.state == AnimalSim.AnimalState.DEAD or AnimalSim.AnimalType.keys()[an.animal_type] != want:
				continue
			if pick == null:
				pick = an
			var t: Dictionary = main.world.get_tile_f(an.pos.x, an.pos.y)
			if not t.is_empty() and int(t["type"]) == World.TileType.GRASS:
				pick = an   # out in the open, not lost in the trees
				break
		if pick:
			obs.look_at_point(Vector3(pick.pos.x, 0, pick.pos.y) * World.TILE_SIZE)
	obs.apply()

	if args.has("walk"):
		main.set_view_mode(main.ViewMode.WALK)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var w: Wanderer = main.wanderer
		if who:
			w.place_at(who.pos + Vector2(1.2, 1.2))
		w.cam_yaw += float(args.get("yaw", "0"))
		if args.has("cam-distance"): w.cam_distance = float(args["cam-distance"])
		if who:
			# Face the walker toward the person so they're in frame.
			var to := (who.pos - w.tile_pos)
			w.model.rotation.y = atan2(to.x, to.y)
			w.cam_yaw = atan2(-to.x, -to.y) + float(args.get("yaw", "0"))
		if args.has("listen"):
			who.pos = w.tile_pos + Vector2(-0.9, -0.9)
			who.target = who.pos
			main.listen_to_nearest()
		w.step(0.0, Vector2.ZERO, false)
		main._update_view_overlays()
		main.agent_renderer.update()

	var hud := main.get_node_or_null("HUD")
	if hud and hud.has_method("build"):
		UiTheme.set_style(str(args.get("style", "storybook")))  # over any saved look
		hud.build()
		main._update_hud()
		if args.has("screen"):
			if str(args["screen"]) == "look":
				hud.open_look(true)
			else:
				hud.open_screen(str(args["screen"]))
				if args.has("twig") and hud.screen is LifeStoryScreen:
					var fams := _big_families(main)
					if not fams.is_empty():
						hud.screen._chosen = fams[0]
						hud.screen._rebuild()
				if args.has("album-tab") and hud.screen is AlbumScreen:
					hud.screen._tab = str(args["album-tab"])
					hud.screen._rebuild()
		if args.has("inspect"):
			hud.show_inspect(Inspect.describe(main, main.observer.target))
	if args.has("no-hud") and hud:
		hud.visible = false
	if args.has("no-hints") and hud and hud.get("hints"):
		hud.hints.visible = false
	main._update_hud()
	_mark("set up")
	for i in int(args.get("frames", "8")):
		await get_tree().process_frame
		_mark("frame %d" % i)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out: String = args.get("out", "user://capture.png")
	var err := img.save_png(out)
	print("[Capture] %s %s" % [out, "ok" if err == OK else "FAILED %d" % err])
	get_tree().quit(0 if err == OK else 1)

## Sets the biggest camp up to keep `kind`, winds the clock to its day and
## runs the world (at 20x) until `hour` (default 1.5 hours in) with it under way.
func _hold_festival(main: Node, kind: String, hour: float) -> Vector2:
	if not FestivalSystem.KINDS.has(kind):
		return Vector2(-1, -1)
	var big = null
	for st in main.settlement_system.get_settlements():
		if big == null or st.member_ids.size() > big.member_ids.size():
			big = st
	if big == null:
		print("[Capture] no camp for a festival (use --sim)")
		return Vector2(-1, -1)
	var r: Dictionary = FestivalSystem.KINDS[kind]
	for id in r["all"] + (r["any"] as Array).slice(0, 1) + ["calendar", "music"]:
		big.knowledge_pool[id] = true
	if kind == "mourning":
		main.festival_system._dead[big.id] = ["Aru", "Belen", "Cosi"]
	var ts: TimeSystem = main.time_system
	var year := FestivalSystem.year_of(ts.day)
	var day := FestivalSystem.day_of(big, kind, year)
	if day < ts.day:
		day = FestivalSystem.day_of(big, kind, year + 1)
	ts.game_time = (float(day - 1) + (float(r["start"]) + 0.1) / 24.0) * TimeSystem.DAY_LENGTH
	var want := hour if hour >= 0.0 else float(r["start"]) + 1.5
	ts.set_speed(20.0)
	for i in 600:
		main._process(1.0 / 30.0)
		if ts.hour >= want or ts.day > day:
			break
	var f: Dictionary = main.festival_system.festival_of(big.id)
	print("[Capture] festival %s at %s, day %d %.1fh: %d there" % [kind, big.name, ts.day, ts.hour,
		(f.get("people", []) as Array).size()])
	return f.get("focus", big.centre)

static func parse_args(raw: PackedStringArray) -> Dictionary:
	var out := {}
	for a in raw:
		if not a.begins_with("--"): continue
		var kv := a.substr(2).split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else "true"
	return out

## Ids in the story with the most relatives in the register, most first.
static func _big_families(main: Node) -> Array:
	var lt: LineageTracker = main.lineage_tracker
	var scored: Array = []
	for id in main.story.lives:
		var p := lt.person(int(id))
		if p.is_empty():
			continue
		var n: int = lt.ancestors(int(id), 1).size() + lt.ancestors(int(id), 2).size() + lt.descendants(int(id), 1).size() \
			+ lt.descendants(int(id), 2).size() + (1 if int(p["partner"]) >= 0 else 0) + (3 if lt.is_legend(int(id)) else 0)
		scored.append([n, int(id)])
	scored.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	return scored.map(func(x): return x[1])

## Have an elder at a fire tell a legend (a capture's set-up, like --teach).
static func _tell_legend(main: Node) -> Agent:
	var lt: LineageTracker = main.lineage_tracker
	var elders: Array = main.agents.filter(func(a): return not a.is_dead and a.at_fire)
	if elders.is_empty():
		elders = main.agents.filter(func(a): return not a.is_dead and a.is_adult)
	if elders.is_empty():
		return null
	var teller: Agent = elders[0]
	for a in elders:
		if a.is_elderly:
			teller = a
			break
	var lid := lt._legend_for(teller)
	if lid < 0:
		# No legend this elder knows yet: let them remember a dead relative or
		# the oldest of the dead as one.
		for id in lt.people:
			var p: Dictionary = lt.people[id]
			if int(p["died_day"]) >= 0 and not lt.is_legend(int(id)):
				lt.legends[int(id)] = {"id": int(id), "name": p["name"], "deed": "lived to a great age",
					"camp": -1, "camp_name": "", "day": int(p["died_day"]), "knew": {teller.agent_id: true},
					"heard": {}, "myth": false, "faded": false, "told": 0}
				lid = int(id)
				break
	if lid < 0:
		return null
	lt._tell(teller, lid, main.agents)
	print("[Capture] %s tells: %s" % [teller.agent_name, teller.speech_bubble])
	return teller
