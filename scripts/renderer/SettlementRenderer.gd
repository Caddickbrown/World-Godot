class_name SettlementRenderer
extends Node3D
## Where people live, drawn from SettlementSystem: a ring of dwellings round a
## hearth, one more for every few members. Camps are hide tents, hamlets round
## huts with thatch, towns timber houses. Every live fire in the world
## (World.natural_fires) gets a flame and, after dusk, real firelight.

const TILE_SIZE := World.TILE_SIZE
const PEOPLE_PER_DWELLING := 3
const MAX_DWELLINGS := 12
const MAX_FIRE_LIGHTS := 16

var world: World
var darkness := 0.0               # 0 day .. 1 night, set by Main
var _built: Dictionary = {}       # settlement id -> {node, tier, count}
var _fires: Dictionary = {}       # "x,z" -> {node, light}
var _mats: Dictionary = {}

func clear() -> void:
	for ch in get_children():
		ch.queue_free()
	_built.clear()
	_fires.clear()

func restyle() -> void:
	clear()
	_mats.clear()

## settlements: SettlementSystem.get_settlements(); fires: World.natural_fires keys.
func sync(settlements: Array, fires: Dictionary) -> void:
	var live: Dictionary = {}
	for s in settlements:
		live[s.id] = true
		var count := clampi(int(ceil(float(s.member_ids.size()) / PEOPLE_PER_DWELLING)), 2, MAX_DWELLINGS)
		var e: Dictionary = _built.get(s.id, {})
		if e.is_empty() or int(e["tier"]) != int(s.tier) or int(e["count"]) != count \
				or (e["centre"] as Vector2).distance_to(s.centre) > 0.5:
			if not e.is_empty():
				(e["node"] as Node).queue_free()
			_built[s.id] = {"node": _build_settlement(s, count), "tier": int(s.tier), "count": count, "centre": s.centre}
	for id in _built.keys():
		if not live.has(id):
			(_built[id]["node"] as Node).queue_free()
			_built.erase(id)
	_sync_fires(fires)

func _build_settlement(s, count: int) -> Node3D:
	var root := Node3D.new()
	var c := Vector3(s.centre.x * TILE_SIZE, 0, s.centre.y * TILE_SIZE)
	root.position = c
	add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(s.id) * 7919 + 13
	for i in count:
		# Rings: six round the hearth, then a wider ring.
		var ring := 0 if i < 6 else 1
		var in_ring := 6 if ring == 0 else 10
		var a := TAU * float(i % in_ring) / float(in_ring) + rng.randf_range(-0.2, 0.2) + ring * 0.3
		var r := (5.0 if ring == 0 else 9.5) + rng.randf_range(-0.6, 0.6)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		var wp := c + p
		var tx := wp.x / TILE_SIZE
		var tz := wp.z / TILE_SIZE
		if world and not world.is_walkable(tx, tz):
			continue
		p.y = (world.surface_y(tx, tz) if world else 0.0)
		var d := _dwelling(int(s.tier), rng)
		d.position = p
		d.rotation.y = atan2(-p.x, -p.z)  # doors face the hearth
		root.add_child(d)
	# The hearth ring of stones
	var hy := world.surface_y(s.centre.x, s.centre.y) if world else 0.0
	for i in 8:
		var a := TAU * i / 8.0
		var st := MeshInstance3D.new()
		st.mesh = _ball(0.22)
		st.position = Vector3(cos(a) * 0.8, hy + 0.1, sin(a) * 0.8)
		st.material_override = _mat(Color(0.5, 0.48, 0.46))
		root.add_child(st)
	return root

func _dwelling(tier: int, rng: RandomNumberGenerator) -> Node3D:
	var d := Node3D.new()
	match tier:
		0:  # hide tent
			var tent := MeshInstance3D.new()
			tent.mesh = _cone(1.5, 2.6, 6)
			tent.position.y = 1.3
			tent.material_override = _mat(Color(0.74, 0.60, 0.44).darkened(rng.randf() * 0.15))
			d.add_child(tent)
			var pole := MeshInstance3D.new()
			pole.mesh = _cone(0.05, 0.9, 4)
			pole.position.y = 2.8
			pole.material_override = _mat(Color(0.4, 0.3, 0.2))
			d.add_child(pole)
		1:  # round hut, thatched
			var wall := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 1.5
			cyl.bottom_radius = 1.6
			cyl.height = 1.4
			cyl.radial_segments = 10
			wall.mesh = cyl
			wall.position.y = 0.7
			wall.material_override = _mat(Color(0.70, 0.58, 0.42))
			d.add_child(wall)
			var roof := MeshInstance3D.new()
			roof.mesh = _cone(2.1, 1.7, 10)
			roof.position.y = 2.25
			roof.material_override = _mat(Color(0.78, 0.66, 0.36).darkened(rng.randf() * 0.12))
			d.add_child(roof)
		_:  # timber house with a pitched roof
			var box := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(3.0, 1.8, 2.4)
			box.mesh = bm
			box.position.y = 0.9
			box.material_override = _mat(Color(0.86, 0.80, 0.68))
			d.add_child(box)
			var roof := MeshInstance3D.new()
			var pm := PrismMesh.new()
			pm.size = Vector3(3.4, 1.3, 2.8)
			roof.mesh = pm
			roof.position.y = 2.45
			roof.material_override = _mat(Color(0.62, 0.30, 0.22).darkened(rng.randf() * 0.15))
			d.add_child(roof)
	var door := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(0.6, 0.9, 0.05)
	door.mesh = dm
	door.position = Vector3(0, 0.45, 1.45 if tier > 0 else 1.0)
	door.material_override = _mat(Color(0.25, 0.18, 0.12))
	d.add_child(door)
	return d

func _sync_fires(fires: Dictionary) -> void:
	for key in fires:
		if _fires.has(key):
			continue
		var p: PackedStringArray = str(key).split(",")
		var tx := float(p[0]) + 0.5
		var tz := float(p[1]) + 0.5
		var node := Node3D.new()
		node.position = Vector3(tx * TILE_SIZE, world.surface_y(tx, tz) if world else 0.0, tz * TILE_SIZE)
		var flame := MeshInstance3D.new()
		flame.mesh = _cone(0.3, 0.8, 6)
		flame.position.y = 0.4
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(1.0, 0.62, 0.22)
		fm.emission_enabled = true
		fm.emission = Color(1.0, 0.45, 0.12)
		fm.emission_energy_multiplier = 5.0
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flame.material_override = fm
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(flame)
		var light: OmniLight3D = null
		if _fires.size() < MAX_FIRE_LIGHTS:
			light = OmniLight3D.new()
			light.light_color = Color(1.0, 0.6, 0.3)
			light.omni_range = 12.0
			light.position.y = 1.2
			node.add_child(light)
		add_child(node)
		_fires[key] = {"node": node, "light": light}
	for key in _fires.keys():
		if not fires.has(key):
			(_fires[key]["node"] as Node).queue_free()
			_fires.erase(key)
	for key in _fires:
		var l: OmniLight3D = _fires[key]["light"]
		if l:
			l.light_energy = lerpf(0.4, 3.0, darkness) * (0.9 + 0.1 * sin(Time.get_ticks_msec() * 0.013 + l.position.x))

func _mat(c: Color) -> StandardMaterial3D:
	var col := LookStyle.g(c)
	var key := col.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.95
		_mats[key] = m
	return _mats[key]

static func _cone(r: float, h: float, segs: int = 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c

static func _ball(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 1.8
	s.radial_segments = 6
	s.rings = 4
	return s
