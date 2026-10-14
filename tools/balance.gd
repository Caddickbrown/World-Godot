extends SceneTree
# Balance probe: runs the real Main scene headless for several seeds and prints
# population per in-game day, so tuning is measured, not guessed.
#
#   godot --headless --path . --script res://tools/balance.gd -- [--days=12] [--seeds=1,2,3]
#        [--speed=20] [--dt=0.0167]  (sim speed and frame time; 20x at 60 fps by default)

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	var days := int(args.get("days", "12"))
	var speed := float(args.get("speed", "20"))   # game seconds per real second
	var dt := float(args.get("dt", str(1.0 / 60.0)))  # real seconds per frame
	var seeds: Array = str(args.get("seeds", "1,2,3")).split(",")
	for s in seeds:
		seed(int(s))
		var main: Node = load("res://scenes/Main.tscn").instantiate()
		main.world_seed = int(s)
		root.add_child(main)
		await process_frame
		main.time_system.set_speed(speed)
		var line := "seed %4s:" % s
		var last_day := 1
		var guard := 0
		while main.time_system.day <= days and not main.game_over and guard < 200000:
			main._process(dt)
			guard += 1
			if main.time_system.day != last_day:
				last_day = main.time_system.day
				line += " %d" % main.agents.filter(func(a): return not a.is_dead and a.health > 0.0).size()
		var causes := {}
		for a in main.agents:
			if a.is_dead:
				causes[a.death_cause] = int(causes.get(a.death_cause, 0)) + 1
		print(line, "  | ended day ", main.time_system.day, " discoveries ",
			main.concept_graph.get_discovered_concepts().size(), " deaths ", causes)
		main.queue_free()
		await process_frame
	quit()
