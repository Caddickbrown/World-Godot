class_name GameHud
extends CanvasLayer
## The watcher's HUD, built in code from UiTheme so both looks (storybook and
## field notes) come from the same layout. T switches the look; L, I and J open
## Lives, Ideas and the Album (Journal).
##
## Main calls: set_main, update(data), show_notification, on_chronicle,
## set_prompt, set_view_hint, show_game_over. Everything else it reads from main.

const CHRONICLE_ROWS := 5
const TOAST_SECONDS := 4.5
const SETTINGS_PATH := "user://world_settings.json"
var _look_starting := false

var main: Node = null
var root: Control
var bar: PanelContainer
var follow_card: PanelContainer
var chronicle_box: VBoxContainer
var toast_box: VBoxContainer
var prompt_lbl: Label
var hint_lbl: Label
var screen: Control = null          # the open full screen, if any
var screen_name := ""

# Live labels refreshed in update()
var _dial: SeasonDial
var _day_lbl: Label
var _when_lbl: Label
var _weather_lbl: Label
var _people_lbl: Label
var _era_lbl: Label
var _speed_buttons: Dictionary = {}
var _follow_id := -1
var _follow_refresh := 0.0
var _chronicle_tab := "all"
var _chronicle_dirty := true
var _toasts: Array = []             # {node, t}
var _last_speed := -1.0
var _game_over := false

const HINT_OBSERVE := "Click someone to follow · Tab walk among them · L lives · I ideas · J album · T look · Space pause"
const HINT_FOLLOW  := "Following · F or Esc to let go · Tab walk beside them · L their story"
const HINT_WALK    := "Walking unseen · WASD drift · Shift hurry · mouse look · E listen in · Tab back to the sky"

func _ready() -> void:
	layer = 10
	_load_settings()
	build()

func _exit_tree() -> void:
	UiTheme.clear_cache()

func set_main(m: Node) -> void:
	main = m
	_chronicle_dirty = true

# ── Build ────────────────────────────────────────────────────────────────────

func build() -> void:
	if root:
		root.queue_free()
	_speed_buttons.clear()
	_toasts.clear()
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_bar()
	_build_follow_card()
	_build_chronicle()
	toast_box = UiTheme.vbox(8)
	toast_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_box.position = Vector2(-220, 104)
	toast_box.custom_minimum_size = Vector2(440, 0)
	toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_box)
	prompt_lbl = UiTheme.label("", "strong", 22, "text")
	_on_paper(prompt_lbl)
	prompt_lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_lbl.offset_left = -260
	prompt_lbl.offset_right = 260
	prompt_lbl.offset_top = -100
	prompt_lbl.offset_bottom = -60
	prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_lbl.visible = false
	root.add_child(prompt_lbl)
	hint_lbl = UiTheme.label(HINT_OBSERVE, "body", 13, "text")
	hint_lbl.add_theme_color_override("font_color", Color("FFF4E0") if UiTheme.style == "storybook" else UiTheme.c("text"))
	hint_lbl.add_theme_color_override("font_outline_color", Color(0.08, 0.1, 0.12, 0.85))
	hint_lbl.add_theme_constant_override("outline_size", 5)
	hint_lbl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint_lbl.offset_left = 16
	hint_lbl.offset_top = -30
	hint_lbl.offset_right = 1000
	hint_lbl.offset_bottom = -10
	root.add_child(hint_lbl)
	_follow_id = -2
	_chronicle_dirty = true
	if screen_name != "":
		var again := screen_name
		screen_name = ""
		screen = null
		open_screen(again)

## A label sitting on the scene (not on a panel) needs an outline to read.
func _on_paper(l: Label) -> void:
	var story := UiTheme.style == "storybook"
	l.add_theme_color_override("font_color", Color("FFF4E0") if story else UiTheme.c("text"))
	l.add_theme_color_override("font_outline_color", UiTheme.c("ink") if story else Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 8 if story else 6)

