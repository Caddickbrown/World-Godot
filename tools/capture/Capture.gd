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
# --animal=T      look at the nearest living animal of type T (deer, wolf, rabbit, ...)
# --no-hud        hide the HUD
# --style=S       UI look: storybook | fieldnotes
# --screen=S      open a full screen: lives | ideas | album
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
	if args.has("sim"):
		main.time_system.set_speed(20.0)
		var steps := int(float(args["sim"]) / 20.0 * 30.0)
		for i in steps:
			main._process(1.0 / 30.0)
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
	if who and (args.has("follow") or args.has("walk")):
		main.follow(who)
		obs.look_at_point(Vector3(who.pos.x, 0, who.pos.y) * World.TILE_SIZE)
	if burn_at.x >= 0.0:
		obs.look_at_point(Vector3(burn_at.x, 0, burn_at.y) * World.TILE_SIZE)
	if args.has("camp"):
		var big = null
		for st in main.settlement_system.get_settlements():
			if big == null or st.member_ids.size() > big.member_ids.size():
				big = st
		if big:
			obs.look_at_point(Vector3(big.centre.x, 0, big.centre.y) * World.TILE_SIZE)
			print("[Capture] camp %s: %d people, tier %d, timber %.0f" % [big.name, big.member_ids.size(), big.tier, big.wood_store])
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
			hud.open_screen(str(args["screen"]))
	if args.has("no-hud") and hud:
		hud.visible = false
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

static func parse_args(raw: PackedStringArray) -> Dictionary:
	var out := {}
	for a in raw:
		if not a.begins_with("--"): continue
		var kv := a.substr(2).split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else "true"
	return out
