extends RefCounted
## Tile layers (World.layer_*) and the native kernels (native/world_kernels).

func run(t) -> void:
	_layers(t)
	_parity(t)
	_terrain_parity(t)
	_flora_parity(t)
	_no_stray_keys(t)

## The native flora builder stands the same trees, same size and colour, as
## the GDScript one: felled, burnt, planted, blighted, growing, cleared.
func _flora_parity(t) -> void:
	if World.kernels == null:
		return
	var w := World.new(7)
	w.heightfield = Heightfield.new().build(w)
	var f: Vector2i = t._first_tile(w, [World.TileType.FOREST])
	var c := Vector2i(f.x / EnvironmentRenderer.CHUNK, f.y / EnvironmentRenderer.CHUNK)
	var k := 0
	for z in range(c.y * 16, c.y * 16 + 16):
		for x in range(c.x * 16, c.x * 16 + 16):
			var tile := w.get_tile(x, z)
			if tile.is_empty() or not World.has_woods(tile):
				continue
			k += 1
			match k % 6:
				1: tile["tree_cut"] = true
				2: tile["burnt"] = 30.0
				3: tile["planted"] = true
				4: tile["blight"] = 0.5
				5: tile["growth"] = 0.3
	var env := EnvironmentRenderer.new()
	t.add_child(env)
	env.setup(w)
	env.set_clearings(PackedVector3Array([Vector3((c.x * 16 + 8) * World.TILE_SIZE, (c.y * 16 + 8) * World.TILE_SIZE, 5.0)]))
	var worst := 0.0
	var instances := 0
	var counts_same := true
	var was: String = UiTheme.style
	for style in ["storybook", "fieldnotes"]:
		UiTheme.set_style(style)
		env.setup(w)
		env._clearings = {c: PackedVector3Array([Vector3((c.x * 16 + 8) * World.TILE_SIZE, (c.y * 16 + 8) * World.TILE_SIZE, 5.0)])}
		var out: Array = env._builder.callv("chunk", env._chunk_input(c))
		var shown_native := {}
		var counts: PackedInt32Array = out[EnvironmentRenderer.TREE_PARTS.size()]
		var data: Dictionary = {}
		for part in EnvironmentRenderer.TREE_PARTS:
			data[part] = {"xf": [], "col": []}
		env._shown.clear()
		for z in range(c.y * 16, c.y * 16 + 16):
			for x in range(c.x * 16, c.x * 16 + 16):
				env._draw_tile(x, z, data)
		for i in counts.size() / 3:
			var key := "%d,%d" % [c.x * 16 + i % 16, c.y * 16 + i / 16]
			var mine: Array = env._shown.get(key, [0, 0, 0])
			if mine != [counts[i * 3], counts[i * 3 + 1], counts[i * 3 + 2]]:
				counts_same = false
		for j in EnvironmentRenderer.TREE_PARTS.size():
			var part: String = EnvironmentRenderer.TREE_PARTS[j]
			var a: PackedFloat32Array = out[j]
			var b := EnvironmentRenderer.pack(data[part]["xf"], data[part]["col"])
			if a.size() != b.size():
				worst = INF
				continue
			instances += a.size() / 16
			for i in a.size():
				worst = maxf(worst, absf(a[i] - b[i]))
	UiTheme.set_style(was)
	t.check("native flora matches GDScript: %d instances, worst %.5f, counts the same" % [instances, worst],
		instances > 50 and worst < 2e-3 and counts_same)
	t.remove_child(env)
	env.free()

## The native terrain mesher draws the same ground as the GDScript one: every
## colour rule (felled, river, depletion, drought, blight, camps, both looks).
func _terrain_parity(t) -> void:
	if World.kernels == null:
		return
	var w := World.new(7)
	w.heightfield = Heightfield.new().build(w)
	var m: Vector2i = t._first_tile(w, [World.TileType.GRASS])
	for d in range(-3, 4):
		var tile := w.get_tile(m.x + d, m.y)
		if tile.is_empty():
			continue
		tile["drought"] = 0.6
		tile["blight"] = 0.3 if d % 2 == 0 else 0.0
		tile["tree_cut"] = d == 1
		tile["river"] = d == -2
		w.set_depletion(tile, 0.5)
	var tr := TerrainRenderer.new()
	t.add_child(tr)
	tr.setup(w)
	tr.set_camps([Vector2(m.x, m.y) * World.TILE_SIZE])
	var chunk := Vector2i(int(m.x * World.TILE_SIZE / TerrainRenderer.CHUNK_M), int(m.y * World.TILE_SIZE / TerrainRenderer.CHUNK_M))
	var worst := [0.0, 0.0, 0.0]
	var was: String = UiTheme.style
	for style in ["storybook", "fieldnotes"]:
		UiTheme.set_style(style)
		tr._sync_palette()
		for c in [chunk, Vector2i(0, 0), Vector2i(tr.chunk_count - 1, tr.chunk_count - 1)]:
			var a: Array = tr._chunk_arrays(c)
			var b: Array = tr._chunk_arrays_gd(c)
			for i in (a[0] as PackedVector3Array).size():
				worst[0] = maxf(worst[0], (a[0][i] - b[0][i]).length())
				worst[1] = maxf(worst[1], (a[1][i] - b[1][i]).length())
				var ca: Color = a[2][i]
				var cb: Color = b[2][i]
				worst[2] = maxf(worst[2], maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b))))
	UiTheme.set_style(was)
	t.check("native terrain matches GDScript: position %.5f, normal %.5f, colour %.5f" % worst,
		worst[0] < 1e-3 and worst[1] < 1e-3 and worst[2] < 2e-3)
	t.remove_child(tr)
	tr.free()

