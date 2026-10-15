class_name HorseModel
extends RefCounted
## A horse built from primitives, in the same hand as the people: the horse
## FBX in the animal pack imports with no mesh at all. Faces +Z, stands
## ~1.7 m at the ears, origin at the hooves. animate() gives it a walk (four
## beats), a trot/gallop (diagonal pairs), a grazing neck and a swishing tail.

## Coats: chestnut, bay, grey, black, palomino, dun. [coat, mane/tail, muzzle]
const COATS := [
	[Color(0.62, 0.36, 0.20), Color(0.40, 0.22, 0.12), Color(0.30, 0.20, 0.15)],
	[Color(0.48, 0.30, 0.18), Color(0.12, 0.10, 0.09), Color(0.20, 0.15, 0.12)],
	[Color(0.78, 0.77, 0.74), Color(0.55, 0.54, 0.52), Color(0.40, 0.38, 0.37)],
	[Color(0.16, 0.14, 0.13), Color(0.08, 0.07, 0.07), Color(0.12, 0.10, 0.10)],
	[Color(0.86, 0.70, 0.42), Color(0.96, 0.92, 0.80), Color(0.55, 0.42, 0.30)],
	[Color(0.70, 0.58, 0.40), Color(0.25, 0.20, 0.15), Color(0.35, 0.28, 0.22)],
]
const HOOF := Color(0.18, 0.16, 0.15)
const HIP_Y := 0.95
const LEG_LEN := 0.9

static var _mats: Dictionary = {}

static func _mat(c: Color) -> StandardMaterial3D:
	var col := LookStyle.g(c)
	var key := col.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.9
		_mats[key] = m
	return _mats[key]

## The look changed: materials are rebuilt on the next build().
static func restyle() -> void:
	_mats.clear()

