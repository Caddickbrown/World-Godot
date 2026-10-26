class_name AgentRenderer
extends Node3D
## The people, as docs/ART_DIRECTION.md draws them: chunky, readable figures in
## their settlement's colours (storybook: big heads and dot eyes; naturalist:
## truer proportions, undyed cloth). They bob and swing their legs as they walk,
## sit to sleep and lie where they fall.
##
## Observer readability: from far away a pin over each head; up close a name;
## with something to say, a speech bubble; listening in, their thought.

const TILE_SIZE := World.TILE_SIZE

var agents: Array = []
var world: World                      # ground height; set by Main
var settlement_system = null          # tribe colours; set by Main
var view_distance: float = 90.0       # camera distance, set by Main each frame
var walker_pos: Vector3 = Vector3.INF # the wisp, when walking among them
## The person the wisp is listening to: their thought shows as a bubble.
## A view-only overlay; the agent never knows (the wisp is unseen).
var listening_id: int = -1

const LABEL_VIEW_DISTANCE := 45.0     # names show when the camera is closer than this
const LABEL_WALK_RADIUS := 14.0       # ...or when the wisp is within this (metres)
const PIN_VIEW_DISTANCE := 60.0       # pins show when the camera is further than this
const HEAD_HEIGHT := 1.7
const SADDLE_HEIGHT := 1.0             # a rider's feet-origin above the ground (horse back ~1.2 m)
const FOCUS_LABEL_RADIUS := 12.0      # following someone: only names this close to them (metres)
const FOCUS_BUBBLE_RADIUS := 5.0      # ...and only speech this close
const MAX_TAGS := 12                  # names/speech shown at once: the nearest to where you look

var _nodes: Dictionary = {}           # agent_id -> {root, body, legs, label, bubble, pin, tribe, phase}
var _pin_mesh: SphereMesh
var _pin_mat: StandardMaterial3D
var _pin_mat_selected: StandardMaterial3D
var _ring: MeshInstance3D
var _time := 0.0
var _focus_pos := Vector3.INF         # whoever is selected, this frame
var look_point := Vector3.INF         # where the camera looks (set by Main)
var _tagged: Dictionary = {}          # agent_id -> true: may show a name this frame
var _mats: Dictionary = {}

# ── Discovery glow ──
## A new idea: a burst of light round the thinker (a ring that spreads over
## the ground, a soft column and, in the storybook look, a few rising sparks).
## Started when Agent.discovery_flash jumps up (Main and Agent set it to 1.5
## on a discovery); it then runs on real time, so it plays the same at 20x
## and while paused. Scaled with the camera distance so it reads from the sky.
const GLOW_SECONDS := 2.6
const MAX_GLOWS := 10
var glows: Array = []                 # {node, ring, column, sparks, light, agent_id, t}
var _glow_mats: Dictionary = {}

func _ready() -> void:
	_pin_mesh = SphereMesh.new()
	_pin_mesh.radius = 0.35
	_pin_mesh.height = 0.7
	_pin_mesh.radial_segments = 12
	_pin_mesh.rings = 6
	_pin_mat = _flat(Color(1.0, 0.62, 0.30))
	_pin_mat_selected = _flat(Color(1.0, 0.95, 0.25))
	for m in [_pin_mat, _pin_mat_selected]:
		m.no_depth_test = true
		m.render_priority = 8
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.7
	_ring.mesh = torus
	_ring.material_override = _flat(Color(1.0, 0.85, 0.3))
	_ring.visible = false
	add_child(_ring)

func setup(p_agents: Array) -> void:
	agents = p_agents
	for a in agents:
		_add_node(a)

## Main owns the list (`agents` is the same array); a newborn is already in
## it by the time this is called, so only its figure is added here.
func add_agent(agent: Agent) -> void:
	if not agents.has(agent):
		agents.append(agent)
	if not _nodes.has(agent.agent_id):
		_add_node(agent)

## A buried person: drop their figure. Main has already taken them out of the list.
func remove_agent(agent: Agent) -> void:
	agents.erase(agent)
	var e: Dictionary = _nodes.get(agent.agent_id, {})
	for k in ["root", "label", "bubble", "pin"]:
		var n: Node = e.get(k)
		if n: n.queue_free()
	_nodes.erase(agent.agent_id)

