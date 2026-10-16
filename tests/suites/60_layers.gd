extends RefCounted
## Tile layers (World.layer_*) and the native kernels (native/world_kernels).

func run(t) -> void:
	_layers(t)
	_parity(t)
	_no_stray_keys(t)

func _layers(t) -> void:
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
	var re := RegEx.create_from_string("\\[\"(resource|herbs|mushrooms)\"\\]|get\\(\"(resource|herbs|mushrooms)\"")
	for dir in ["res://scripts/simulation", "res://scripts/systems", "res://scripts/renderer", "res://scripts/ui", "res://scripts"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd") or f == "World.gd":
				continue
			var src := FileAccess.get_file_as_string(dir + "/" + f)
			if re.search(src):
				bad.append(f)
	t.check("no script reads layered fields off a tile (%s)" % ", ".join(bad), bad.is_empty())
