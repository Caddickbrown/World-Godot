class_name EnvironmentRenderer
extends Node3D
## Flora and rocks, drawn the way docs/ART_DIRECTION.md asks: pines (stacked
## cones) on forest tiles, round broadleaf trees in woodland and dotted over
## meadows, berry bushes, rocks on stony ground. Built from primitives into
## MultiMeshes, one entry per tile so felled trees vanish (and regrow) exactly
## where the simulation says.

const TILE_SIZE := World.TILE_SIZE

var _world: World
var _field: Heightfield
## Per part: {mm: MultiMesh, xforms: Array}; parts are built once, then
## instances are hidden (zero scale) or shown per tile.
var _parts: Dictionary = {}
## "x,z" -> [[part_name, index], ...] for the trees on that tile
var _tile_trees: Dictionary = {}
var _hidden: Dictionary = {}       # "x,z" -> true while that tile's trees are felled

func setup(world: World) -> void:
	_world = world
	_field = world.heightfield
	clear()
	_populate()

func clear() -> void:
	for ch in get_children():
		ch.queue_free()
	_parts.clear()
	_tile_trees.clear()
	_hidden.clear()

func _populate() -> void:
	var nat := LookStyle.naturalist()
	var defs := {
		"pine_lo": _cone(1.3, 2.6), "pine_hi": _cone(0.95, 2.0), "trunk": _trunk(),
		"crown": _ball(1.2), "crown_small": _ball(0.8), "bush": _ball(0.8), "rock": _rock(),
	}
	var data: Dictionary = {}
	for k in defs:
		data[k] = {"xf": [], "col": []}
	var rng := RandomNumberGenerator.new()
	rng.seed = _world.seed_val
	var trunk_col := Color(0.42, 0.29, 0.20)
	for z in _world.height:
		for x in _world.width:
			var tile: Dictionary = _world.tiles[z][x]
			var t := int(tile["type"])
			# Forests get a second chance at a tree, so they read as forest.
			var slots := 2 if t == World.TileType.FOREST and rng.randf() < 0.5 else 1
			for k in slots:
				var px := (x + rng.randf_range(0.1, 0.9)) * TILE_SIZE
				var pz := (z + rng.randf_range(0.1, 0.9)) * TILE_SIZE
				var h := _field.height_at(px, pz)
				var nrm := _field.normal_at(px, pz)
				var roll := rng.randf()
				var yaw := rng.randf() * TAU
				var b := Basis(Vector3.UP, yaw)
				var clump := sin(px * 0.11 + pz * 0.07) * cos(pz * 0.13 - px * 0.05) * 0.5 + 0.5
				var key := "%d,%d" % [x, z]
				if h < 0.6 or nrm.y < 0.7:
					continue
				# Woods have clearings: people must stay visible from the sky.
				if t == World.TileType.FOREST and roll < 0.42 + clump * 0.35:
					var s := rng.randf_range(0.8, 1.35) * (1.25 if nat else 1.0)
					var tint := Color(0.16, 0.36, 0.20).lerp(Color(0.26, 0.45, 0.22), rng.randf())
					_add(data, key, "pine_lo", Transform3D(b.scaled(Vector3(s, s, s)), Vector3(px, h + 1.6 * s, pz)), tint)
					_add(data, key, "pine_hi", Transform3D(b.scaled(Vector3(s, s, s)), Vector3(px, h + 3.0 * s, pz)), tint.lightened(0.08))
					_add(data, key, "trunk", Transform3D(b.scaled(Vector3(s, s, s)), Vector3(px, h + 0.5 * s, pz)), trunk_col)
				elif (t == World.TileType.WOODLAND and roll < 0.16 + clump * 0.24) or (t == World.TileType.GRASS and roll < 0.03 * clump * 3.0):
					var s := rng.randf_range(0.7, 1.1)
					var tint := Color(0.36, 0.58, 0.24).lerp(Color(0.58, 0.68, 0.26), rng.randf() * 0.6)
					if rng.randf() < 0.025 and not nat:
						tint = Color(0.86, 0.55, 0.22)  # the odd tree turning early
					_add(data, key, "trunk", Transform3D(b.scaled(Vector3(s, s * 1.4, s)), Vector3(px, h + 0.7 * s, pz)), trunk_col)
					_add(data, key, "crown", Transform3D(b.scaled(Vector3(s, s * 0.9, s)), Vector3(px, h + 2.4 * s, pz)), tint)
					_add(data, key, "crown_small", Transform3D(b.scaled(Vector3(s, s * 0.8, s)), Vector3(px + 0.6 * s, h + 2.0 * s, pz + 0.3 * s)), tint.darkened(0.08))
				elif t == World.TileType.GRASS and roll < 0.12:
					var s := rng.randf_range(0.5, 0.9)
					var berry := bool(tile.get("resource", 0.0) > 0.5) and rng.randf() < 0.5
					_add(data, "", "bush", Transform3D(b.scaled(Vector3(s, s * 0.7, s)), Vector3(px, h + 0.2, pz)),
						Color(0.42, 0.45, 0.24) if berry else Color(0.30, 0.50, 0.22))
				elif (t == World.TileType.STONE or t == World.TileType.MOUNTAIN or nrm.y < 0.8) and roll < 0.18:
					var s := rng.randf_range(0.5, 1.6)
					_add(data, "", "rock", Transform3D(b.scaled(Vector3(s * 1.3, s * 0.8, s)), Vector3(px, h + 0.1, pz)),
						LookStyle.ROCK.lerp(LookStyle.ROCK_DARK, rng.randf()))
	for k in defs:
		_build_part(k, defs[k], data[k])
	# Tiles that start felled
	for key in _tile_trees:
		var p: PackedStringArray = key.split(",")
		refresh_tile(int(p[0]), int(p[1]))

