class_name SeasonDial
extends Control
## A round dial: four season quarters and a hand showing how far through the
## year we are. Drawn, so it follows the UI style.

var year_fraction := 0.0   # 0 = first day of spring, 1 = end of winter

const SEASON_COLORS := {
	"storybook": [Color("9BD06E"), Color("FFD25A"), Color("F0803C"), Color("BFE3F2")],
	"fieldnotes": [Color("7E9A6A"), Color("C9A04E"), Color("B5674A"), Color("9FB8B4")],
}

func _init() -> void:
	custom_minimum_size = Vector2(48, 48)
	tooltip_text = "Season dial"

func set_year(fraction: float) -> void:
	year_fraction = fposmod(fraction, 1.0)
	queue_redraw()

func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5 - 2.0
	var ctr := size * 0.5
	var cols: Array = SEASON_COLORS[UiTheme.style]
	for i in 4:
		var a0 := -PI / 2.0 + TAU * i / 4.0
		var pts := PackedVector2Array([ctr])
		for k in 13:
			var a := a0 + (TAU / 4.0) * k / 12.0
			pts.append(ctr + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, cols[i])
	var line := UiTheme.c("ink") if UiTheme.style == "storybook" else UiTheme.c("text")
	draw_arc(ctr, r, 0.0, TAU, 40, line, 2.5 if UiTheme.style == "storybook" else 1.0, true)
	var hand := -PI / 2.0 + TAU * year_fraction
	draw_line(ctr, ctr + Vector2(cos(hand), sin(hand)) * (r - 4.0), line, 3.0, true)
	draw_circle(ctr, 3.5, line)
