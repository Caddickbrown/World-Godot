class_name SeasonLook
extends RefCounted
## How the year shows on the land: snow lying in winter, bare broadleaf, the
## autumn turn, spring's fresh greens, meadow flowers. Pure functions of the
## calendar, so the look never needs the simulation and tests can read it.
##
## Everything here is a continuous 0..1 blend, eased over the first day or two
## of a season, so nothing cuts. The renderers feed the values to shader
## uniforms (one per material), so a season change costs no rebuild.

const SEASON_DAYS := float(TimeSystem.SEASON_DAYS)

## The blend for a point in the calendar. days = game_time / DAY_LENGTH (0 at
## the first morning). Keys:
##   snow   ground snow cover        autumn  broadleaf turned (orange, red, gold)
##   bare   broadleaf leaves down    spring  fresh light greens
##   dry    late-summer straw        winter  dull winter grass (under any snow)
##   bloom  meadow flowers out (0 none .. 1 full)
static func blend(days: float) -> Dictionary:
	var d := maxf(days, 0.0)
	var idx := int(d / SEASON_DAYS) % 4
	var p := fmod(d, SEASON_DAYS)       # days into this season
	var first_spring := d < SEASON_DAYS  # the world wakes in spring: no winter to melt
	var b := {"snow": 0.0, "autumn": 0.0, "bare": 0.0, "spring": 0.0, "dry": 0.0, "winter": 0.0, "bloom": 0.0}
	match idx:
		0:  # Spring: last snow melts, buds break, the meadows flower
			if first_spring:
				p = maxf(p, 2.0)
			b["snow"] = 1.0 - smoothstep(0.0, 1.2, p)
			b["winter"] = 1.0 - smoothstep(0.0, 1.5, p)
			b["bare"] = 1.0 - smoothstep(0.3, 1.8, p)
			b["spring"] = smoothstep(0.6, 1.8, p) * (1.0 - 0.5 * smoothstep(5.0, 7.0, p))
			b["bloom"] = smoothstep(0.8, 2.0, p)
		1:  # Summer: still green, drying to straw late on
			b["spring"] = 0.5 * (1.0 - smoothstep(0.0, 2.0, p))
			b["dry"] = 0.6 * smoothstep(3.0, 7.0, p)
			b["bloom"] = 1.0 - 0.6 * smoothstep(4.0, 7.0, p)
		2:  # Autumn: the broadleaf turn, leaves start to fall at the end
			b["autumn"] = smoothstep(0.0, 2.5, p)
			b["dry"] = 0.6 * (1.0 - smoothstep(0.0, 2.0, p))
			b["bloom"] = 0.4 * (1.0 - smoothstep(0.0, 2.0, p))
			b["bare"] = 0.5 * smoothstep(5.0, 7.0, p)
			b["winter"] = 0.4 * smoothstep(5.0, 7.0, p)
		3:  # Winter: bare woods, then snow lies
			b["bare"] = 0.5 + 0.5 * smoothstep(0.0, 1.0, p)
			b["autumn"] = 1.0 - smoothstep(0.0, 1.2, p)
			b["winter"] = 0.4 + 0.6 * smoothstep(0.0, 1.0, p)
			b["snow"] = smoothstep(0.3, 1.8, p)
	return b

## A forced season for captures and tests: the look of `name` well under way.
static func blend_for(name: String) -> Dictionary:
	var i := TimeSystem.SEASONS.find(name.capitalize())
	if i < 0:
		i = 0
	# Day 3 of that season in the second year (so spring has a winter behind it).
	return blend((4 + i) * SEASON_DAYS + 3.0)

## Push a blend into a material's uniforms (any of the season shaders).
static func apply(mat: ShaderMaterial, b: Dictionary) -> void:
	if mat == null:
		return
	for k in b:
		mat.set_shader_parameter(k, float(b[k]))
	mat.set_shader_parameter("naturalist", 1.0 if LookStyle.naturalist() else 0.0)
