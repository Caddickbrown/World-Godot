extends RefCounted
## Save and continue (SaveGame): a world saved, run on, then loaded is the
## world as it was saved, and it carries on.

const PATH := "user://test_save.bin"

func run(t) -> void:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	main.world_seed = 9
	main.album_path = "user://test_save_album.json"
	t.add_child(main)
	main.time_system.set_speed(20.0)
	for i in 900:
		main._process(1.0 / 60.0)
	var before := _fingerprint(main)
	t.check("a world saves", main.save_game(PATH) == "" and SaveGame.exists(PATH))
	for i in 300:
		main._process(1.0 / 60.0)
	t.check("...and runs on to somewhere else", _fingerprint(main) != before)
	var err: String = main.continue_game(PATH)
	var after := _fingerprint(main)
	t.check("loading it brings back the world as saved%s" % ("" if err == "" else " (" + err + ")"),
		err == "" and after == before)
	if after != before:
		for k in before:
			if before[k] != after.get(k):
				print("  differs: %s %s -> %s" % [k, before[k], after.get(k)])
	var shared := true
	for a in main.agents:
		shared = shared and a._concept_graph == main.concept_graph
	t.check("people point at the live systems, not copies", shared)
	for i in 900:
		main._process(1.0 / 60.0)
	var ids := {}
	for a in main.agents:
		ids[a.agent_id] = true
	t.check("...and it carries on: %d people, ids all different" % main.agents.size(),
		ids.size() == main.agents.size() and main.time_system.day >= int(before["day"]))
	t.remove_child(main)
	main.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))

func _fingerprint(main: Node) -> Dictionary:
	var names: Array = []
	var pos := Vector2.ZERO
	var known := 0
	for a in main.agents:
		names.append("%d:%s:%s" % [a.agent_id, a.agent_name, a.is_dead])
		pos += a.pos
		known += a.knowledge.size()
	return {
		"day": main.time_system.day,
		"time": snappedf(main.time_system.game_time, 0.01),
		"people": names,
		"pos": pos.snappedf(0.001),
		"known": known,
		"ideas": main.concept_graph.get_discovered_concepts().size(),
		"settlements": main.settlement_system.get_settlements().map(func(s): return "%s:%d:%d" % [s.name, s.tier, s.member_ids.size()]),
		"types": hash(main.world.layer_type),
		"food": snappedf(Array(main.world.layer_resource).reduce(func(acc, v): return acc + v, 0.0), 0.01),
		"chronicle": main.history_log.entries.size() if "entries" in main.history_log else -1,
		"animals": main.animal_sim.animals.size(),
		"next_id": Agent._next_id,
	}
