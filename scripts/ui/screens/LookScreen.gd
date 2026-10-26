class_name LookScreen
extends HudScreen
## Pick a look: shown when the game starts, and from the Look button (or T to
## flip straight over) at any time. Each card is drawn in its own look, and
## choosing one re-dresses the world behind the screen at once, so you can
## see the island both ways before you begin.

const LOOKS := [
	["storybook", "Storybook", "Bright, round and warm: a picture book of an island. Stickers, ink outlines, sunny colours."],
	["fieldnotes", "Field notes", "Muted, inked and calm: a naturalist's notebook. Dark glass panels, hairlines, softer light."],
]

var starting := false   # the first screen of a new game: Begin starts the clock

func build_screen() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(UiTheme.c("ink"), 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var col := UiTheme.vbox(18)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.add_child(col)
	var head := UiTheme.panel()
	var hv := UiTheme.vbox(4)
	head.add_child(hv)
	hv.add_child(UiTheme.caps("A new island" if starting else "The look"))
	hv.add_child(UiTheme.label("How should the island look?", "display", 40))
	hv.add_child(UiTheme.wrap(UiTheme.label("Pick one; the world behind changes as you choose. You can change it any time: the Look button, or T.", "hand", 19, "muted"), 640))
	col.add_child(head)
	var cards := UiTheme.hbox(24)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(cards)
	var chosen := UiTheme.style
	for l in LOOKS:
		cards.add_child(_card(l[0], l[1], l[2], l[0] == chosen))
	UiTheme.set_style(chosen)   # the cards borrowed the style to draw themselves
	if starting and main():
		col.add_child(_seed_row())
	col.add_child(SoundSettings.panel())   # volumes and hush (scripts/audio)
	var row := UiTheme.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var go := UiTheme.button("Begin" if starting else "Done", true, 20)
	go.custom_minimum_size = Vector2(180, 52)
	go.pressed.connect(_done)
	row.add_child(go)
	col.add_child(row)
	body = Control.new()

## A card drawn in its own look.
func _card(id: String, name: String, blurb: String, selected: bool) -> Control:
	UiTheme.set_style(id)
	var p := PanelContainer.new()
	var sb := UiTheme.panel_box()
	sb.set_content_margin_all(22)
	if id == "fieldnotes":
		sb.bg_color = UiTheme.c("screen_bg")
	if selected:
		sb.border_color = UiTheme.c("select")
		sb.set_border_width_all(maxi(4, int(UiTheme.n("border_w")) + 2))
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(380, 0)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.tooltip_text = "Use the %s look" % name
	var v := UiTheme.vbox(10)
	p.add_child(v)
	v.add_child(UiTheme.caps(("Chosen" if selected else "Look") + (" · A" if id == "storybook" else " · B")))
	v.add_child(UiTheme.label(name, "display", 34))
	v.add_child(UiTheme.wrap(UiTheme.label(blurb, "body", 16, "muted"), 330))
	# A sample of each look: a chronicle line and a few colours.
	var sample := UiTheme.panel(true)
	sample.add_child(UiTheme.wrap(UiTheme.label("Day 3 · dusk — Alor taught fire to six people round the hearth.", "hand", 18), 300))
	v.add_child(sample)
	var sw := UiTheme.hbox(6)
	for key in ["accent", "good", "cool", "warn", "select"]:
		var r := ColorRect.new()
		r.color = UiTheme.c(key)
		r.custom_minimum_size = Vector2(36, 18)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sw.add_child(r)
	v.add_child(sw)
	if UiTheme.n("tilt") > 0.0:
		p.pivot_offset = Vector2(190, 120)
		p.rotation_degrees = -UiTheme.n("tilt") if id == "storybook" else 0.0
	p.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_choose(id))
	return p

## Which island: its seed (the same seed makes the same island), a field to
## type one, and a button for a fresh one. Only before you begin.
func _seed_row() -> Control:
	var p := UiTheme.panel()
	var row := UiTheme.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(row)
	row.add_child(UiTheme.caps("Island", "accent", 12))
	var field := LineEdit.new()
	field.text = str(main().world.seed_val)
	field.custom_minimum_size = Vector2(150, 0)
	field.tooltip_text = "Type a seed to grow that island"
	field.add_theme_font_override("font", UiTheme.font("strong"))
	field.add_theme_font_size_override("font_size", 18)
	field.add_theme_color_override("font_color", UiTheme.c("text"))
	var fsb := UiTheme.panel_box(true, 10.0)
	fsb.set_content_margin_all(8)
	field.add_theme_stylebox_override("normal", fsb)
	field.add_theme_stylebox_override("focus", fsb)
	field.text_submitted.connect(func(txt): _grow(int(txt) if txt.is_valid_int() else txt.hash()))
	row.add_child(field)
	var again := UiTheme.button("A different island", false, 15)
	again.pressed.connect(func():
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		_grow(rng.randi_range(1, 999999)))
	row.add_child(again)
	return p

func _grow(seed_value: int) -> void:
	var m := main()
	if m == null or seed_value == m.world.seed_val:
		return
	m.world_seed = seed_value
	m._init_world()
	m._set_speed(0.0)
	hud.open_look(true)   # rebuilt for the new island, clock still held

func _choose(id: String) -> void:
	if id == UiTheme.style:
		return
	UiTheme.set_style(id)
	hud.apply_style_change()   # saves, re-dresses the world, rebuilds the HUD (and this screen)

func _done() -> void:
	hud.close_screen()   # (on a new game, closing starts the clock)
