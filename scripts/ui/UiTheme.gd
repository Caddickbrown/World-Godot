class_name UiTheme
extends RefCounted
## The two UI looks from docs/ART_DIRECTION.md as tokens, plus small builders
## so every screen is made the same way. Switch with UiTheme.set_style(); the
## HUD rebuilds itself when it changes.
##   storybook  (A): paper stickers, ink outlines, a little tilt, Fredoka + Patrick Hand
##   fieldnotes (B): dark glass, hairlines, no tilt, Alegreya Sans + Alegreya italic

const STYLES := ["storybook", "fieldnotes"]
static var style := "storybook"

const TOKENS := {
	"storybook": {
		"panel": Color("FFF4E0"), "panel_alt": Color("FFFFFF"), "ink": Color("22304A"),
		"text": Color("22304A"), "muted": Color("4A5878"), "faint": Color("6A5A44"),
		"accent": Color("F0803C"), "select": Color("FFD25A"), "good": Color("6DB04A"),
		"warn": Color("D9496B"), "cool": Color("1E9E95"), "sky": Color("BFE3F2"),
		"border": Color("22304A"), "border_w": 3, "radius": 20, "shadow": 5, "tilt": 1.5,
		"screen_bg": Color("2E6E6A"), "bar_bg": Color("FFF4E0"),
	},
	"fieldnotes": {
		"panel": Color(0.086, 0.122, 0.114, 0.88), "panel_alt": Color(0.13, 0.17, 0.16, 0.92),
		"ink": Color("1C2723"), "text": Color("ECE6D6"), "muted": Color("A9A493"), "faint": Color("8C8878"),
		"accent": Color("C9A04E"), "select": Color("C9A04E"), "good": Color("7E9A6A"),
		"warn": Color("B5674A"), "cool": Color("5E8C8A"), "sky": Color("9FB8B4"),
		"border": Color(0.925, 0.902, 0.84, 0.22), "border_w": 1, "radius": 6, "shadow": 0, "tilt": 0.0,
		"screen_bg": Color("1C2723"), "bar_bg": Color(0.086, 0.122, 0.114, 0.88),
	},
}

static var _fonts: Dictionary = {}

static func set_style(s: String) -> void:
	if s in STYLES:
		style = s

static func next_style() -> String:
	style = STYLES[(STYLES.find(style) + 1) % STYLES.size()]
	return style

static func c(key: String) -> Color:
	return TOKENS[style][key]

static func n(key: String) -> float:
	return float(TOKENS[style][key])

## role: "display" (headings), "body", "strong", "hand" (speech, thoughts, chronicle)
static func font(role: String) -> Font:
	var key := style + ":" + role
	if _fonts.has(key):
		return _fonts[key]
	var f: Font
	if style == "storybook":
		match role:
			"hand": f = load("res://assets/fonts/PatrickHand-Regular.ttf")
			_:
				var v := FontVariation.new()
				v.base_font = load("res://assets/fonts/Fredoka.ttf")
				v.variation_opentype = {"wght": 700 if role == "display" else (600 if role == "strong" else 500)}
				f = v
	else:
		match role:
			"hand": f = load("res://assets/fonts/Alegreya-Italic.ttf")
			"display": f = load("res://assets/fonts/AlegreyaSans-Light.ttf")
			"strong": f = load("res://assets/fonts/AlegreyaSans-Medium.ttf")
			_: f = load("res://assets/fonts/AlegreyaSans-Regular.ttf")
	_fonts[key] = f
	return f

static func panel_box(alt: bool = false, radius: float = -1.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c("panel_alt") if alt else c("panel")
	var w := int(n("border_w"))
	sb.set_border_width_all(w)
	sb.border_color = c("border")
	sb.set_corner_radius_all(int(n("radius") if radius < 0.0 else radius))
	sb.set_content_margin_all(16)
	if n("shadow") > 0.0:
		sb.shadow_color = c("ink")
		sb.shadow_size = 1
		sb.shadow_offset = Vector2(0, n("shadow"))
	return sb

static func label(text: String, role: String = "body", size: int = 16, color_key: String = "text") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(role))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c(color_key))
	return l

static func caps(text: String, color_key: String = "accent", size: int = 12) -> Label:
	var l := label(text.to_upper(), "strong", size, color_key)
	l.add_theme_constant_override("outline_size", 0)
	return l

static func wrap(l: Label, width: float) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	return l

## A button in the current style. selected draws it as the active choice.
static func button(text: String, selected: bool = false, size: int = 16) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(44, 40)
	b.add_theme_font_override("font", font("strong"))
	b.add_theme_font_size_override("font_size", size)
	var normal := StyleBoxFlat.new()
	var story := style == "storybook"
	normal.bg_color = c("select") if selected else (c("panel_alt") if story else Color(0, 0, 0, 0))
	normal.set_border_width_all(int(n("border_w")) if story else 1)
	normal.border_color = c("ink") if story else (c("accent") if selected else c("border"))
	normal.set_corner_radius_all(14 if story else 4)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	if story:
		normal.shadow_color = c("ink")
		normal.shadow_size = 1
		normal.shadow_offset = Vector2(0, 3)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = c("select").lightened(0.25) if story else Color(c("accent"), 0.18)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = c("select")
	for st in ["normal", "focus"]:
		b.add_theme_stylebox_override(st, normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	var fg := c("ink") if (selected or story) else c("text")
	if not story and selected:
		fg = c("ink")
	for k in ["font_color", "font_hover_color", "font_focus_color"]:
		b.add_theme_color_override(k, fg)
	b.add_theme_color_override("font_pressed_color", c("ink"))
	return b

## A progress bar drawn as a thin track (fieldnotes) or a chunky jar (storybook).
static func meter(value: float, color_key: String, width: float = 200.0) -> ProgressBar:
	var p := ProgressBar.new()
	p.min_value = 0.0
	p.max_value = 1.0
	p.value = clampf(value, 0.0, 1.0)
	p.show_percentage = false
	var story := style == "storybook"
	p.custom_minimum_size = Vector2(width, 14 if story else 5)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color.WHITE if story else Color(c("text"), 0.15)
	bg.set_corner_radius_all(8 if story else 2)
	if story:
		bg.set_border_width_all(2)
		bg.border_color = c("ink")
	var fill := StyleBoxFlat.new()
	fill.bg_color = c(color_key)
	fill.set_corner_radius_all(8 if story else 2)
	p.add_theme_stylebox_override("background", bg)
	p.add_theme_stylebox_override("fill", fill)
	return p

static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

static func panel(alt: bool = false) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_box(alt))
	return p