func _build_bar() -> void:
	bar = UiTheme.panel()
	var sb := UiTheme.panel_box()
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	bar.add_theme_stylebox_override("panel", sb)
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 16
	bar.offset_right = -16
	bar.offset_top = 12
	root.add_child(bar)
	var row := UiTheme.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	bar.add_child(row)
	_dial = SeasonDial.new()
	row.add_child(_dial)
	var when := UiTheme.vbox(0)
	_day_lbl = UiTheme.label("Day 1", "display", 24)
	_when_lbl = UiTheme.label("spring, morning", "hand", 17, "muted")
	when.add_child(_day_lbl)
	when.add_child(_when_lbl)
	row.add_child(when)
	_weather_lbl = _chip("", "sky")
	row.add_child(_weather_lbl.get_parent())
	_people_lbl = _chip("", "good")
	row.add_child(_people_lbl.get_parent())
	_era_lbl = UiTheme.caps("Stone Age", "warn", 13)
	_era_lbl.tooltip_text = "The age the world is in"
	row.add_child(_era_lbl)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	for pair in [["lives", "Lives"], ["ideas", "Ideas"], ["album", "Album"]]:
		var b := UiTheme.button(pair[1], false, 14)
		b.pressed.connect(open_screen.bind(pair[0]))
		row.add_child(b)
	var speeds := UiTheme.hbox(2)
	for sp in [[0.0, "II", "Hold the world still"], [1.0, "1×", "Normal pace"], [5.0, "5×", "Five times"], [20.0, "20×", "Twenty times"]]:
		var b := UiTheme.button(sp[1], false, 14)
		b.custom_minimum_size.x = 44
		b.tooltip_text = sp[2]
		b.pressed.connect(_set_speed.bind(sp[0]))
		speeds.add_child(b)
		_speed_buttons[sp[0]] = b
	row.add_child(speeds)
	var look := UiTheme.button("Look", false, 15)
	look.tooltip_text = "Choose the look (T flips it)"
	look.pressed.connect(open_look.bind(false))
	row.add_child(look)
	_last_speed = -1.0

func _chip(text: String, color_key: String) -> Label:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var story := UiTheme.style == "storybook"
	sb.bg_color = UiTheme.c(color_key).lightened(0.35) if story else Color(0, 0, 0, 0)
	sb.set_corner_radius_all(14 if story else 4)
	sb.set_border_width_all(2 if story else 0)
	sb.border_color = UiTheme.c("ink")
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	var l := UiTheme.label(text, "strong", 16, "text" if not story else "ink")
	p.add_child(l)
	return l

func _build_follow_card() -> void:
	follow_card = UiTheme.panel()
	follow_card.position = Vector2(16, 104)
	follow_card.custom_minimum_size = Vector2(300, 0)
	follow_card.visible = false
	root.add_child(follow_card)
	if UiTheme.n("tilt") > 0.0:
		follow_card.rotation_degrees = -0.8

func _build_chronicle() -> void:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 10)
	wrap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	wrap.offset_left = -330
	wrap.offset_right = -16
	wrap.offset_top = 104
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(wrap)
	var tabs := UiTheme.hbox(4)
	tabs.alignment = BoxContainer.ALIGNMENT_END
	for t in [["all", "All"], ["people", "People"], ["ideas", "Ideas"], ["world", "World"]]:
		var b := UiTheme.button(t[1], t[0] == _chronicle_tab, 14)
		b.pressed.connect(func(): _chronicle_tab = t[0]; build())
		tabs.add_child(b)
	wrap.add_child(tabs)
	chronicle_box = UiTheme.vbox(10)
	chronicle_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(chronicle_box)

# ── Per-frame ────────────────────────────────────────────────────────────────

func update(data: Dictionary) -> void:
	if root == null:
		return
	var day: int = int(data.get("day", 1))
	var hour: float = float(data.get("hour", 8.0))
	_day_lbl.text = "Day %d" % day
	_when_lbl.text = "%s, %s · %02d:%02d" % [str(data.get("season", "Spring")).to_lower(), _part_of_day(hour), int(hour), int(fposmod(hour, 1.0) * 60.0)]
	_dial.set_year((float(day - 1) + hour / 24.0) / float(TimeSystem.SEASON_DAYS * 4))
	_weather_lbl.text = "%s · %s" % [data.get("weather", "Clear"), data.get("temp", "")]
	_people_lbl.text = "%d living · %d camps" % [int(data.get("population", 0)), int(data.get("settlements", 0))]
	_era_lbl.text = str(data.get("era", "")).to_upper()
	var speed: float = float(data.get("speed", 1.0))
	if speed != _last_speed:
		_last_speed = speed
		for k in _speed_buttons:
			var b: Button = _speed_buttons[k]
			var fresh := UiTheme.button(b.text, is_equal_approx(float(k), speed), 15)
			for st in ["normal", "focus", "hover", "pressed"]:
				b.add_theme_stylebox_override(st, fresh.get_theme_stylebox(st))
			b.add_theme_color_override("font_color", fresh.get_theme_color("font_color"))
			fresh.free()
	var sel: Agent = data.get("selected_agent", null) as Agent
	var sel_id := sel.agent_id if sel and not sel.is_dead else -1
	_follow_refresh -= get_process_delta_time()
	if sel_id != _follow_id or _follow_refresh <= 0.0:
		_follow_id = sel_id
		_follow_refresh = 0.4
		_fill_follow_card(sel)
	if _chronicle_dirty:
		_chronicle_dirty = false
		_fill_chronicle()
	_tick_toasts()

