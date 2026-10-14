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
# --no-hud        hide the HUD
# Needs a display: tools/capture/shots.sh wraps itself in xvfb-run.
extends Node

func _ready() -> void:
	var args := parse_args(OS.get_cmdline_user_args())
	var s := int(args.get("seed", "7"))
	seed(s)
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	main.world_seed = s
	add_child(main)
	await get_tree().process_frame

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

	if args.has("no-hud"):
		var hud := main.get_node_or_null("HUD")
		if hud: hud.visible = false
	main._update_hud()
	for i in int(args.get("frames", "8")):
		await get_tree().process_frame
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