func _layers(t) -> void:
	var rolls := [World.roll(1, 2, 3), World.roll(1, 2, 4), World.roll(4000000000, 16383, 5)]
	t.check("rolls fall in [0, 1) and differ", rolls.all(func(r): return r >= 0.0 and r < 1.0) and rolls[0] != rolls[1])
	var mean := 0.0
	for i in 4000:
		mean += World.roll(99, i, 0)
	t.check("...and are even (mean %.3f)" % (mean / 4000.0), absf(mean / 4000.0 - 0.5) < 0.03)
	var w := World.new(7)
	var m: Vector2i = t._first_tile(w, [World.TileType.GRASS])
	var tile := w.get_tile(m.x, m.y)
	t.check("layered fields have left the tile Dictionaries", not tile.has("resource") and not tile.has("herbs"))
	w.set_food(tile, 0.1)
	t.check("food reads back through the layer", absf(w.food_of(tile) - 0.1) < 1e-6 and absf(w.tile_value(tile, "resource") - 0.1) < 1e-6)
	w.set_type(tile, World.TileType.DESERT)
	t.check("set_type keeps the type layer in step", w.layer_type[m.y * w.width + m.x] == World.TileType.DESERT)
	w.set_type(tile, World.TileType.GRASS)
	w.set_food(tile, 0.0)
	for i in World.STRIPE_COUNT:
		w.update_resources(1.0, "summer")
	t.check("grass grows its food back", w.food_of(tile) > 0.0)
	w.set_depletion(tile, 0.9)
	t.check("a stripped tile is depleted", w.is_depleted(tile))
	for i in World.STRIPE_COUNT:
		w.update_depletion(30.0)
	t.check("...and recovers", w.depletion_of(tile) < 0.9)

## The native pass and the GDScript one give the same world.
func _parity(t) -> void:
	if World.kernels == null:
		print("  (native kernels not built: parity skipped; native/build.sh)")
		return
	var a := World.new(11)
	var b := World.new(11)
	for w in [a, b]:
		for i in w.layer_resource.size():
			w.layer_resource[i] = fmod(i * 0.37, 1.0)
	var keep: Object = World.kernels
	for step in World.STRIPE_COUNT * 3:
		World.kernels = keep
		a.update_resources(0.5, "spring")
		World.kernels = null
		b.update_resources(0.5, "spring")
	World.kernels = keep
	# Forest spread: the same events, roll for roll.
	var w := World.new(5)
	var p := 0.2   # high odds, so a pass makes plenty of events to compare
	var ev_n: PackedInt32Array = keep.forest_spread(w.layer_type, w.width, 12345, p, p, p)
	var ev_g := EcologySystem.forest_spread_gd(w.layer_type, w.width, 12345, p, p, p)
	t.check("native forest spread makes the same %d events as GDScript" % (ev_n.size() / 3), ev_n.size() > 30 and ev_n == ev_g)
	var w2 := World.new(5)
	var f := PackedFloat32Array()
	f.resize(w2.width * w2.height)
	for i in f.size():
		f[i] = [0.5, 0.01, -1.0, 0.0, 0.3][i % 5]
	var faded: PackedFloat32Array = keep.fade(f.duplicate(), w2.width, 0, 1, 0.05)
	World.kernels = null
	var faded_gd := w2.fade_layer(f.duplicate(), 0, 1, 0.05)
	World.kernels = keep
	var fade_same := true
	for i in f.size():
		if absf(faded[i] - faded_gd[i]) > 1e-6: fade_same = false
	t.check("native fade matches GDScript, and leaves -1 (not gathered) alone", fade_same and faded[2] == -1.0 and faded[1] == 0.0)
	var worst := 0.0
	for i in a.layer_resource.size():
		worst = maxf(worst, absf(a.layer_resource[i] - b.layer_resource[i]))
		worst = maxf(worst, absf(a.layer_herbs[i] - b.layer_herbs[i]))
		worst = maxf(worst, absf(a.layer_mushrooms[i] - b.layer_mushrooms[i]))
	t.check("native regrowth matches GDScript (worst %.7f)" % worst, worst < 1e-5)

## Nothing reads a layered field from a tile Dictionary (it would get the
## default and quietly be wrong).
func _no_stray_keys(t) -> void:
	var bad: Array = []
	var re := RegEx.create_from_string("\\[\"(resource|herbs|mushrooms|depletion_level)\"\\]|get\\(\"(resource|herbs|mushrooms|depletion_level)\"")
	for dir in ["res://scripts/simulation", "res://scripts/systems", "res://scripts/renderer", "res://scripts/ui", "res://scripts/look", "res://scripts"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd") or f == "World.gd":
				continue
			var src := FileAccess.get_file_as_string(dir + "/" + f)
			if re.search(src):
				bad.append(f)
	t.check("no script reads layered fields off a tile (%s)" % ", ".join(bad), bad.is_empty())
