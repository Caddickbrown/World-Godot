class_name PropKit
extends RefCounted
## Builds many low-poly primitives into ONE vertex-coloured mesh, so a whole
## town's shrine, barn, walls and fields are one draw rather than hundreds of
## nodes. add_*() take a transform (local to the settlement) and a colour (graded
## for the look by the caller); commit() returns the ArrayMesh.

var _verts := PackedVector3Array()
var _norms := PackedVector3Array()
var _cols := PackedColorArray()
var _idx := PackedInt32Array()
static var _cache: Dictionary = {}   # primitive key -> mesh arrays

var parts := 0

static func _arrays(key: String, make: Callable) -> Array:
	if not _cache.has(key):
		var m: PrimitiveMesh = make.call()
		_cache[key] = m.get_mesh_arrays()
	return _cache[key]

static func clear_cache() -> void:
	_cache.clear()

func add_arrays(arr: Array, xf: Transform3D, col: Color) -> void:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var ix = arr[Mesh.ARRAY_INDEX]
	var base := _verts.size()
	var basis := xf.basis
	var nbasis := basis.inverse().transposed()
	for i in v.size():
		_verts.append(xf * v[i])
		_norms.append((nbasis * nm[i]).normalized())
		_cols.append(col)
	if ix is PackedInt32Array and (ix as PackedInt32Array).size() > 0:
		for i in (ix as PackedInt32Array):
			_idx.append(base + i)
	else:
		for i in v.size():
			_idx.append(base + i)
	parts += 1

func box(size: Vector3, xf: Transform3D, col: Color) -> void:
	var a := _arrays("box", func():
		var b := BoxMesh.new()
		b.size = Vector3.ONE
		return b)
	add_arrays(a, xf * Transform3D(Basis.from_scale(size), Vector3.ZERO), col)

## A cylinder (or cone when top = 0) of height h, standing on its base at xf's origin.
func cyl(top: float, bottom: float, h: float, xf: Transform3D, col: Color, segs: int = 8) -> void:
	var key := "cyl:%.3f:%d" % [top / maxf(bottom, 0.001), segs]
	var ratio := top / maxf(bottom, 0.001)
	var a := _arrays(key, func():
		var c := CylinderMesh.new()
		c.top_radius = ratio
		c.bottom_radius = 1.0
		c.height = 1.0
		c.radial_segments = segs
		c.rings = 1
		return c)
	add_arrays(a, xf * Transform3D(Basis.from_scale(Vector3(bottom, h, bottom)), Vector3(0, h * 0.5, 0)), col)

func ball(r: float, xf: Transform3D, col: Color, squash: float = 1.0) -> void:
	var a := _arrays("ball", func():
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = 8
		s.rings = 5
		return s)
	add_arrays(a, xf * Transform3D(Basis.from_scale(Vector3(r, r * squash, r)), Vector3.ZERO), col)

## A roof prism (ridge along x), size = (length, height, depth), sitting on xf's origin.
func prism(size: Vector3, xf: Transform3D, col: Color) -> void:
	var a := _arrays("prism", func():
		var p := PrismMesh.new()
		p.size = Vector3.ONE
		return p)
	add_arrays(a, xf * Transform3D(Basis.from_scale(size), Vector3(0, size.y * 0.5, 0)), col)

func is_empty() -> bool:
	return _verts.is_empty()

func commit() -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _verts
	arr[Mesh.ARRAY_NORMAL] = _norms
	arr[Mesh.ARRAY_COLOR] = _cols
	arr[Mesh.ARRAY_INDEX] = _idx
	var m := ArrayMesh.new()
	if not _verts.is_empty():
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

static func at(p: Vector3, yaw: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), p)
