extends SceneTree
func _init() -> void:
	seed(7)
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	main.world_seed = 7
	root.add_child(main)
	await process_frame
	await process_frame
	main._process(0.1)
	var n := 0
	for an in main.animal_sim.animals:
		var e: Dictionary = main.animal_renderer._instances.get(an.anim_id, {})
		var node: Node3D = e.get("node")
		print(AnimalSim.AnimalType.keys()[an.animal_type], " sim ", an.pos * 2.0, " node ", node.global_position, " scale ", node.scale.x, " h ", AnimalRenderer._model_height(node) * node.scale.y, " inside ", node.is_inside_tree(), " vis ", node.is_visible_in_tree())
		n += 1
		if n > 6: break
	quit()
