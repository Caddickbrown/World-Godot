class_name EnvironmentRenderer
extends Node3D
## Flora and rocks, drawn the way docs/ART_DIRECTION.md asks: pines (stacked
## cones) on forest tiles, round broadleaf trees in woodland and dotted over
## meadows, berry bushes, rocks on stony ground.
##
## The woods change (ForestSystem): trees grow from seedlings, are felled to
## stumps, burn to black snags, spread into meadows and are planted. So trees
## are drawn from each tile's live state, in 16x16-tile chunks of MultiMeshes,
## and a chunk is rebuilt when one of its tiles changes. Where a tree stands on
## a tile is fixed by the world seed, so a regrown wood comes back in place.
## Bushes and rocks don't change and are built once.

const TILE_SIZE := World.TILE_SIZE
const CHUNK := 16                  # tiles per side of a flora chunk
const REBUILDS_PER_FRAME := 3
const TREE_PARTS := ["pine_lo", "pine_hi", "trunk", "crown", "crown_small", "stump", "snag"]
const TRUNK_COL := Color(0.42, 0.29, 0.20)
const CHAR_COL := Color(0.06, 0.055, 0.05)

var _world: World
var _field: Heightfield
var _meshes: Dictionary = {}       # part -> Mesh
var _mats: Dictionary = {}         # part -> material
var _chunks: Dictionary = {}       # Vector2i chunk -> {part: MultiMeshInstance3D}
var _dirty: Dictionary = {}        # Vector2i chunk -> true
## "x,z" -> [n trees standing, n stumps, n snags] as last drawn (tests read this)
var _shown: Dictionary = {}

func setup(world: World) -> void:
	_world = world
	_field = world.heightfield
	clear()
	_meshes = {
		"pine_lo": _cone(1.3, 2.6), "pine_hi": _cone(0.95, 2.0), "trunk": _trunk(),
		"crown": _ball(1.2), "crown_small": _ball(0.8), "stump": _stump(), "snag": _trunk(),
		"bush": _ball(0.8), "rock": _rock(),
	}
	_build_static()
	var nx := int(ceil(float(world.width) / CHUNK))
	var nz := int(ceil(float(world.height) / CHUNK))
	for cz in nz:
		for cx in nx:
			_rebuild_chunk(Vector2i(cx, cz))

func clear() -> void:
	for ch in get_children():
		ch.queue_free()
	_chunks.clear()
	_dirty.clear()
	_shown.clear()
	_mats.clear()

## A tile's trees changed: redraw its chunk soon (a few chunks a frame).
func mark_dirty(x: int, z: int) -> void:
	_dirty[Vector2i(x / CHUNK, z / CHUNK)] = true

## Redraw a few waiting chunks; Main calls this every frame.
func flush(budget: int = REBUILDS_PER_FRAME) -> void:
	var n := 0
	for c in _dirty.keys():
		if n >= budget:
			break
		_dirty.erase(c)
		_rebuild_chunk(c)
		n += 1

## Redraw a tile's chunk now.
func refresh_tile(x: int, z: int) -> void:
	_dirty.erase(Vector2i(x / CHUNK, z / CHUNK))
	_rebuild_chunk(Vector2i(x / CHUNK, z / CHUNK))

## Older name, kept for Main.
func remove_tree_at(x: int, z: int) -> void:
	refresh_tile(x, z)

func trees_shown_on(x: int, z: int) -> bool:
	return int((_shown.get("%d,%d" % [x, z], [0, 0, 0]) as Array)[0]) > 0

func stumps_shown_on(x: int, z: int) -> int:
	return int((_shown.get("%d,%d" % [x, z], [0, 0, 0]) as Array)[1])

func snags_shown_on(x: int, z: int) -> int:
	return int((_shown.get("%d,%d" % [x, z], [0, 0, 0]) as Array)[2])

## How many trees this tile holds when grown (0 for open ground).
func tree_count_on(x: int, z: int) -> int:
	var tile := _world.get_tile(x, z)
	if tile.is_empty():
		return 0
	var n := 0
	for slot in _slots(x, z, tile):
		if slot["kind"] != "":
			n += 1
	return n

# ── Trees ────────────────────────────────────────────────────────────────────

