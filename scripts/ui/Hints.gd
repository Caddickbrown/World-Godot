class_name Hints
extends Control
## "Something's happening": a calm little list (bottom right) of where a
## notable moment is happening or about to, and a small marker for each one,
## over the spot when it's in view or at the screen's edge pointing to it.
## Clicking a row or a marker moves the camera there; nothing else.
##
## Pillar 1: this reads the world and moves only the camera
## (Main.look_at_tile). It never names anyone and never forecasts an idea, so
## it can't answer a hunch ("who thinks of X first?"): a new idea shows only
## after it has been thought. N toggles it (kept in the HUD's settings).

const REFRESH_SECONDS := 1.5       # real seconds between looks at the world
const MAX_ITEMS := 4
const MAX_MARKERS := 3
const NEWBORN_SECONDS := 20.0      # game seconds a birth stays worth a look (about 4 hours)
const FADING_SECONDS := 15.0       # an old life within this of its end (about 3 hours)
const IDEA_HOURS := 1.0            # a new idea stays a hint this long
const EDGE := 30.0                 # px from the screen's edge for off-screen markers
const NEAR_PLACE := 12.0           # tiles: "at <camp>" within this, else a heading

var main: Node = null
var items: Array = []              # {kind, text, pos (tile), rank}
var _timer := 0.0
var _panel: PanelContainer
var _rows: VBoxContainer
var _markers: Array = []           # Marker
var _shown_sig := ""

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	_panel = UiTheme.panel()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_right = -16
	_panel.offset_bottom = -44
	_panel.offset_left = -16
	_panel.offset_top = -44
	_panel.modulate.a = 0.92
	_panel.visible = false
	add_child(_panel)
	var v := UiTheme.vbox(4)
	_panel.add_child(v)
	var title := UiTheme.caps("Something's happening", "muted", 11)
	title.tooltip_text = "Where to look (N to hide). Click to go there."
	v.add_child(title)
	_rows = UiTheme.vbox(2)
	v.add_child(_rows)
	for i in MAX_MARKERS:
		var m := Marker.new()
		m.visible = false
		add_child(m)
		_markers.append(m)

func _process(delta: float) -> void:
	if not visible or main == null or main.world == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH_SECONDS
		items = gather(main)
		_fill_rows()
	_place_markers()

# ── What's worth a look ──────────────────────────────────────────────────────

## Reads the world (never writes it). Ranked, at most MAX_ITEMS.
static func gather(m) -> Array:
	var out: Array = []
	var fs = m.get("festival_system")
	if fs:
		for f in fs.active:
			out.append({"kind": "festival", "text": "%s at %s" % [FestivalSystem.KINDS[f["kind"]]["name"], f["place"]],
				"pos": f["focus"], "rank": 5})
		for u in fs.upcoming(m.settlement_system, m.time_system, 2.0):
			out.append({"kind": "festival_soon", "text": "%s soon at %s" % [u["name"], u["place"]], "pos": u["pos"], "rank": 3})
	var newest = null
	var fading: Array = []
	for a in m.agents:
		if a.is_dead or a.health <= 0.0:
			continue
		if a.age < NEWBORN_SECONDS and (newest == null or a.age < newest.age):
			newest = a
		if a.is_adult and (a.age > a.life_expectancy - FADING_SECONDS or (a.infected and a.health < 0.25)):
			fading.append(a)
	if newest:
		out.append({"kind": "birth", "text": "A new baby %s" % where(m, newest.pos), "pos": newest.pos, "rank": 3})
	fading.sort_custom(func(x, y): return x.age - x.life_expectancy > y.age - y.life_expectancy)
	for a in fading.slice(0, 2):
		out.append({"kind": "fading", "text": "A life near its end %s" % where(m, a.pos), "pos": a.pos, "rank": 4})
	var ws = m.weather_system
	if ws:
		for r in WeatherSystem.ZONES:
			var found := false
			for c in WeatherSystem.ZONES:
				if ws.zone_state(r, c) == WeatherSystem.WeatherType.STORM:
					var p: Vector2 = ws.zone_centre(Vector2i(r, c))
					out.append({"kind": "storm", "text": "A storm %s" % where(m, p), "pos": p, "rank": 2})
					found = true
					break
			if found:
				break
	if m.story:
		var now: float = float(m.time_system.day) * 24.0 + float(m.time_system.hour)
		for e in m.story.recent("ideas", 3):
			var p: Vector2 = e["pos"]
			if p.x >= 0.0 and now - (float(e["day"]) * 24.0 + float(e["hour"])) <= IDEA_HOURS:
				out.append({"kind": "idea", "text": "A new idea %s" % where(m, p), "pos": p, "rank": 2})
				break
	out.sort_custom(func(x, y): return int(x["rank"]) > int(y["rank"]))
	return out.slice(0, MAX_ITEMS)

