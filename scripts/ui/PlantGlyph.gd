class_name PlantGlyph
extends Control
## An idea drawn as a plant: a seed (unthought), a sprout (a few hold it), a
## flower (widely held) or a drooping stem (lost). Used by the Idea Garden.

var stage := IdeaLedger.Stage.SEED
var petal := Color("F0803C")

func _init() -> void:
	custom_minimum_size = Vector2(56, 56)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func setup(p_stage: int, p_petal: Color) -> PlantGlyph:
	stage = p_stage
	petal = p_petal
	queue_redraw()
	return self

func _draw() -> void:
	var story := UiTheme.style == "storybook"
	var ink := UiTheme.c("ink") if story else _stage_ink()
	var w := 3.0 if story else 1.5
	var s := minf(size.x, size.y) / 56.0
	var base := Vector2(size.x * 0.5, size.y - 6.0 * s)
	draw_line(base + Vector2(-18, 0) * s, base + Vector2(18, 0) * s, ink, w, true)
	match stage:
		IdeaLedger.Stage.SEED:
			_ellipse(base + Vector2(0, -4) * s, Vector2(6, 4) * s, Color("C9A27A") if story else Color(0, 0, 0, 0), ink, w)
		IdeaLedger.Stage.SPROUT:
			draw_line(base, base + Vector2(0, -24) * s, ink, w, true)
			_leaf(base + Vector2(0, -14) * s, Vector2(-11, -6) * s, Color("9BD06E"), ink, w, story)
			_leaf(base + Vector2(0, -20) * s, Vector2(11, -7) * s, Color("6DB04A"), ink, w, story)
		IdeaLedger.Stage.BLOOM:
			draw_line(base, base + Vector2(0, -30) * s, ink, w, true)
			_leaf(base + Vector2(0, -12) * s, Vector2(-11, -5) * s, Color("6DB04A"), ink, w, story)
			var head := base + Vector2(0, -36) * s
			for i in 5:
				var a := -PI / 2.0 + TAU * i / 5.0
				var p := head + Vector2(cos(a), sin(a)) * 8.0 * s
				if story:
					draw_circle(p, 6.0 * s, petal)
				draw_arc(p, 6.0 * s, 0, TAU, 16, ink, w * 0.7, true)
			draw_circle(head, 5.0 * s, Color("FFD25A") if story else ink)
		IdeaLedger.Stage.WILTED:
			var pts := PackedVector2Array()
			for k in 9:
				var t := k / 8.0
				pts.append(base + Vector2(sin(t * 1.4) * 14.0, -t * 26.0 + t * t * 10.0) * s)
			draw_polyline(pts, ink, w, true)
			_leaf(pts[pts.size() - 1], Vector2(6, 9) * s, Color("B5A07A"), ink, w, story)

func _stage_ink() -> Color:
	match stage:
		IdeaLedger.Stage.SEED: return Color("6E6A5E")
		IdeaLedger.Stage.SPROUT: return Color("9FB58C")
		IdeaLedger.Stage.WILTED: return Color("B5674A")
	return UiTheme.c("text")

func _leaf(from: Vector2, dir: Vector2, fill: Color, ink: Color, w: float, filled: bool) -> void:
	var tip := from + dir
	var mid := (from + tip) * 0.5
	var nrm := Vector2(-dir.y, dir.x).normalized() * dir.length() * 0.35
	var pts := PackedVector2Array([from, mid + nrm, tip, mid - nrm])
	if filled:
		draw_colored_polygon(pts, fill)
	pts.append(from)
	draw_polyline(pts, ink, w * 0.8, true)

func _ellipse(ctr: Vector2, radii: Vector2, fill: Color, ink: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for k in 17:
		var a := TAU * k / 16.0
		pts.append(ctr + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	if fill.a > 0.0:
		draw_colored_polygon(pts, fill)
	draw_polyline(pts, ink, w, true)
