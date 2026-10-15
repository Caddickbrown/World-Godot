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
	while main.time_system.day <= days and not main.game_over:
		main._process(1.0 / 60.0)
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
	quit()