## "at Elm Cross", "near a camp", "in the north-west".
static func where(m, p: Vector2) -> String:
	var best = null
	var best_d := NEAR_PLACE
	if m.settlement_system:
		for s in m.settlement_system.get_settlements():
			var d: float = s.centre.distance_to(p)
			if d < best_d:
				best_d = d
				best = s
	if best:
		return "at " + str(best.name) if str(best.name) != "" else "at a camp"
	var w: World = m.world
	var c := Vector2(w.width, w.height) * 0.5
	var v := p - c
	if v.length() < w.width * 0.12:
		return "in the middle of the island"
	var names := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
	var i := posmod(int(round(v.angle() / (TAU / 8.0))), 8)
	return "in the " + names[i]

# ── Drawing ──────────────────────────────────────────────────────────────────

func _fill_rows() -> void:
	var sig := "|".join(items.map(func(x): return str(x["text"])))
	if sig == _shown_sig:
		return
	_shown_sig = sig
	for c in _rows.get_children():
		c.queue_free()
	for it in items:
		var b := UiTheme.button(str(it["text"]), false, 13)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = "Look there"
		b.pressed.connect(go_to.bind(it["pos"]))
		_rows.add_child(b)
	_panel.visible = not items.is_empty()
	_panel.reset_size()

## Camera only.
func go_to(tile: Vector2) -> void:
	if main and main.has_method("look_at_tile"):
		main.look_at_tile(tile)

func _camera() -> Camera3D:
	if main.view_mode == main.ViewMode.WALK:
		return main.wanderer.camera
	return main.camera

func _place_markers() -> void:
	var cam := _camera()
	var rect := get_viewport_rect()
	var centre := rect.size * 0.5
	for i in MAX_MARKERS:
		var mk: Marker = _markers[i]
		if i >= items.size() or cam == null:
			mk.visible = false
			continue
		var it: Dictionary = items[i]
		var tile: Vector2 = it["pos"]
		var wp := Vector3(tile.x * World.TILE_SIZE, main.world.surface_y(tile.x, tile.y) + 3.0, tile.y * World.TILE_SIZE)
		var behind := cam.is_position_behind(wp)
		var sp := cam.unproject_position(wp)
		var inner := Rect2(Vector2(EDGE, EDGE + 80.0), rect.size - Vector2(EDGE * 2.0, EDGE * 2.0 + 80.0))
		if behind:
			sp = centre - (sp - centre) * 1000.0
		if not behind and inner.has_point(sp):
			mk.dir = Vector2.ZERO
		else:
			var d := (sp - centre)
			if d.length() < 1.0:
				d = Vector2(0, 1)
			# Clamp the ray from the centre to the inner rectangle.
			var half := inner.size * 0.5
			var k := minf(half.x / maxf(absf(d.x), 0.001), half.y / maxf(absf(d.y), 0.001))
			sp = inner.get_center() + d * k
			mk.dir = d.normalized()
		mk.position = sp - mk.size * 0.5
		mk.tooltip_text = str(it["text"])
		mk.target = tile
		mk.hints = self
		mk.urgent = int(it["rank"]) >= 4
		if not mk.visible:
			mk.modulate.a = 0.0
			mk.visible = true
		mk.modulate.a = minf(0.85, mk.modulate.a + get_process_delta_time() * 1.5)
		mk.queue_redraw()

## A small round marker: a dot over the spot in view, an arrow at the edge.
class Marker extends Control:
	var dir := Vector2.ZERO
	var target := Vector2.ZERO
	var urgent := false
	var hints = null

	func _init() -> void:
		size = Vector2(26, 26)
		custom_minimum_size = size
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _draw() -> void:
		var c := size * 0.5
		var story := UiTheme.style == "storybook"
		var ink := UiTheme.c("ink") if story else Color(0.07, 0.1, 0.09, 0.9)
		var fill := UiTheme.c("select") if urgent else (UiTheme.c("panel") if story else UiTheme.c("accent"))
		draw_circle(c, 10.0, ink)
		draw_circle(c, 8.0, fill)
		if dir == Vector2.ZERO:
			draw_circle(c, 3.0, ink)
		else:
			var tip := c + dir * 6.0
			var side := dir.orthogonal() * 4.0
			draw_colored_polygon(PackedVector2Array([tip, c - dir * 3.0 + side, c - dir * 3.0 - side]), ink)

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and hints:
			hints.go_to(target)
			accept_event()
