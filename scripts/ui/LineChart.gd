class_name LineChart
extends Control
## A small line chart drawn in the UI's own look: storybook gets chunky ink
## axes and a soft fill under the first line; field notes hairlines. Days run
## along the bottom. Set `lines` ([{points: PackedVector2Array, color_key,
## label, fill}]) and call queue_redraw().

var lines: Array = []
var y_label := ""
var min_y_max := 10.0
const PAD_L := 40.0
const PAD_B := 26.0
const PAD_T := 10.0
const PAD_R := 12.0

func _init() -> void:
	custom_minimum_size = Vector2(420, 180)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## A round number at or above v for the top of the axis.
static func nice_ceiling(v: float) -> float:
	if v <= 0.0:
		return 1.0
	var mag := pow(10.0, floor(log(v) / log(10.0)))
	for m in [1.0, 2.0, 2.5, 5.0, 10.0]:
		if v <= m * mag:
			return m * mag
	return 10.0 * mag

func _draw() -> void:
	var story := UiTheme.style == "storybook"
	var ink := UiTheme.c("ink") if story else UiTheme.c("text")
	var faint := Color(ink, 0.18 if story else 0.14)
	var font := UiTheme.font("body")
	var fs := 13
	var area := Rect2(PAD_L, PAD_T, size.x - PAD_L - PAD_R, size.y - PAD_T - PAD_B)
	var x_max := 1.0
	var y_max := min_y_max
	for l in lines:
		for p in (l["points"] as PackedVector2Array):
			x_max = maxf(x_max, p.x)
			y_max = maxf(y_max, p.y)
	y_max = nice_ceiling(y_max)
	x_max = ceil(x_max)
	var to_px := func(p: Vector2) -> Vector2:
		return Vector2(area.position.x + p.x / x_max * area.size.x, area.end.y - p.y / y_max * area.size.y)
	# Grid and y ticks
	for i in 5:
		var v := y_max * i / 4.0
		var y := area.end.y - area.size.y * i / 4.0
		draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), faint, 1.0)
		draw_string(font, Vector2(2, y + 5), "%d" % int(v), HORIZONTAL_ALIGNMENT_RIGHT, PAD_L - 8, fs, Color(ink, 0.7))
	# Day ticks
	var step := maxi(1, int(ceil(x_max / 8.0)))
	var d := 0
	while d <= int(x_max):
		var x: float = to_px.call(Vector2(d, 0)).x
		draw_line(Vector2(x, area.end.y), Vector2(x, area.end.y + 4), Color(ink, 0.6), 1.0)
		draw_string(font, Vector2(x - 20, area.end.y + 18), "day %d" % (d + 1) if d == 0 else str(d + 1), HORIZONTAL_ALIGNMENT_CENTER, 40, fs, Color(ink, 0.7))
		d += step
	# Lines
	for li in lines.size():
		var l: Dictionary = lines[li]
		var pts: PackedVector2Array = l["points"]
		if pts.size() < 2:
			continue
		var col: Color = UiTheme.c(str(l.get("color_key", "accent")))
		var px := PackedVector2Array()
		for p in pts:
			px.append(to_px.call(p))
		if bool(l.get("fill", false)):
			var poly := px.duplicate()
			poly.append(Vector2(px[px.size() - 1].x, area.end.y))
			poly.append(Vector2(px[0].x, area.end.y))
			draw_colored_polygon(poly, Color(col, 0.22 if story else 0.14))
		if story:
			draw_polyline(px, ink, 5.0, true)
		draw_polyline(px, col, 3.0 if story else 1.6, true)
		var last := px[px.size() - 1]
		draw_circle(last, 5.0 if story else 3.0, col)
		if story:
			draw_arc(last, 5.0, 0, TAU, 16, ink, 1.5, true)
	# Axes
	draw_line(Vector2(area.position.x, area.position.y), Vector2(area.position.x, area.end.y), ink, 2.5 if story else 1.0)
	draw_line(Vector2(area.position.x, area.end.y), Vector2(area.end.x, area.end.y), ink, 2.5 if story else 1.0)
