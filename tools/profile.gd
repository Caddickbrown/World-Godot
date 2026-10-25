extends SceneTree
## Where a simulated frame's time goes. Runs the real Main headless (no GPU:
## renderer cost here is CPU-side only) for --days at --speed, then prints
## each stage's share. godot --headless --path . --script res://tools/profile.gd -- --days=6

func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var days := int(args.get("days", "6"))
	var speed := float(args.get("speed", "20"))
	seed(int(args.get("seed", "1")))
	var t0 := Time.get_ticks_usec()
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	main.world_seed = int(args.get("seed", "1"))
	main.album_path = "user://profile_album.json"
	root.add_child(main)
	await process_frame
	var boot := Time.get_ticks_usec() - t0
	main.time_system.set_speed(speed)
	main.profiling = true
	var frames := 0
	var t1 := Time.get_ticks_usec()
	var report_day := 2
	var worst: Array = []   # [usec, day, hour, {stage: usec}]
	var hitch_ms := float(args.get("hitch", "50"))
	var hitches := 0
	while main.time_system.day <= days and not main.game_over:
		var f0 := Time.get_ticks_usec()
		main._process(1.0 / 60.0)
		var ft := Time.get_ticks_usec() - f0
		if ft > hitch_ms * 1000.0:
			hitches += 1
		if worst.size() < 12 or ft > int(worst[-1][0]):
			worst.append([ft, main.time_system.day, main.time_system.hour, main.frame_profile.duplicate()])
			worst.sort_custom(func(a, b): return a[0] > b[0])
			if worst.size() > 12:
				worst.pop_back()
		frames += 1
		if main.time_system.day >= report_day:
			report_day += 2
			var alive: int = main.agents.filter(func(a): return not a.is_dead).size()
			print("  day %d: %d people, %d animals, %.2f ms/frame so far" % [main.time_system.day, alive,
				main.animal_sim.animals.size(), float(Time.get_ticks_usec() - t1) / frames / 1000.0])
	var total := Time.get_ticks_usec() - t1
	print("boot (world, heightfield, flora, renderers): %.0f ms" % (boot / 1000.0))
	print("%d frames at %.0fx: %.2f ms per frame (%.0f%% of a 16.7 ms frame at 60 fps)" % [frames, speed,
		float(total) / frames / 1000.0, float(total) / frames / 16667.0 * 100.0])
	var rows: Array = []
	for k in main.profile:
		rows.append([int(main.profile[k]), k])
	rows.sort()
	rows.reverse()
	for r in rows:
		print("  %5.1f%%  %6.3f ms  %s" % [100.0 * r[0] / total, float(r[0]) / frames / 1000.0, r[1]])
	print("frames over %.0f ms: %d of %d" % [hitch_ms, hitches, frames])
	print("worst frames:")
	for w in worst:
		var parts: Array = []
		var st: Dictionary = w[3]
		var keys := st.keys()
		keys.sort_custom(func(a, b): return st[a] > st[b])
		for k in keys.slice(0, 3):
			parts.append("%s %.1f" % [k, st[k] / 1000.0])
		print("  %6.1f ms  day %d %02d:00  %s" % [w[0] / 1000.0, w[1], int(w[2]), ", ".join(parts)])
	quit()
