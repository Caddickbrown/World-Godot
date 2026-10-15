class_name PathRenderer
extends Node3D
## Worn paths: the footfall counts PathSystem keeps (World.trade_traffic),
## drawn as bare earth on the ground. A separate layer, not a slab: it is
## built on the Heightfield's own 1 m grid, with the terrain's own triangle
## split, a few centimetres up, and blends in by vertex alpha, so it lies on
## the ground like paint (docs/LESSONS.md: "never a slab on top"). Owns no
## terrain colour; LookStyle.TRAMPLED (graded for the look) is the earth.
##
## Rebuilt at most every REBUILD_SECONDS, and only when PathSystem's revision
## moved; and then only the CHUNK-sized squares whose wear changed. Paths
## change slowly, so most rebuilds touch a square or two: one whole-map mesh
## cost 50-80 ms on a busy island, a hitch every REBUILD_SECONDS.

const TILE_SIZE := World.TILE_SIZE
const WEAR_START := 4.0            # footfalls before a tile shows at all
const WEAR_FULL := 22.0            # ...and when it is a beaten path
const LIFT := 0.035                # metres above the ground
const REBUILD_SECONDS := 1.5       # real seconds between rebuilds at most
const SPREAD := 1.35               # metres a tile's wear reaches past its centre
const CHUNK := 16                  # tiles per side of a mesh square
const WEAR_STEPS := 10.0           # wear is quantised this finely to decide a square changed
const SQUARES_PER_PASS := 3        # at most this many squares rebuilt a pass; the rest next pass
const CATCH_UP_SECONDS := 0.2      # how soon the next pass comes while squares are left over

var world: World
var _material: StandardMaterial3D
var _revision := -1
var _cooldown := 0.0
var _chunks: Dictionary = {}       # Vector2i chunk -> MeshInstance3D
var _sigs: Dictionary = {}         # Vector2i chunk -> PackedInt32Array of what it was built from
## Tiles drawn at the last rebuild (Vector2i -> wear 0..1), for tests and the
## inspect card. The headless renderer keeps no mesh data (docs/LESSONS.md).
var shown: Dictionary = {}
## Squares rebuilt by the last rebuild, for tests.
var rebuilt := 0
## Squares that changed but wait for the next pass.
var pending := 0
var _budget := -1                  # squares a rebuild may do (-1: all, as tests and restyles want)

func _ready() -> void:
	restyle()

func restyle() -> void:
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.roughness = 1.0
	_material.render_priority = -1
	# Colours are baked from the look, so every square is rebuilt.
	_sigs.clear()
	_revision = -1

## Redraw if the wear has changed (cheap to call every frame). real_delta:
## real seconds since the last call (not game time: the cooldown is about
## frame cost, and a faster world wears paths faster anyway).
func sync(paths: PathSystem, real_delta: float) -> void:
	if paths == null or world == null:
		return
	_cooldown -= real_delta
	if paths.revision == _revision or _cooldown > 0.0:
		return
	_revision = paths.revision
	_cooldown = REBUILD_SECONDS
	_budget = SQUARES_PER_PASS
	rebuild()
	if pending > 0:
		_revision = -1
		_cooldown = CATCH_UP_SECONDS

func rebuild() -> void:
	shown.clear()
	rebuilt = 0
	pending = 0
	if world == null:
		return
	var field: Heightfield = world.heightfield
	for key in world.trade_traffic:
		var p: PackedStringArray = str(key).split(",")
		var w := clampf((float(world.trade_traffic[key]) - WEAR_START) / (WEAR_FULL - WEAR_START), 0.0, 1.0)
		if w > 0.0:
			shown[Vector2i(int(p[0]), int(p[1]))] = w
	if field == null:
		return
	# Which tiles reach each square: its own, and those whose wear spreads in
	# from just over its edge.
	var margin := int(ceil(SPREAD / TILE_SIZE)) + 1
	var groups: Dictionary = {}    # chunk -> PackedInt32Array [x, z, q, ...]
	for t in shown:
		var q := int(round(float(shown[t]) * WEAR_STEPS))
		var c0 := Vector2i(floori(float(t.x - margin) / CHUNK), floori(float(t.y - margin) / CHUNK))
		var c1 := Vector2i(floori(float(t.x + margin) / CHUNK), floori(float(t.y + margin) / CHUNK))
		for cz in range(c0.y, c1.y + 1):
			for cx in range(c0.x, c1.x + 1):
				var c := Vector2i(cx, cz)
				if not groups.has(c):
					groups[c] = PackedInt32Array()
				var g: PackedInt32Array = groups[c]
				g.append_array([t.x, t.y, q])
				groups[c] = g
	# Squares with no wear left.
	for c in _chunks.keys():
		if not groups.has(c):
			_chunks[c].queue_free()
			_chunks.erase(c)
			_sigs.erase(c)
	for c in groups:
		var g: PackedInt32Array = groups[c]
		if _sigs.has(c) and _sigs[c] == g:
			continue
		if _budget >= 0 and rebuilt >= _budget:
			pending += 1
			continue
		_sigs[c] = g
		rebuilt += 1
		var mesh := _build_chunk(c, g, field)
		if not _chunks.has(c):
			var mi := MeshInstance3D.new()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_chunks[c] = mi
		_chunks[c].mesh = mesh
		_chunks[c].material_override = _material
	_budget = -1