func _add(data: Dictionary, key: String, part: String, xf: Transform3D, col: Color) -> void:
	var d: Dictionary = data[part]
	if key != "":
		if not _tile_trees.has(key):
			_tile_trees[key] = []
		_tile_trees[key].append([part, d["xf"].size()])
	d["xf"].append(xf)
	d["col"].append(LookStyle.g(col))

func _build_part(name: String, mesh: Mesh, d: Dictionary) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = d["xf"].size()
	for i in mm.instance_count:
		mm.set_instance_transform(i, d["xf"][i])
		mm.set_instance_color(i, d["col"][i])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.9
	# Anything right in front of the camera dithers away, so walking through a
	# wood the trees never swallow the view (the sky camera is never this close).
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	mat.distance_fade_min_distance = 1.5
	mat.distance_fade_max_distance = 5.0
	inst.material_override = mat
	add_child(inst)
	_parts[name] = {"mm": mm, "xforms": d["xf"]}

## Show or hide a tile's trees to match the simulation (felled or regrown).
func refresh_tile(x: int, z: int) -> void:
	var key := "%d,%d" % [x, z]
	if not _tile_trees.has(key):
		return
	var tile := _world.get_tile(x, z)
	var cut := bool(tile.get("tree_cut", false))
	if cut:
		_hidden[key] = true
	else:
		_hidden.erase(key)
	for entry in _tile_trees[key]:
		var part: Dictionary = _parts[entry[0]]
		var xf: Transform3D = part["xforms"][entry[1]]
		if cut:
			xf = Transform3D(Basis().scaled(Vector3.ZERO), xf.origin)
		(part["mm"] as MultiMesh).set_instance_transform(entry[1], xf)

## Older name, kept for Main.
func remove_tree_at(x: int, z: int) -> void:
	refresh_tile(x, z)

func trees_shown_on(x: int, z: int) -> bool:
	return tree_count_on(x, z) > 0 and not _hidden.has("%d,%d" % [x, z])

func tree_count_on(x: int, z: int) -> int:
	return (_tile_trees.get("%d,%d" % [x, z], []) as Array).size()

static func _cone(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 7
	c.rings = 1
	return c

static func _ball(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 1.8
	s.radial_segments = 8
	s.rings = 5
	return s

static func _trunk() -> CylinderMesh:
	var t := CylinderMesh.new()
	t.top_radius = 0.12
	t.bottom_radius = 0.18
	t.height = 1.0
	t.radial_segments = 6
	return t

static func _rock() -> SphereMesh:
	var r := SphereMesh.new()
	r.radius = 0.6
	r.height = 1.0
	r.radial_segments = 5
	r.rings = 3
	return r