## Rebuild every figure (the look style changed).
func restyle() -> void:
	for id in _nodes:
		for k in ["root", "label", "bubble", "pin"]:
			var n: Node = _nodes[id].get(k)
			if n: n.queue_free()
	_nodes.clear()
	_mats.clear()
	for g in glows:
		(g["node"] as Node).queue_free()
	glows.clear()
	_glow_mats.clear()
	for a in agents:
		_add_node(a)

func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.9
		_mats[key] = m
	return _mats[key]

func _add_node(agent: Agent) -> void:
	var nat := LookStyle.naturalist()
	var i := agent.agent_id
	var root := Node3D.new()
	add_child(root)
	var body_root := Node3D.new()   # everything above the feet; bobs while walking
	root.add_child(body_root)
	var tunic := _mat(LookStyle.g(Color(0.66, 0.58, 0.46)))
	var skin := _mat(LookStyle.g(LookStyle.SKIN[(i * 3) % LookStyle.SKIN.size()]))
	var hair := _mat(LookStyle.g(LookStyle.HAIR[(i * 7 + 1) % LookStyle.HAIR.size()]))
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.22 if nat else 0.28
	cap.height = 1.3 if nat else 1.15
	body.mesh = cap
	body.position.y = 0.9 if nat else 0.78
	body.material_override = tunic
	body_root.add_child(body)
	var head := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.15 if nat else 0.24
	hs.height = hs.radius * 2.0
	head.mesh = hs
	head.position.y = 1.66 if nat else 1.55
	head.material_override = skin
	body_root.add_child(head)
	var hr := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = hs.radius * 1.08
	hm.height = hm.radius * 1.15
	hm.is_hemisphere = true
	hr.mesh = hm
	hr.position = Vector3(0, head.position.y + 0.03, -0.03)
	hr.material_override = hair
	body_root.add_child(hr)
	if not nat:
		var eye_mat := _mat(Color(0.08, 0.06, 0.05))
		for side in [-1.0, 1.0]:
			var eye := MeshInstance3D.new()
			var em := SphereMesh.new()
			em.radius = 0.045
			em.height = 0.09
			eye.mesh = em
			eye.position = Vector3(side * 0.09, head.position.y + 0.02, 0.21)
			eye.material_override = eye_mat
			body_root.add_child(eye)
	var legs: Array = []
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * 0.12, 0.5, 0)
		var leg := MeshInstance3D.new()
		var lm := CapsuleMesh.new()
		lm.radius = 0.1
		lm.height = 0.55
		leg.mesh = lm
		leg.position.y = -0.27
		leg.material_override = skin
		pivot.add_child(leg)
		root.add_child(pivot)
		legs.append(pivot)
	var label := _make_label(40, Color(1, 1, 1))
	var bubble := _make_label(36, Color(1.0, 0.96, 0.82))
	var pin := MeshInstance3D.new()
	pin.mesh = _pin_mesh
	pin.material_override = _pin_mat
	pin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pin)
	_nodes[agent.agent_id] = {"root": root, "body_root": body_root, "body": body, "legs": legs,
		"label": label, "bubble": bubble, "pin": pin, "tribe": -2, "phase": fmod(float(agent.agent_id) * 2.399, TAU),
		"last_pos": agent.pos, "last_flash": agent.discovery_flash}