static func _part_of_day(h: float) -> String:
	if h < 5.0: return "night"
	if h < 8.0: return "dawn"
	if h < 12.0: return "morning"
	if h < 17.0: return "afternoon"
	if h < 20.0: return "evening"
	return "night"

func _fill_follow_card(a: Agent) -> void:
	for ch in follow_card.get_children():
		ch.queue_free()
	follow_card.visible = a != null and not a.is_dead
	if not follow_card.visible:
		return
	var v := UiTheme.vbox(10)
	follow_card.add_child(v)
	var walking: bool = main != null and main.view_mode == main.ViewMode.WALK
	v.add_child(UiTheme.caps("Listening to" if walking else "Following"))
	v.add_child(UiTheme.label(a.agent_name, "display", 30))
	var bits: Array = [a.life_stage.capitalize()]
	if not a.task.is_empty():
		bits.append(a.task.replace("_", " "))
	if main and main.settlement_system:
		var st = main.settlement_system.get_settlement_for_agent(a.agent_id)
		if st:
			bits.append(st.name)
	v.add_child(UiTheme.label(" · ".join(bits), "body", 15, "muted"))
	var doing := AgentThoughts.doing(a)
	v.add_child(UiTheme.wrap(UiTheme.label(doing.left(1).to_upper() + doing.substr(1), "strong", 16, "warn" if float(a.needs["hunger"]) < 0.3 else "text"), 260))
	v.add_child(UiTheme.wrap(UiTheme.label("(%s)" % AgentThoughts.thought(a), "hand", 19, "cool"), 260))
	for m in [["Fed", float(a.needs["hunger"]), "warn"], ["Rested", float(a.needs["energy"]), "good"]]:
		var row := UiTheme.vbox(2)
		row.add_child(UiTheme.label(m[0], "body", 13, "muted"))
		row.add_child(UiTheme.meter(m[1], m[2] if m[1] < 0.35 else "cool", 260))
		v.add_child(row)
	if main and main.story:
		var life: LifeRecord = main.story.life_of(a)
		var lines: Array = []
		if life.partner != "":
			lines.append("Partner of %s." % life.partner)
		if not life.children.is_empty():
			lines.append("Children: %s%s." % [", ".join(life.children.slice(0, 3)), "…" if life.children.size() > 3 else ""])
		lines.append("Knows %d ideas." % a.knowledge.size())
		v.add_child(UiTheme.wrap(UiTheme.label(" ".join(lines), "body", 15), 260))
	var btns := UiTheme.hbox(8)
	var story_b := UiTheme.button("Their story", false, 15)
	story_b.pressed.connect(open_screen.bind("lives"))
	btns.add_child(story_b)
	var go := UiTheme.button("Let go", false, 15)
	go.pressed.connect(func(): if main: main.follow(null))
	btns.add_child(go)
	v.add_child(btns)

func _fill_chronicle() -> void:
	if chronicle_box == null:
		return
	for ch in chronicle_box.get_children():
		ch.queue_free()
	if main == null or main.story == null:
		return
	var focus: int = main.selected_agent.agent_id if main.selected_agent else -1
	var tints := {"people": "panel_alt", "ideas": "select", "world": "sky"}
	var i := 0
	for e in main.story.recent(_chronicle_tab, CHRONICLE_ROWS, focus):
		var card := PanelContainer.new()
		var sb := UiTheme.panel_box(true)
		sb.set_content_margin_all(12)
		if UiTheme.style == "storybook":
			sb.bg_color = UiTheme.c(tints.get(e["kind"], "panel_alt")).lightened(0.15)
		card.add_theme_stylebox_override("panel", sb)
		var v := UiTheme.vbox(2)
		v.add_child(UiTheme.caps("Day %d · %s" % [e["day"], _part_of_day(float(e["hour"]))], "faint", 11))
		v.add_child(UiTheme.wrap(UiTheme.label(e["text"], "hand", 18, "text" if UiTheme.style != "storybook" else "ink"), 270))
		card.add_child(v)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		var pos: Vector2 = e["pos"]
		if pos.x >= 0.0:
			card.tooltip_text = "Click to look there"
			card.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed and main: main.look_at_tile(pos))
		if UiTheme.n("tilt") > 0.0:
			card.rotation_degrees = [-1.2, 1.0, -0.6, 1.4, -1.0][i % 5]
		chronicle_box.add_child(card)
		i += 1