## Where trees may stand on a tile, fixed by the seed: [{p, h, yaw, s, kind, tint}].
## kind: "pine" | "broad" | "meadow" | "" (no tree in this slot for this tile type).
func _slots(x: int, z: int, tile: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(x, z, _world.seed_val))
	var t := int(tile["type"])
	var planted := bool(tile.get("planted", false))
	var burnt := float(tile.get("burnt", 0.0)) > 0.0
	var nat := LookStyle.naturalist()
	var out: Array = []
	var slots := 2 if (t == World.TileType.FOREST or planted or burnt) and rng.randf() < 0.5 else 1
	for k in slots:
		var px := (x + rng.randf_range(0.1, 0.9)) * TILE_SIZE
		var pz := (z + rng.randf_range(0.1, 0.9)) * TILE_SIZE
		var roll := rng.randf()
		var yaw := rng.randf() * TAU
		var size := rng.randf()
		var tint_r := rng.randf()
		var odd := rng.randf()
		var h := _field.height_at(px, pz)
		var nrm := _field.normal_at(px, pz)
		var clump := sin(px * 0.11 + pz * 0.07) * cos(pz * 0.13 - px * 0.05) * 0.5 + 0.5
		var kind := ""
		if h >= 0.6 and nrm.y >= 0.7:
			# Woods have clearings: people must stay visible from the sky.
			if t == World.TileType.FOREST and roll < 0.42 + clump * 0.35:
				kind = "pine"
			elif t == World.TileType.WOODLAND and (roll < 0.16 + clump * 0.24 or (planted and roll < 0.7)):
				kind = "broad"
			elif t == World.TileType.GRASS and roll < 0.09 * clump:
				kind = "meadow"
			elif burnt and roll < 0.55:
				kind = "snag"
		var tint: Color
		var s: float
		if kind == "pine":
			s = lerpf(0.8, 1.35, size) * (1.25 if nat else 1.0)
			tint = Color(0.16, 0.36, 0.20).lerp(Color(0.26, 0.45, 0.22), tint_r)
		else:
			s = lerpf(0.7, 1.1, size)
			tint = Color(0.36, 0.58, 0.24).lerp(Color(0.58, 0.68, 0.26), tint_r * 0.6)
			if odd < 0.025 and not nat:
				tint = Color(0.86, 0.55, 0.22)  # the odd tree turning early
		out.append({"p": Vector3(px, h, pz), "yaw": yaw, "s": s, "kind": kind, "tint": tint})
	return out

func _rebuild_chunk(c: Vector2i) -> void:
	var data: Dictionary = {}
	for part in TREE_PARTS:
		data[part] = {"xf": [], "col": []}
	for z in range(c.y * CHUNK, mini((c.y + 1) * CHUNK, _world.height)):
		for x in range(c.x * CHUNK, mini((c.x + 1) * CHUNK, _world.width)):
			_draw_tile(x, z, data)
	var nodes: Dictionary = _chunks.get(c, {})
	for part in TREE_PARTS:
		var d: Dictionary = data[part]
		var inst: MultiMeshInstance3D = nodes.get(part)
		if d["xf"].is_empty():
			if inst:
				inst.visible = false
			continue
		if inst == null:
			inst = MultiMeshInstance3D.new()
			inst.material_override = _material(part)
			add_child(inst)
			nodes[part] = inst
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _meshes[part]
		mm.instance_count = d["xf"].size()
		for i in mm.instance_count:
			mm.set_instance_transform(i, d["xf"][i])
			mm.set_instance_color(i, d["col"][i])
		inst.multimesh = mm
		inst.visible = true
	_chunks[c] = nodes

func _draw_tile(x: int, z: int, data: Dictionary) -> void:
	var tile: Dictionary = _world.tiles[z][x]
	var key := "%d,%d" % [x, z]
	var stump := bool(tile.get("tree_cut", false))
	var burnt := float(tile.get("burnt", 0.0)) > 0.0
	# Growth is drawn in steps (ForestSystem marks a tile when it crosses one).
	var g := 1.0
	if World.has_woods(tile) and float(tile.get("growth", 1.0)) >= 0.0:
		g = floorf(clampf(float(tile.get("growth", 1.0)), 0.0, 1.0) * ForestSystem.VISUAL_STEPS) / ForestSystem.VISUAL_STEPS
	var counts := [0, 0, 0]
	for slot in _slots(x, z, tile):
		var kind: String = slot["kind"]
		if kind == "":
			continue
		var p: Vector3 = slot["p"]
		var b := Basis(Vector3.UP, float(slot["yaw"]))
		var s: float = slot["s"]
		if kind == "snag":
			var ss := s * 0.9
			_add(data, "snag", Transform3D(b.scaled(Vector3(ss * 0.8, ss * 2.4, ss * 0.8)), p + Vector3(0, 1.1 * ss, 0)), CHAR_COL)
			counts[2] += 1
			continue
		if stump and kind != "meadow":
			_add(data, "stump", Transform3D(b.scaled(Vector3(s, s, s)), p + Vector3(0, 0.15 * s, 0)), TRUNK_COL.lightened(0.15))
			counts[1] += 1
			continue
		if burnt:
			continue   # meadow trees on burnt ground are gone too
		# A seedling is a knee-high sprig; a grown tree is full size.
		var f := lerpf(0.16, 1.0, g if kind != "meadow" else 1.0)
		s *= f
		var tint: Color = slot["tint"]
		if f < 0.5:
			tint = tint.lightened(0.12)   # young leaves are fresher
		var blight := float(tile.get("blight", 0.0))
		if blight > 0.0:
			tint = tint.lerp(LookStyle.BLIGHT, blight * 0.8)   # DisasterSystem: sick, grey woods
		if kind == "pine":
			_add(data, "pine_lo", Transform3D(b.scaled(Vector3(s, s, s)), p + Vector3(0, 1.6 * s, 0)), tint)
			if f > 0.35:
				_add(data, "pine_hi", Transform3D(b.scaled(Vector3(s, s, s)), p + Vector3(0, 3.0 * s, 0)), tint.lightened(0.08))
			_add(data, "trunk", Transform3D(b.scaled(Vector3(s, s, s)), p + Vector3(0, 0.5 * s, 0)), TRUNK_COL)
		else:
			_add(data, "trunk", Transform3D(b.scaled(Vector3(s, s * 1.4, s)), p + Vector3(0, 0.7 * s, 0)), TRUNK_COL)
			_add(data, "crown", Transform3D(b.scaled(Vector3(s, s * 0.9, s)), p + Vector3(0, 2.4 * s, 0)), tint)
			if f > 0.35:
				_add(data, "crown_small", Transform3D(b.scaled(Vector3(s, s * 0.8, s)), p + Vector3(0.6 * s, 2.0 * s, 0.3 * s)), tint.darkened(0.08))
		counts[0] += 1
	if counts == [0, 0, 0]:
		_shown.erase(key)
	else:
		_shown[key] = counts