func _make_label(font_size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = font_size
	# Fixed on-screen size, like a map label: readable from the sky and up close.
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.outline_size = 10
	l.outline_modulate = Color(0.08, 0.06, 0.04, 0.9)
	l.modulate = color
	l.visible = false
	l.font = UiTheme.font("strong")
	# Always readable: names and words draw over trees and roofs.
	l.no_depth_test = true
	l.render_priority = 10
	l.outline_render_priority = 9
	add_child(l)
	return l

## Overlay nodes for tests and the capture tool.
func get_overlay(agent_id: int, key: String) -> Node3D:
	return (_nodes.get(agent_id, {}) as Dictionary).get(key) as Node3D

func update() -> void:
	var dt := get_process_delta_time()
	_time += dt
	var active: Dictionary = {}
	_ring.visible = false
	_focus_pos = Vector3.INF
	for agent in agents:
		if agent.selected and not agent.is_dead:
			_focus_pos = Vector3(agent.pos.x * TILE_SIZE, 0.0, agent.pos.y * TILE_SIZE)
	# A crowd (forty founders on one beach) would pile its names into a heap:
	# only the nearest few to where you're looking get a tag.
	_tagged.clear()
	var centre := _focus_pos if _focus_pos != Vector3.INF else look_point
	if centre != Vector3.INF:
		var near: Array = []
		for agent in agents:
			if not agent.is_dead and agent.health > 0.0:
				var d := Vector2(agent.pos.x * TILE_SIZE - centre.x, agent.pos.y * TILE_SIZE - centre.z).length_squared()
				near.append([d, agent.agent_id])
		near.sort_custom(func(x, y): return x[0] < y[0])
		# ...and never two on top of each other (the gap grows as you pull back).
		var gap := view_distance * 0.11
		var placed: Array = []
		var by_id := {}
		for agent in agents:
			by_id[agent.agent_id] = agent
		for pair in near:
			if placed.size() >= MAX_TAGS:
				break
			var a: Agent = by_id[pair[1]]
			var p := Vector2(a.pos.x, a.pos.y) * TILE_SIZE
			var clear := a.selected or a.agent_id == listening_id
			if not clear:
				clear = true
				for q in placed:
					if absf(q.x - p.x) < gap * 1.6 and absf(q.y - p.y) < gap * 0.7:
						clear = false
						break
			if clear:
				placed.append(p)
				_tagged[pair[1]] = true
	for agent in agents:
		active[agent.agent_id] = true
		if not _nodes.has(agent.agent_id):
			_add_node(agent)
		var e: Dictionary = _nodes[agent.agent_id]
		var root: Node3D = e["root"]
		var feet := Vector3(agent.pos.x * TILE_SIZE, world.surface_y(agent.pos.x, agent.pos.y) if world else 0.0, agent.pos.y * TILE_SIZE)
		# On horseback: up in the saddle (AnimalMinds keeps the horse under them).
		var mounted: bool = agent.riding_horse_id >= 0 and not agent.is_dead
		if mounted:
			feet.y += SADDLE_HEIGHT
		root.position = feet
		root.visible = true
		_dress(e, agent)
		var moved: float = (agent.pos - (e["last_pos"] as Vector2)).length()
		e["last_pos"] = agent.pos
		var walking: bool = moved > 0.0005 and not agent.is_dead and agent.state != Agent.State.SLEEPING
		if walking or agent.at_fire or agent.state == Agent.State.FESTIVAL:
			root.rotation.y = atan2(agent.facing.x, agent.facing.y)
		var stage_scale := 0.55 if agent.life_stage == "infant" else (0.72 if agent.life_stage == "child" else 1.0)
		root.scale = Vector3.ONE * stage_scale
		var body_root: Node3D = e["body_root"]
		var legs: Array = e["legs"]
		if agent.is_dead:
			root.rotation.x = deg_to_rad(88.0)
			body_root.position.y = 0.0
		elif mounted:
			root.rotation.x = 0.0
			body_root.position.y = -0.4   # seated, legs either side of the horse
			for i in legs.size():
				(legs[i] as Node3D).rotation.x = -0.35
				(legs[i] as Node3D).rotation.z = 0.55 if i == 0 else -0.55
		elif agent.state == Agent.State.SLEEPING or agent.at_fire \
				or (agent.state == Agent.State.FESTIVAL and agent.festival_pose == FestivalSystem.POSE_SIT and not walking):
			root.rotation.x = 0.0
			body_root.position.y = -0.45   # sitting, curled by the fire
			for leg in legs:
				leg.rotation.x = -PI / 2.0
				leg.rotation.z = 0.0
		else:
			root.rotation.x = 0.0
			e["phase"] = float(e["phase"]) + dt * (9.0 if walking else 0.0)
			var ph: float = e["phase"]
			body_root.position.y = absf(sin(ph)) * 0.06 if walking else 0.0
			if agent.state == Agent.State.FESTIVAL and agent.festival_pose == FestivalSystem.POSE_DANCE:
				# Dancing: a hop on every step, and a little on the spot between.
				body_root.position.y = absf(sin(ph if walking else _time * 7.0 + float(e["phase"]))) * 0.22
			(legs[0] as Node3D).rotation.x = sin(ph) * 0.6 if walking else 0.0
			(legs[1] as Node3D).rotation.x = -sin(ph) * 0.6 if walking else 0.0
			for leg in legs: leg.rotation.z = 0.0
		if agent.selected and not agent.is_dead:
			_ring.visible = true
			_ring.position = feet + Vector3(0, 0.05, 0)
		_update_overlays(e, agent, feet)
		if agent.discovery_flash > float(e.get("last_flash", 0.0)) + 0.01 and not agent.is_dead:
			start_glow(agent)
		e["last_flash"] = agent.discovery_flash
	advance_glows(dt)
	for id in _nodes:
		if not active.has(id):
			for key in ["root", "label", "bubble", "pin"]:
				var n: Node3D = _nodes[id].get(key) as Node3D
				if n: n.visible = false

## Tunic colour follows the settlement they live in (re-dressed when it changes).
func _dress(e: Dictionary, agent: Agent) -> void:
	var tribe := -1
	var cul = null
	if settlement_system:
		var s = settlement_system.get_settlement_for_agent(agent.agent_id)
		if s:
			tribe = int(s.id)
			cul = s.culture
	# Their camp's dye (Culture, feat/cultures); re-dressed when it drifts.
	var key := tribe * 1000 + (int(cul.version) if cul else 0)
	if key == int(e["tribe"]):
		return
	e["tribe"] = key
	var col: Color = Color(0.82, 0.62, 0.40) if tribe < 0 else (cul.dye() if cul else LookStyle.tribe(tribe))
	(e["body"] as MeshInstance3D).material_override = _mat(LookStyle.g(col))

func _update_overlays(entry: Dictionary, agent: Agent, feet: Vector3) -> void:
	var alive: bool = not agent.is_dead and agent.health > 0.0
	var near_walker: bool = walker_pos != Vector3.INF and feet.distance_to(walker_pos) < LABEL_WALK_RADIUS
	var close: bool = view_distance < LABEL_VIEW_DISTANCE or near_walker
	# Following someone in a crowd: the tags round them, not the whole camp's.
	var flat := Vector3(feet.x, 0.0, feet.z)
	var near_focus: bool = (_focus_pos == Vector3.INF or flat.distance_to(_focus_pos) < FOCUS_LABEL_RADIUS) \
		and (_tagged.is_empty() or _tagged.has(agent.agent_id))
	var speech_near_focus: bool = (_focus_pos == Vector3.INF or flat.distance_to(_focus_pos) < FOCUS_BUBBLE_RADIUS) \
		and (_tagged.is_empty() or _tagged.has(agent.agent_id))

	var label: Label3D = entry.get("label") as Label3D
	if label:
		label.visible = alive and ((close and near_focus) or agent.selected)
		if label.visible:
			label.text = agent.agent_name
			label.position = feet + Vector3(0, HEAD_HEIGHT + 0.3, 0)
			label.modulate = Color(1.0, 0.95, 0.35) if agent.selected else Color(1, 1, 1)

	var bubble: Label3D = entry.get("bubble") as Label3D
	if bubble:
		var listening: bool = agent.agent_id == listening_id
		var line: String = AgentThoughts.thought(agent) if listening else agent.speech_bubble
		bubble.visible = alive and not line.is_empty() and ((close and speech_near_focus) or agent.selected or listening)
		if bubble.visible:
			bubble.text = ("(" + line + ")") if listening else ("“" + line + "”")
			bubble.modulate = Color(0.75, 0.9, 1.0) if listening else Color(1.0, 0.96, 0.82)
			bubble.position = feet + Vector3(0, HEAD_HEIGHT + 0.8, 0)

	var pin: MeshInstance3D = entry.get("pin") as MeshInstance3D
	if pin:
		pin.visible = alive and view_distance > PIN_VIEW_DISTANCE and walker_pos == Vector3.INF
		if pin.visible:
			var s: float = view_distance / 70.0 * (2.2 if agent.selected else 1.0)
			pin.scale = Vector3(s, s, s)
			pin.position = feet + Vector3(0, HEAD_HEIGHT + 0.6 * s, 0)
			pin.material_override = _pin_mat_selected if agent.selected else _pin_mat

# ── Discovery glow ───────────────────────────────────────────────────────────

func _glow_mat(key: String, c: Color) -> StandardMaterial3D:
	if not _glow_mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.no_depth_test = key == "spark"
		m.albedo_color = c
		_glow_mats[key] = m
	return _glow_mats[key]

## Light up round someone who just had an idea (view only).
func start_glow(agent: Agent) -> void:
	if glows.size() >= MAX_GLOWS:
		var old: Dictionary = glows.pop_front()
		(old["node"] as Node).queue_free()
	var nat := LookStyle.naturalist()
	var warm := Color(0.79, 0.63, 0.31) if nat else Color(1.0, 0.82, 0.35)   # ochre / sun
	var node := Node3D.new()
	add_child(node)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.86
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 6
	ring.mesh = torus
	ring.scale = Vector3(1, 0.15, 1)
	ring.material_override = _glow_mat("ring", warm)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(ring)
	var column := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.25
	cyl.bottom_radius = 0.7
	cyl.height = 1.0
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 12
	column.mesh = cyl
	column.material_override = _glow_mat("column", Color(warm, 0.5))
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(column)
	var sparks: Array = []
	var n_sparks := 0 if nat else 6
	for i in n_sparks:
		var sp := MeshInstance3D.new()
		var pm := PrismMesh.new()   # a little diamond: two prisms back to back would do; one reads as a glint
		pm.size = Vector3(0.22, 0.32, 0.06)
		sp.mesh = pm
		sp.material_override = _glow_mat("spark", Color(1.0, 0.95, 0.7) if i % 2 == 0 else Color(0.94, 0.5, 0.24))
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(sp)
		sparks.append(sp)
	var light := OmniLight3D.new()
	light.light_color = warm
	light.omni_range = 9.0
	light.shadow_enabled = false
	node.add_child(light)
	glows.append({"node": node, "ring": ring, "column": column, "sparks": sparks, "light": light,
		"agent_id": agent.agent_id, "agent": agent, "t": 0.0, "nat": nat})
	_place_glow(glows[-1])

## Run every glow on by dt real seconds (update() calls it; capture and tests may too).
func advance_glows(dt: float) -> void:
	for g in glows.duplicate():
		g["t"] = float(g["t"]) + dt
		if float(g["t"]) >= GLOW_SECONDS:
			(g["node"] as Node).queue_free()
			glows.erase(g)
			continue
		_place_glow(g)

func _place_glow(g: Dictionary) -> void:
	var agent: Agent = g["agent"]
	var node: Node3D = g["node"]
	var feet := Vector3(agent.pos.x * TILE_SIZE, world.surface_y(agent.pos.x, agent.pos.y) if world else 0.0, agent.pos.y * TILE_SIZE)
	node.position = feet
	var k := float(g["t"]) / GLOW_SECONDS                 # 0 .. 1 through the burst
	var fade := (1.0 - smoothstep(0.55, 1.0, k)) * smoothstep(0.0, 0.06, k)
	var big := maxf(1.0, view_distance / 32.0)           # reads from the sky
	var ring: MeshInstance3D = g["ring"]
	var r := lerpf(0.6, 4.2, 1.0 - pow(1.0 - minf(k * 1.4, 1.0), 3.0)) * big
	ring.scale = Vector3(r, 0.15 * big, r)
	ring.position.y = 0.12
	ring.transparency = 1.0 - fade
	var col: MeshInstance3D = g["column"]
	var h := (3.5 + 3.0 * smoothstep(0.0, 0.3, k)) * big
	col.scale = Vector3(big * (1.0 + k * 0.6), h, big * (1.0 + k * 0.6))
	col.position.y = h * 0.5
	col.transparency = 1.0 - fade * (0.55 if bool(g["nat"]) else 0.75)
	var i := 0
	for sp in g["sparks"]:
		var a := TAU * i / 6.0 + k * 3.0
		var rise := (0.8 + k * 3.4 + float(i % 3) * 0.5) * big
		(sp as MeshInstance3D).position = Vector3(cos(a) * 0.9 * big, HEAD_HEIGHT * 0.6 + rise, sin(a) * 0.9 * big)
		(sp as MeshInstance3D).rotation.y = a + k * 6.0
		(sp as MeshInstance3D).scale = Vector3.ONE * big * (1.0 - k * 0.5)
		(sp as MeshInstance3D).transparency = 1.0 - fade
		i += 1
	var light: OmniLight3D = g["light"]
	light.position.y = 1.4
	light.light_energy = 3.5 * fade * (1.0 - k * 0.5)
	light.omni_range = 9.0 * big

## Glows playing now round this person (tests).
func glowing(agent_id: int) -> bool:
	for g in glows:
		if int(g["agent_id"]) == agent_id:
			return true
	return false