# ── Events from Main ─────────────────────────────────────────────────────────

func on_chronicle(_entry: Dictionary) -> void:
	_chronicle_dirty = true

func show_notification(msg: String) -> void:
	if toast_box == null:
		return
	# Moments are the special ones; other notices are left to the chronicle.
	if not msg.begins_with("Witnessed"):
		return
	var p := UiTheme.panel()
	var sb := UiTheme.panel_box()
	if UiTheme.style == "storybook":
		sb.bg_color = UiTheme.c("accent")
	p.add_theme_stylebox_override("panel", sb)
	var v := UiTheme.vbox(0)
	v.add_child(UiTheme.caps("A moment for the album", "ink" if UiTheme.style == "storybook" else "accent", 12))
	v.add_child(UiTheme.label(msg.trim_prefix("Witnessed: "), "display", 24, "ink" if UiTheme.style == "storybook" else "text"))
	p.add_child(v)
	if UiTheme.n("tilt") > 0.0:
		p.rotation_degrees = -2.0
	toast_box.add_child(p)
	_toasts.append({"node": p, "t": TOAST_SECONDS})

func _tick_toasts() -> void:
	var dt := get_process_delta_time()
	for t in _toasts.duplicate():
		t["t"] -= dt
		var node: Control = t["node"]
		if is_instance_valid(node):
			node.modulate.a = clampf(t["t"], 0.0, 1.0)
		if t["t"] <= 0.0:
			_toasts.erase(t)
			if is_instance_valid(node):
				node.queue_free()

func set_prompt(text: String) -> void:
	if prompt_lbl:
		prompt_lbl.text = text
		prompt_lbl.visible = not text.is_empty()

func set_view_hint(walking: bool, following: bool) -> void:
	if hint_lbl:
		hint_lbl.text = HINT_WALK if walking else (HINT_FOLLOW if following else HINT_OBSERVE)
		bar.visible = not walking or screen != null
		hint_lbl.visible = screen == null

func show_game_over(day: int, discoveries: int) -> void:
	_game_over = true
	var p := UiTheme.panel()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.custom_minimum_size = Vector2(440, 0)
	p.position = Vector2(-220, -120)
	var v := UiTheme.vbox(12)
	v.add_child(UiTheme.caps("The island is quiet"))
	v.add_child(UiTheme.label("No one is left.", "display", 32))
	v.add_child(UiTheme.wrap(UiTheme.label("They lasted %d days and found %d ideas. Their stories are in the album." % [day, discoveries], "hand", 20), 400))
	var again := UiTheme.button("Begin a new island", true, 17)
	again.pressed.connect(func(): if main: main._init_world())
	v.add_child(again)
	p.add_child(v)
	root.add_child(p)

# ── Screens ──────────────────────────────────────────────────────────────────

func open_screen(which: String) -> void:
	if screen:
		screen.queue_free()
		screen = null
	if which == screen_name:
		screen_name = ""
		return
	screen_name = which
	match which:
		"lives": screen = LifeStoryScreen.new()
		"ideas": screen = IdeaGardenScreen.new()
		"album": screen = AlbumScreen.new()
		"look":
			var ls := LookScreen.new()
			ls.starting = _look_starting
			screen = ls
		_: screen_name = ""; return
	screen.hud = self
	root.add_child(screen)
	screen.build_screen()

func close_screen() -> void:
	if screen:
		screen.queue_free()
	screen = null
	screen_name = ""
	if _look_starting:
		_look_starting = false
		if main:
			main._set_speed(1.0)

func toggle_style() -> void:
	UiTheme.next_style()
	apply_style_change()

## UiTheme.style changed: keep it, re-dress the world, rebuild the HUD.
func apply_style_change() -> void:
	_save_settings()
	if main and main.has_method("apply_style"):
		main.apply_style()
	build()

## The look picker. starting: the first screen of a new game, which holds the
## clock until you begin.
func open_look(starting: bool = false) -> void:
	_look_starting = starting
	if screen_name == "look":
		screen_name = ""
	open_screen("look")

func _set_speed(s: float) -> void:
	if main:
		main._set_speed(s)

func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_T: toggle_style()
		KEY_L: open_screen("lives")
		KEY_I: open_screen("ideas")
		KEY_J: open_screen("album")
		KEY_ESCAPE:
			if screen:
				close_screen()
				get_viewport().set_input_as_handled()
		_: return
	if k.keycode != KEY_ESCAPE:
		get_viewport().set_input_as_handled()

func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f else null
	if d is Dictionary:
		UiTheme.set_style(str(d.get("style", UiTheme.style)))

func _save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"style": UiTheme.style}))