func _add(data: Dictionary, part: String, xf: Transform3D, col: Color) -> void:
	var d: Dictionary = data[part]
	d["xf"].append(xf)
	d["col"].append(LookStyle.g(col))

## Every part shares the season shader (shaders/flora_season.gdshader): the
## year turns through its uniforms (set_season), never a chunk rebuild.
const PART_KIND := {"crown": 0, "crown_small": 0, "pine_lo": 1, "pine_hi": 1, "bush": 2,
	"trunk": 3, "stump": 3, "snag": 3, "rock": 3}
var _season: Dictionary = {}

func _material(part: String) -> ShaderMaterial:
	if _mats.has(part):
		return _mats[part]
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/flora_season.gdshader")
	mat.set_shader_parameter("kind", int(PART_KIND.get(part, 3)))
	# Anything right in front of the camera dithers away, so walking through a
	# wood the trees never swallow the view (the sky camera is never this close).
	mat.set_shader_parameter("fade_min", 1.5)
	mat.set_shader_parameter("fade_max", 5.0)
	SeasonLook.apply(mat, _season)
	_mats[part] = mat
	return mat

## The season's look (SeasonLook.blend) for every flora material. Cheap: a
## handful of uniforms, applied only when something moved.
func set_season(b: Dictionary) -> void:
	var changed := _season.is_empty()
	for k in b:
		if absf(float(b[k]) - float(_season.get(k, -1.0))) > 0.004:
			changed = true
	if not changed:
		return
	_season = b.duplicate()
	for part in _mats:
		SeasonLook.apply(_mats[part], _season)

func season_value(key: String) -> float:
	return float(_season.get(key, 0.0))

# ── Bushes and rocks (they don't change) ─────────────────────────────────────

func _build_static() -> void:
	var data := {"bush": {"xf": [], "col": []}, "rock": {"xf": [], "col": []}}
	var rng := RandomNumberGenerator.new()
	rng.seed = _world.seed_val + 17
	for z in _world.height:
		for x in _world.width:
			var t := int(_world.tiles[z][x]["type"])
			var px := (x + rng.randf_range(0.1, 0.9)) * TILE_SIZE
			var pz := (z + rng.randf_range(0.1, 0.9)) * TILE_SIZE
			var roll := rng.randf()
			var b := Basis(Vector3.UP, rng.randf() * TAU)
			var sz := rng.randf()
			var h := _field.height_at(px, pz)
			var nrm := _field.normal_at(px, pz)
			if h < 0.6:
				continue
			if t == World.TileType.GRASS and roll < 0.12 and nrm.y >= 0.7:
				var s := lerpf(0.5, 0.9, sz)
				var berry := float(_world.tiles[z][x].get("resource", 0.0)) > 0.5 and rng.randf() < 0.5
				_add(data, "bush", Transform3D(b.scaled(Vector3(s, s * 0.7, s)), Vector3(px, h + 0.2, pz)),
					Color(0.42, 0.45, 0.24) if berry else Color(0.30, 0.50, 0.22))
			elif (t == World.TileType.STONE or t == World.TileType.MOUNTAIN or nrm.y < 0.8) and roll < 0.18:
				var s := lerpf(0.5, 1.6, sz)
				_add(data, "rock", Transform3D(b.scaled(Vector3(s * 1.3, s * 0.8, s)), Vector3(px, h + 0.1, pz)),
					LookStyle.ROCK.lerp(LookStyle.ROCK_DARK, rng.randf()))
	for part in data:
		var d: Dictionary = data[part]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _meshes[part]
		mm.instance_count = d["xf"].size()
		for i in mm.instance_count:
			mm.set_instance_transform(i, d["xf"][i])
			mm.set_instance_color(i, d["col"][i])
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		inst.material_override = _material(part)
		add_child(inst)

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

static func _stump() -> CylinderMesh:
	var t := CylinderMesh.new()
	t.top_radius = 0.2
	t.bottom_radius = 0.26
	t.height = 0.3
	t.radial_segments = 7
	return t

static func _rock() -> SphereMesh:
	var r := SphereMesh.new()
	r.radius = 0.6
	r.height = 1.0
	r.radial_segments = 5
	r.rings = 3
	return r
