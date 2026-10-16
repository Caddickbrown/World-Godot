extends SceneTree
## The same regrowth pass (World.update_resources, every row) three ways:
## tiles as Dictionaries (today), packed arrays in GDScript, packed arrays in
## Rust (native/world_kernels), plus what one read costs each way.
## godot --headless --path . --script res://tools/bench_kernels.gd

const REPS := 40

func _init() -> void:
	var w := World.new(7)
	var n: int = w.width * w.height
	print("grid %dx%d = %d tiles" % [w.width, w.height, n])
	var d := 0.016 * 8.0 * 1.5
	# Put the fields back on the Dictionaries, as they were before the layers.
	for z in w.height:
		for x in w.width:
			var tile: Dictionary = w.tiles[z][x]
			tile["resource"] = 0.2
			tile["herbs"] = w.layer_herbs[z * w.width + x]
			tile["mushrooms"] = w.layer_mushrooms[z * w.width + x]
	# 1. Dictionaries, as World does it now.
	var t0 := Time.get_ticks_usec()
	for r in REPS:
		for z in w.height:
			for x in w.width:
				var tile: Dictionary = w.tiles[z][x]
				match tile["type"]:
					World.TileType.GRASS:    tile["resource"] = minf(1.0, tile["resource"] + 0.0020 * d)
					World.TileType.WOODLAND: tile["resource"] = minf(1.0, tile["resource"] + 0.0016 * d)
					World.TileType.FOREST:   tile["resource"] = minf(1.0, tile["resource"] + 0.0012 * d)
				if tile["herbs"] >= 0.0:
					tile["herbs"] = minf(1.0, tile["herbs"] + 0.0006 * d)
				if tile["mushrooms"] >= 0.0:
					tile["mushrooms"] = minf(1.0, tile["mushrooms"] + 0.0008 * d)
	var dict_us := float(Time.get_ticks_usec() - t0) / REPS
	# The same data as packed layers.
	var res := PackedFloat32Array(); res.resize(n)
	var hb := PackedFloat32Array(); hb.resize(n)
	var mu := PackedFloat32Array(); mu.resize(n)
	var ty := PackedByteArray(); ty.resize(n)
	for z in w.height:
		for x in w.width:
			var tile: Dictionary = w.tiles[z][x]
			var i: int = z * w.width + x
			res[i] = 0.2; hb[i] = tile["herbs"]; mu[i] = tile["mushrooms"]; ty[i] = int(tile["type"])
	var gres := res.duplicate(); var ghb := hb.duplicate(); var gmu := mu.duplicate()
	# 2. Packed arrays, GDScript.
	t0 = Time.get_ticks_usec()
	for r in REPS:
		for i in n:
			var g := 0.0
			match ty[i]:
				3: g = 0.0020
				4: g = 0.0016
				5: g = 0.0012
			if g > 0.0:
				gres[i] = minf(1.0, gres[i] + g * d)
			if ghb[i] >= 0.0:
				ghb[i] = minf(1.0, ghb[i] + 0.0006 * d)
			if gmu[i] >= 0.0:
				gmu[i] = minf(1.0, gmu[i] + 0.0008 * d)
	var packed_us := float(Time.get_ticks_usec() - t0) / REPS
	# 3. Packed arrays, Rust (copy in and out included).
	if not ClassDB.class_exists("Kernels"):
		print("Rust library not loaded (build native/world_kernels)")
		quit()
		return
	var k: Object = ClassDB.instantiate("Kernels")
	t0 = Time.get_ticks_usec()
	for r in REPS:
		var out: Array = k.regrow(res, hb, mu, ty, w.width, 0, 1, d)
		res = out[0]; hb = out[1]; mu = out[2]
	var rust_us := float(Time.get_ticks_usec() - t0) / REPS
	var same := true
	for i in n:
		if absf(res[i] - gres[i]) > 1e-4 or absf(hb[i] - ghb[i]) > 1e-4:
			same = false
			break
	# Single reads, as Agent code does them (100k each).
	var sum := 0.0
	t0 = Time.get_ticks_usec()
	for j in 100000:
		var tile: Dictionary = w.tiles[(j * 7) % w.height][(j * 13) % w.width]
		sum += float(tile["resource"])
	var read_dict := float(Time.get_ticks_usec() - t0) / 100.0
	t0 = Time.get_ticks_usec()
	for j in 100000:
		sum += res[((j * 7) % w.height) * w.width + (j * 13) % w.width]
	var read_packed := float(Time.get_ticks_usec() - t0) / 100.0
	t0 = Time.get_ticks_usec()
	for j in 100000:
		sum += k.read_at(res, ((j * 7) % w.height) * w.width + (j * 13) % w.width)
	var read_rust := float(Time.get_ticks_usec() - t0) / 100.0
	print("one read: dictionary %.0f ns, packed %.0f ns, call into Rust %.0f ns" % [read_dict, read_packed, read_rust])
	print("dictionaries, GDScript: %8.0f us" % dict_us)
	print("packed, GDScript:       %8.0f us  (%.1fx)" % [packed_us, dict_us / packed_us])
	print("packed, Rust:           %8.0f us  (%.1fx)  same result: %s" % [rust_us, dict_us / rust_us, same])
	quit()
