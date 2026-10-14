# Renders the art mockup (scripts/mockup/ArtMockup.gd). Positions are relative
# to the founders' camp so every seed frames its own people.
#   godot --path . res://tools/capture/Mockup.tscn -- --out=x.png [--seed=7] [--hour=10]
#        [--cam=dx,dy,dz] [--look=dx,dy,dz] [--tilt=1] [--fov=40]
extends Node

func _ready() -> void:
	var args := parse_args()
	var mock := Node3D.new()
	mock.set_script(load("res://scripts/mockup/ArtMockup.gd"))
	add_child(mock)
	mock.build(int(args.get("seed", "7")))
	mock.set_hour(float(args.get("hour", "10")))
	var c: Vector3 = mock.camp_centre
	var cam := c + _v(args.get("cam", "30,22,30"))
	var look := c + _v(args.get("look", "0,0,0"))
	if args.has("fov"): mock.camera.fov = float(args["fov"])
	mock.frame(cam, look, float(args.get("tilt", "0")))
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var out: String = args.get("out", "user://mockup.png")
	var err := get_viewport().get_texture().get_image().save_png(out)
	print("[Capture] %s %s" % [out, "ok" if err == OK else "FAILED"])
	get_tree().quit()

func _v(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))

func parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"): continue
		var kv := a.substr(2).split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else "true"
	return out