## One square's mesh: splat its tiles' wear onto the 1 m vertices round each,
## then every cell with a weighted corner becomes two triangles, split the way
## the terrain splits its own (TerrainRenderer._build_chunk), so they lie flat
## on it. Flat packed grids local to the square.
func _build_chunk(c: Vector2i, g: PackedInt32Array, field: Heightfield) -> ArrayMesh:
	var step := Heightfield.STEP
	var n := field.n
	var hs: PackedFloat32Array = field.heights
	var per := int(round(CHUNK * TILE_SIZE / step))     # cells per side
	var vx0 := c.x * per
	var vz0 := c.y * per
	var side := per + 1                                  # vertices per side
	var weight := PackedFloat32Array()
	weight.resize(side * side)
	var cell_on := PackedByteArray()
	cell_on.resize(per * per)
	var cells := PackedInt32Array()
	var reach := int(ceil((TILE_SIZE * 0.5 + SPREAD) / step))
	var inner := TILE_SIZE * 0.35
	var outer := TILE_SIZE * 0.5 + SPREAD
	var inner2 := inner * inner
	var outer2 := outer * outer
	# Cells (and vertices) of this square that lie on the heightfield.
	var lx1 := mini(per, n - 1 - vx0)
	var lz1 := mini(per, n - 1 - vz0)
	for k in range(0, g.size(), 3):
		var cx: float = (g[k] + 0.5) * TILE_SIZE
		var cz: float = (g[k + 1] + 0.5) * TILE_SIZE
		var w: float = g[k + 2] / WEAR_STEPS
		var ix0 := int(round(cx / step)) - vx0
		var iz0 := int(round(cz / step)) - vz0
		for iz in range(maxi(0, iz0 - reach), mini(lz1, iz0 + reach) + 1):
			var dz := (iz + vz0) * step - cz
			for ix in range(maxi(0, ix0 - reach), mini(lx1, ix0 + reach) + 1):
				var dx := (ix + vx0) * step - cx
				var d2 := dx * dx + dz * dz
				if d2 >= outer2:
					continue
				var a := w if d2 <= inner2 else w * (1.0 - smoothstep(inner, outer, sqrt(d2)))
				var i := iz * side + ix
				if a <= weight[i]:
					continue
				weight[i] = a
				# The (up to) four cells of this square this vertex is a corner of.
				var ci := iz * per + ix
				if ix < lx1 and iz < lz1 and cell_on[ci] == 0:
					cell_on[ci] = 1; cells.append(ci)
				if ix > 0 and iz < lz1 and cell_on[ci - 1] == 0:
					cell_on[ci - 1] = 1; cells.append(ci - 1)
				if ix < lx1 and iz > 0 and cell_on[ci - per] == 0:
					cell_on[ci - per] = 1; cells.append(ci - per)
				if ix > 0 and iz > 0 and cell_on[ci - per - 1] == 0:
					cell_on[ci - per - 1] = 1; cells.append(ci - per - 1)
	if cells.is_empty():
		return null
	var earth := LookStyle.g(LookStyle.TRAMPLED.darkened(0.08))
	var dust := LookStyle.g(LookStyle.TRAMPLED.lightened(0.12))
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var index := PackedInt32Array()
	var vid := PackedInt32Array()
	vid.resize(side * side)
	vid.fill(-1)
	var ids := PackedInt32Array()
	ids.resize(4)
	for ci in cells:
		var cxl: int = ci % per
		var czl: int = ci / per
		var base := czl * side + cxl
		var corners := [base, base + 1, base + side, base + side + 1]
		for k in 4:
			var v: int = corners[k]
			if vid[v] < 0:
				var lx: int = v % side
				var lz: int = v / side
				var gx := lx + vx0
				var gz := lz + vz0
				var gi := gz * n + gx
				var x: float = gx * step
				var z: float = gz * step
				var a: float = weight[v]
				# A little grain so a path frays at its edges, from position only.
				var grain := 0.5 + 0.5 * sin(x * 2.3 + z * 1.7) * cos(z * 2.9 - x * 0.7)
				var col := earth.lerp(dust, grain * 0.6)
				col.a = clampf(a * (0.78 + 0.22 * grain), 0.0, 0.92)
				# On grid points: read the samples, no bilinear lookups.
				var hl: float = hs[gi - 1] if gx > 0 else hs[gi]
				var hr: float = hs[gi + 1] if gx < n - 1 else hs[gi]
				var hu: float = hs[gi - n] if gz > 0 else hs[gi]
				var hd: float = hs[gi + n] if gz < n - 1 else hs[gi]
				vid[v] = verts.size()
				verts.append(Vector3(x, hs[gi] + LIFT, z))
				normals.append(Vector3(hl - hr, 2.0 * step, hu - hd).normalized())
				colors.append(col)
			ids[k] = vid[v]
		# corners: 0 = (ix, iz), 1 = (ix+1, iz), 2 = (ix, iz+1), 3 = (ix+1, iz+1)
		index.append_array([ids[0], ids[1], ids[2], ids[1], ids[3], ids[2]])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = index
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Wear shown on a tile (0 = none), for the inspect card.
func wear_at(x: int, z: int) -> float:
	return float(shown.get(Vector2i(x, z), 0.0))
