class_name AlbumScreen
extends HudScreen
## The album of witnessed moments, and hunches: guesses about what happens
## next. A right call adds a glimmer to the jar; glimmers buy nothing.

var _tab := "all"

func kicker() -> String: return "Things you were there for"
func title() -> String: return "Album"
func subtitle() -> String: return "Moments count only if you saw them. You can't change what happens; you can call it."

func fill() -> void:
	var m := main()
	var row := UiTheme.hbox(32)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_child(row)

	var left := UiTheme.vbox(12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var entries: Array = m.story.moments.entries()
	var found := entries.filter(func(e): return e["found"]).size()
	var head := UiTheme.hbox(8)
	head.add_child(UiTheme.label("%d of %d witnessed" % [found, entries.size()], "strong", 17, "muted"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	for t in [["all", "All"], ["firsts", "Firsts"], ["people", "People"], ["ideas", "Ideas"], ["world", "World"], ["pressed", "Pressed lives"]]:
		var b := UiTheme.button(t[1], t[0] == _tab, 14)
		b.pressed.connect(func(): _tab = t[0]; _rebuild())
		head.add_child(b)
	left.add_child(head)
	var sc: Array = scroll_column(640, 0)
	(sc[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(sc[0])
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	(sc[1] as VBoxContainer).add_child(grid)
	if _tab == "pressed":
		_pressed_pages(sc[1], m.story.moments.pressed)
	var i := 0
	for e in entries:
		if _tab == "pressed":
			break
		if _tab != "all" and e["kind"] != _tab:
			continue
		grid.add_child(_sticker(e, i))
		i += 1

	# Hunches can pile up; they scroll rather than push the jar off screen.
	var rs: Array = scroll_column(340, 14)
	(rs[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(rs[0])
	var right: VBoxContainer = rs[1]
	right.add_child(UiTheme.caps("Hunches", "accent", 13))
	var open: Array = m.story.hunches.open
	if open.is_empty():
		right.add_child(UiTheme.wrap(UiTheme.label("Nothing to call yet. Hunches appear when the world is on the edge of something.", "hand", 18, "muted"), 330))
	for h in open:
		right.add_child(_hunch(h))
	var done: Array = m.story.hunches.history.slice(maxi(0, m.story.hunches.history.size() - 3))
	for h in done:
		if str(h.get("pick", "")) == "":
			continue
		right.add_child(UiTheme.wrap(UiTheme.label("%s %s → %s" % ["✓" if h["correct"] else "✗", h["question"], h["answer"]], "body", 14, "good" if h["correct"] else "muted"), 330))
	var jar := UiTheme.panel(true)
	var jv := UiTheme.vbox(2)
	jv.add_child(UiTheme.label("%d glimmers" % m.story.hunches.glimmers, "display", 28))
	jv.add_child(UiTheme.label("%d called · they just glow" % m.story.hunches.called, "hand", 16, "muted"))
	jar.add_child(jv)
	right.add_child(jar)

func _sticker(e: Dictionary, i: int) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiTheme.panel_box(true)
	sb.set_content_margin_all(12)
	if not e["found"]:
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = Color(UiTheme.c("muted"), 0.5)
		sb.shadow_size = 0
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(190, 120)
	var v := UiTheme.vbox(4)
	v.add_child(UiTheme.caps(e["kind"], "faint", 10))
	v.add_child(UiTheme.wrap(UiTheme.label(e["name"] if e["found"] else "?", "display", 20, "text" if e["found"] else "muted"), 166))
	v.add_child(UiTheme.wrap(UiTheme.label(e["note"] if e["found"] else e["hint"], "hand", 15, "muted"), 166))
	p.add_child(v)
	if UiTheme.n("tilt") > 0.0 and e["found"]:
		p.rotation_degrees = [-2.0, 1.5, -1.0, 2.5][i % 4]
	return p

func _hunch(h: Dictionary) -> PanelContainer:
	var p := UiTheme.panel(true)
	var v := UiTheme.vbox(8)
	v.add_child(UiTheme.wrap(UiTheme.label(h["question"], "strong", 17), 300))
	v.add_child(UiTheme.label("Settles by day %d" % h["deadline"], "body", 13, "muted"))
	var opts := HFlowContainer.new()
	opts.add_theme_constant_override("h_separation", 6)
	opts.add_theme_constant_override("v_separation", 6)
	for o in h["options"]:
		var b := UiTheme.button(o, h["pick"] == o, 14)
		b.pressed.connect(func(): main().story.hunches.pick(int(h["id"]), o); _rebuild())
		opts.add_child(b)
	v.add_child(opts)
	p.add_child(v)
	return p

func _rebuild() -> void:
	for ch in body.get_children():
		ch.queue_free()
	fill()

## Pressed lives (feat/generations): pages kept from this and earlier worlds,
## newest first.
func _pressed_pages(col: VBoxContainer, pages: Array) -> void:
	if pages.is_empty():
		col.add_child(UiTheme.wrap(UiTheme.label("No lives pressed yet. Open someone's story (L) and press it, or follow someone to the end of their days.", "hand", 18, "muted"), 600))
		return
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	col.add_child(grid)
	var list := pages.duplicate()
	list.reverse()
	var i := 0
	for pg in list:
		grid.add_child(_page_card(pg, i))
		i += 1

func _page_card(pg: Dictionary, i: int) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiTheme.panel_box(true)
	sb.set_content_margin_all(14)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(300, 0)
	var v := UiTheme.vbox(4)
	v.add_child(UiTheme.caps("World %d" % int(pg.get("world", 0)), "faint", 10))
	v.add_child(UiTheme.label(str(pg.get("name", "")), "display", 26))
	v.add_child(UiTheme.wrap(UiTheme.label(PressedLife.span(pg), "body", 14, "muted"), 280))
	if str(pg.get("last_line", "")) != "":
		v.add_child(UiTheme.wrap(UiTheme.label("“%s”" % pg["last_line"], "hand", 17, "accent" if UiTheme.style == "fieldnotes" else "warn"), 280))
	if str(pg.get("legend", "")) != "":
		v.add_child(UiTheme.wrap(UiTheme.label("A legend: they %s." % pg["legend"], "hand", 16, "accent"), 280))
	if str(pg.get("named_for", "")) != "":
		v.add_child(UiTheme.label("Named for %s" % pg["named_for"], "body", 14, "muted"))
	v.add_child(UiTheme.wrap(UiTheme.label(PressedLife.family(pg), "body", 14), 280))
	var evs: Array = pg.get("events", [])
	for e in evs.slice(maxi(0, evs.size() - 3)):
		v.add_child(UiTheme.wrap(UiTheme.label("Day %d: %s" % [int(e["day"]), e["text"]], "hand", 15, "muted"), 280))
	p.add_child(v)
	if UiTheme.n("tilt") > 0.0:
		p.rotation_degrees = [-1.2, 1.0, -0.6, 1.4][i % 4]
	return p
