class_name HudScreen
extends Control
## A full-screen page over the world (Lives, Ideas, Album): a dimmed backdrop,
## a page panel with a title and a close button. Subclasses fill `body`.

var hud: GameHud
var body: Control

func build_screen() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(UiTheme.c("ink"), 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var page := UiTheme.panel()
	var sb := UiTheme.panel_box()
	sb.set_content_margin_all(28)
	if UiTheme.style == "fieldnotes":
		sb.bg_color = UiTheme.c("screen_bg")
	page.add_theme_stylebox_override("panel", sb)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.offset_left = 48
	page.offset_right = -48
	page.offset_top = 40
	page.offset_bottom = -40
	add_child(page)
	var v := UiTheme.vbox(16)
	page.add_child(v)
	var head := UiTheme.hbox(16)
	var titles := UiTheme.vbox(2)
	titles.add_child(UiTheme.caps(kicker()))
	titles.add_child(UiTheme.label(title(), "display", 40))
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	var blurb := UiTheme.wrap(UiTheme.label(subtitle(), "hand", 18, "muted"), 380)
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(blurb)
	var close := UiTheme.button("Close", false, 15)
	close.tooltip_text = "Close (Esc)"
	close.pressed.connect(func(): hud.close_screen())
	head.add_child(close)
	v.add_child(head)
	body = Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	fill()

func kicker() -> String: return ""
func title() -> String: return ""
func subtitle() -> String: return ""
func fill() -> void: pass

func main() -> Node:
	return hud.main

## A scrolling column, for lists that can grow.
func scroll_column(min_width: float, sep: int = 10) -> Array:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size.x = min_width
	var col := UiTheme.vbox(sep)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(col)
	return [sc, col]