static func _part(parent: Node3D, mesh: Mesh, pos: Vector3, rot: Vector3, col: Color, scale := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.scale = scale
	mi.material_override = _mat(col)
	parent.add_child(mi)
	return mi

static func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 8
	c.rings = 2
	return c

static func _ball(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 8
	s.rings = 5
	return s

static func _cone(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 5
	c.rings = 1
	return c

## variant picks the coat (any int; the animal's id works).
static func build(variant: int) -> Node3D:
	var coat: Array = COATS[posmod(variant, COATS.size())]
	var body_c: Color = coat[0]
	var hair_c: Color = coat[1]
	var nose_c: Color = coat[2]
	var root := Node3D.new()
	root.name = "Horse"
	# Barrel, chest and quarters
	_part(root, _capsule(0.31, 1.4), Vector3(0, 1.08, 0), Vector3(PI / 2, 0, 0), body_c, Vector3(1.0, 1.0, 1.08))
	_part(root, _ball(0.34), Vector3(0, 1.12, 0.48), Vector3.ZERO, body_c, Vector3(1.0, 1.05, 1.0))
	_part(root, _ball(0.35), Vector3(0, 1.12, -0.5), Vector3.ZERO, body_c, Vector3(1.05, 1.0, 1.0))
	# Neck pivots at the withers so grazing can lower it.
	var neck := Node3D.new()
	neck.name = "Neck"
	neck.position = Vector3(0, 1.28, 0.58)
	root.add_child(neck)
	# The neck rises forward from the withers (axis up and toward +Z).
	_part(neck, _capsule(0.17, 0.85), Vector3(0, 0.3, 0.28), Vector3(0.75, 0, 0), body_c)
	_part(neck, BoxMesh.new(), Vector3(0, 0.36, 0.2), Vector3(0.75, 0, 0), hair_c, Vector3(0.05, 0.7, 0.1))   # mane
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.62, 0.56)
	neck.add_child(head)
	# The head runs forward and down from the poll to the muzzle.
	_part(head, _capsule(0.115, 0.58), Vector3(0, -0.12, 0.2), Vector3(-1.05, 0, 0), body_c)
	_part(head, _ball(0.09), Vector3(0, -0.25, 0.4), Vector3.ZERO, nose_c, Vector3(1.0, 0.9, 1.1))        # muzzle
	_part(head, _cone(0.04, 0.15), Vector3(0.06, 0.1, -0.02), Vector3(0.2, 0, -0.15), body_c)             # ears
	_part(head, _cone(0.04, 0.15), Vector3(-0.06, 0.1, -0.02), Vector3(0.2, 0, 0.15), body_c)
	_part(head, BoxMesh.new(), Vector3(0, 0.04, 0.06), Vector3(0.4, 0, 0), hair_c, Vector3(0.05, 0.1, 0.14))   # forelock
	# Tail pivots at the dock.
	var tail := Node3D.new()
	tail.name = "Tail"
	tail.position = Vector3(0, 1.2, -0.82)
	root.add_child(tail)
	_part(tail, _capsule(0.055, 0.62), Vector3(0, -0.27, -0.09), Vector3(0.35, 0, 0), hair_c, Vector3(1.3, 1.0, 1.0))
	# Legs pivot at hip and shoulder; order FL, FR, BL, BR.
	var legs := Node3D.new()
	legs.name = "Legs"
	root.add_child(legs)
	for spot in [Vector3(0.15, HIP_Y, 0.5), Vector3(-0.15, HIP_Y, 0.5), Vector3(0.16, HIP_Y, -0.52), Vector3(-0.16, HIP_Y, -0.52)]:
		var pivot := Node3D.new()
		pivot.position = spot
		legs.add_child(pivot)
		_part(pivot, _capsule(0.07, LEG_LEN * 0.62), Vector3(0, -0.26, 0), Vector3.ZERO, body_c)
		_part(pivot, _capsule(0.05, LEG_LEN * 0.5), Vector3(0, -0.66, 0), Vector3.ZERO, body_c)
		var hoof := CylinderMesh.new()
		hoof.top_radius = 0.05
		hoof.bottom_radius = 0.065
		hoof.height = 0.08
		hoof.radial_segments = 6
		_part(pivot, hoof, Vector3(0, -LEG_LEN + 0.04, 0.01), Vector3.ZERO, HOOF)
	root.set_meta("phase", float(posmod(variant * 37, 100)) / 100.0 * TAU)
	return root

## Pose the horse for this frame. speed: metres per second over the ground.
static func animate(root: Node3D, state: int, speed: float, dt: float) -> void:
	var legs := root.get_node_or_null("Legs")
	var neck := root.get_node_or_null("Neck") as Node3D
	var tail := root.get_node_or_null("Tail") as Node3D
	if legs == null or neck == null:
		return
	var running := state == AnimalSim.AnimalState.RUN or state == AnimalSim.AnimalState.FLEE
	var moving := speed > 0.05 and state != AnimalSim.AnimalState.DEAD
	var stride := (7.0 if running else 4.2) * clampf(speed / (3.0 if running else 1.2), 0.4, 1.6)
	var phase: float = float(root.get_meta("phase", 0.0)) + (stride * dt if moving else 0.0)
	root.set_meta("phase", phase)
	var swing := (0.55 if running else 0.32) if moving else 0.0
	# Walk: four beats (each leg a quarter apart). Trot/gallop: diagonal pairs.
	var offsets := [0.0, PI, PI, 0.0] if running else [0.0, PI, PI * 1.5, PI * 0.5]
	var pivots := legs.get_children()
	for i in pivots.size():
		var p := pivots[i] as Node3D
		p.rotation.x = lerp_angle(p.rotation.x, sin(phase + offsets[i]) * swing, minf(1.0, dt * 12.0))
	# Grazing lowers the head to the grass; running stretches it out.
	var want := 1.15 if state == AnimalSim.AnimalState.EAT else (-0.25 if running else 0.0)
	neck.rotation.x = lerp_angle(neck.rotation.x, want + (sin(phase * 2.0) * 0.05 if moving else 0.0), minf(1.0, dt * 3.0))
	if tail:
		var t := Time.get_ticks_msec() * 0.001
		tail.rotation.z = sin(t * 1.7 + phase) * (0.12 if not moving else 0.05)
		tail.rotation.x = 0.5 if running else 0.0
