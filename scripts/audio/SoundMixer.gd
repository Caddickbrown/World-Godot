class_name SoundMixer
extends RefCounted
## What the island sounds like from where you are: pure functions from a
## "scene" (what the ear is near, the hour, the season, the weather) to the
## level of each bed and the rate of each kind of call. No nodes, no state, so
## tests can ask "the shore at dawn" or "inland at night in the rain" directly.
##
## A scene is a Dictionary:
##   hour (0-24), season ("Spring".."Winter"), walk (bool: the wisp's ear),
##   cam_dist (metres from the focus), height (metres above the ground),
##   sea (0..1 of the ground round you that is sea), woods (0..1 trees),
##   fresh (0..1 rivers and their banks), rain (0..1), storm (0..1).

const BEDS := ["surf", "wind", "rain_soft", "rain_leaves", "crickets", "chorus"]

const BIRD_SEASON := {"Spring": 1.0, "Summer": 0.8, "Autumn": 0.45, "Winter": 0.15}
const CHORUS_SEASON := {"Spring": 1.0, "Summer": 0.6, "Autumn": 0.2, "Winter": 0.0}
const CRICKET_SEASON := {"Spring": 0.35, "Summer": 1.0, "Autumn": 0.6, "Winter": 0.0}
const FROG_SEASON := {"Spring": 1.0, "Summer": 0.9, "Autumn": 0.4, "Winter": 0.0}

## 0 at night, 1 by day, eased through dawn and dusk.
static func daylight(hour: float) -> float:
	return smoothstep(5.0, 7.0, hour) * (1.0 - smoothstep(19.0, 21.0, hour))

## The dawn chorus: rises from 04:30, at its height about 06:00-07:30.
static func dawn(hour: float) -> float:
	return smoothstep(4.5, 6.0, hour) * (1.0 - smoothstep(7.5, 9.0, hour))

## Rain and storm amounts from how overcast the sky is where you look
## (WeatherSystem.overcast_at: cloudy 0.3, rain 0.6, storm 1.0).
static func rain_from_overcast(oc: float) -> Vector2:
	return Vector2(clampf((oc - 0.4) / 0.2, 0.0, 1.0), clampf((oc - 0.8) / 0.2, 0.0, 1.0))

## The beds' levels (0..1) and the calls' rates (per second) for a scene.
static func mix(s: Dictionary) -> Dictionary:
	var hour := float(s.get("hour", 12.0))
	var season := str(s.get("season", "Spring"))
	var sea := clampf(float(s.get("sea", 0.0)), 0.0, 1.0)
	var woods := clampf(float(s.get("woods", 0.0)), 0.0, 1.0)
	var fresh := clampf(float(s.get("fresh", 0.0)), 0.0, 1.0)
	var rain := clampf(float(s.get("rain", 0.0)), 0.0, 1.0)
	var storm := clampf(float(s.get("storm", 0.0)), 0.0, 1.0)
	var height := float(s.get("height", 2.0))
	var day := daylight(hour)
	var night := 1.0 - day
	var dawn_k := dawn(hour)
	var land := 1.0 - sea
	var high := smoothstep(15.0, 260.0, height)   # 0 on the ground, 1 at the top of the sky
	var dry := 1.0 - 0.85 * rain
	var birds: float = BIRD_SEASON.get(season, 0.5)
	var choir: float = CHORUS_SEASON.get(season, 0.0)
	var out := {}
	# The sea: louder the more of it is round you, and wilder in a storm.
	out["surf"] = clampf(pow(sea, 0.7) * (0.7 + 0.3 * storm) * (1.0 - 0.25 * high), 0.0, 1.0)
	# Wind: a breath on the ground, more up high, a lot in a storm.
	var winter := 0.12 if season == "Winter" else 0.0
	out["wind"] = clampf(0.1 + 0.5 * high + 0.55 * storm + 0.15 * rain + winter + 0.1 * sea, 0.0, 1.0)
	# Rain where you're looking: on leaves under trees, softer in the open.
	var r := rain * (1.0 - 0.3 * high)
	out["rain_leaves"] = r * woods
	out["rain_soft"] = r * (1.0 - 0.6 * woods)
	# Crickets on warm nights over land; rain hushes them.
	out["crickets"] = night * float(CRICKET_SEASON.get(season, 0.0)) * land * (1.0 - 0.9 * rain) * (0.5 + 0.5 * (1.0 - high))
	# Birds: the chorus at dawn in spring, a thinner bed by day; over land, woods most.
	var habitat := land * (0.45 + 0.55 * woods)
	out["chorus"] = clampf((dawn_k * choir + 0.22 * day * birds) * habitat * dry, 0.0, 1.0)
	# Calls (per second, before distance).
	out["bird_rate"] = (0.12 + 1.4 * dawn_k * choir) * maxf(day, dawn_k) * birds * habitat * dry * (1.0 - 0.6 * high)
	out["coo_rate"] = 0.03 * day * birds * land * dry
	out["gull_rate"] = 0.12 * day * sea * (1.0 - 0.5 * rain)
	out["owl_rate"] = 0.025 * night * woods * dry
	out["frog_rate"] = 0.5 * night * fresh * float(FROG_SEASON.get(season, 0.0)) * (1.0 - 0.5 * rain)
	out["wolf_rate"] = 0.02 * night * land * (1.4 if season == "Winter" else 1.0)
	return out

## How the ear hears point sources (fires, voices, calls) in each view.
## The wisp is close and hears detail; the sky hears the island as a whole, so
## a single voice fades out as you rise while the beds carry on.
##   ref: metres at which a source is at half its level
##   radius: metres past which it isn't heard at all
##   detail: how much of the small close sounds come through
static func hearing(walk: bool, cam_dist: float) -> Dictionary:
	if walk:
		return {"ref": 9.0, "radius": 60.0, "detail": 1.0}
	var ref := 10.0 + 0.28 * cam_dist
	return {"ref": ref, "radius": ref * 4.0, "detail": lerpf(0.85, 0.3, smoothstep(30.0, 300.0, cam_dist))}

## Level of a source d metres from the ear (1 at the ear, 1/2 at ref, 0 past
## radius, always falling with distance).
static func falloff(d: float, ref: float, radius: float = INF) -> float:
	if d >= radius:
		return 0.0
	var g := 1.0 / (1.0 + pow(d / ref, 2.0))
	if radius < INF:
		g *= 1.0 - smoothstep(radius * 0.7, radius, d)
	return g

## Seconds before thunder reaches you from d metres. Sound is slowed three
## times over: the island is small, and the wait is the pleasure of it.
static func thunder_delay(d: float) -> float:
	return clampf(d / 343.0 * 3.0, 0.08, 4.0)

## How loud thunder is from d metres (it carries: never below a far grumble).
static func thunder_gain(d: float) -> float:
	return maxf(0.22, 1.0 / (1.0 + pow(d / 140.0, 2.0)))
