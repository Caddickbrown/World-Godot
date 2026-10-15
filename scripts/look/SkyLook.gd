class_name SkyLook
extends Node3D
## Sky, sun, moon, haze and the time-of-day grade. set_time(time_of_day) each
## frame (0 = midnight, 0.25 = 6:00). Follows LookStyle.
##
## The sky is a shader (shaders/sky_world.gdshader): clouds drift by day and
## thicken when overcast; at night there are stars, a Milky Way band, the moon
## crossing opposite the sun and, now and then, a shooting star. Weather is
## what's over the camera's focus (WeatherSystem's zone there, blended with
## its neighbours), not the worst zone on the island; WeatherView draws the
## rest of the island's weather (clouds and rain curtains over each zone,
## lightning, the rainbow).
##
## Visual randomness comes from a local RandomNumberGenerator: looking must
## never move the simulation's dice.

## Shooting stars: per real second, while the sky is dark and clear.
const METEOR_PER_SECOND := 0.12
const METEOR_SECONDS := 0.9
const OVERCAST_EASE := 0.25          # overcast units per game-second

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env: Environment
var _sky: ShaderMaterial
var overcast := 0.0                  # 0 clear .. 1 storm; eased towards the weather by set_weather
var _overcast_goal := 0.0
var _rain: GPUParticles3D
var weather_view: WeatherView
var night := 0.0                     # 0 day .. 1 deep night (as last set_time)
var cloud_offset := Vector2.ZERO
var meteor_t := -1.0                 # progress of the current shooting star, < 0 none
var meteors_seen := 0
var flash := 0.0                     # lightning flash, decays in real time
var raining_here := false
var _rng := RandomNumberGenerator.new()
var _twinkle := 0.0
var _tod := 0.4

func _ready() -> void:
	_rng.seed = 911
	env = Environment.new()
	var sky := Sky.new()
	_sky = ShaderMaterial.new()
	_sky.shader = preload("res://shaders/sky_world.gdshader")
	sky.sky_material = _sky
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_sun_scatter = 0.25
	env.ssao_enabled = true
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.4
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	sun.light_angular_distance = 1.0
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.65, 0.9)
	moon.rotation = Vector3(deg_to_rad(-50), deg_to_rad(30), 0)
	add_child(moon)
	_rain = _make_rain()
	add_child(_rain)
	weather_view = WeatherView.new()
	add_child(weather_view)
	apply_style()
	set_time(0.4)

## Stars twinkle, shooting stars fall and lightning fades in real time, so
## the sky stays alive while the simulation is paused (overlays never freeze).
func _process(delta: float) -> void:
	animate(delta)

func animate(delta: float) -> void:
	_twinkle += delta
	flash = maxf(0.0, flash - delta * 5.0)
	if meteor_t >= 0.0:
		meteor_t += delta / METEOR_SECONDS
		if meteor_t > 1.0:
			meteor_t = -1.0
	elif night > 0.6 and overcast < 0.4 and _rng.randf() < METEOR_PER_SECOND * delta:
		shooting_star()
	_sky.set_shader_parameter("twinkle_t", _twinkle)
	_sky.set_shader_parameter("meteor_t", meteor_t)
	_sky.set_shader_parameter("flash", flash * 0.6)
	env.ambient_light_energy = _ambient + flash * 1.5

## Start a shooting star somewhere overhead (also used by captures and tests).
func shooting_star() -> void:
	var az := _rng.randf() * TAU
	var el := deg_to_rad(_rng.randf_range(35.0, 70.0))
	var a := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el))
	var turn := az + _rng.randf_range(0.35, 0.6) * (1.0 if _rng.randf() < 0.5 else -1.0)
	var el2 := el - deg_to_rad(_rng.randf_range(12.0, 22.0))
	var b := Vector3(cos(turn) * cos(el2), sin(el2), sin(turn) * cos(el2))
	_sky.set_shader_parameter("meteor_a", a)
	_sky.set_shader_parameter("meteor_b", b)
	meteor_t = 0.0
	meteors_seen += 1

## A lightning flash (WeatherView calls this with each bolt it draws).
func lightning_flash(strength: float = 1.0) -> void:
	flash = maxf(flash, clampf(strength, 0.0, 1.0))

## Rain falls in a box round the camera's focus, so it costs the same anywhere.
func _make_rain() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 1600
	p.lifetime = 0.9
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(30, 1, 30)
	pm.direction = Vector3(0.15, -1, 0.05)
	pm.spread = 3.0
	pm.initial_velocity_min = 26.0
	pm.initial_velocity_max = 32.0
	pm.gravity = Vector3.ZERO
	p.process_material = pm
	var streak := QuadMesh.new()
	streak.size = Vector2(0.05, 1.1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.86, 0.90, 0.97, 0.55)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	streak.material = m
	p.draw_pass_1 = streak
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

## Weather the eye can see: rain 0.6, storm 1.0. focus is where the camera
## looks; the rain box sits above it.
func set_weather(goal: float, raining: bool, focus: Vector3, dt: float) -> void:
	_overcast_goal = goal
	overcast = move_toward(overcast, _overcast_goal, dt * OVERCAST_EASE)
	raining_here = raining
	cloud_offset += Vector2(WeatherView.WIND.x, WeatherView.WIND.y) * dt * 0.004
	if _rain:
		_rain.emitting = raining
		_rain.amount_ratio = clampf(overcast, 0.3, 1.0)
		_rain.global_position = focus + Vector3(0, 22, 0)

## The weather at the camera's focus (tile coords from world metres), and the
## island's weather for WeatherView. dt is game-seconds; hour for the rainbow.
func watch_weather(ws: WeatherSystem, focus: Vector3, dt: float) -> void:
	var tx := focus.x / World.TILE_SIZE
	var tz := focus.z / World.TILE_SIZE
	set_weather(ws.overcast_at(tx, tz), ws.is_raining_at(tx, tz), focus, dt)
	if weather_view:
		weather_view.update_weather(ws, focus, dt, self)

func apply_style() -> void:
	var nat := LookStyle.naturalist()
	env.tonemap_mode = Environment.TONE_MAPPER_ACES if nat else Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.88 if nat else 0.92
	env.fog_density = 0.0018 if nat else 0.0016
	env.fog_aerial_perspective = 0.35 if nat else 0.6
	# Storybook: a brighter, cuter night (big moon, rich stars); field notes subdued.
	_sky.set_shader_parameter("star_gain", 0.7 if nat else 1.25)
	_sky.set_shader_parameter("milky_gain", 0.6 if nat else 1.2)
	_sky.set_shader_parameter("moon_size", deg_to_rad(1.6 if nat else 2.4))
	if weather_view:
		weather_view.apply_style()

var _ambient := 0.9

func set_time(tod: float) -> void:
	_tod = tod
	var hour := tod * 24.0
	var day := clampf((hour - 6.0) / 13.5, 0.0, 1.0)
	var up := hour > 5.5 and hour < 19.8
	var elev := sin(day * PI) if up else 0.0
	sun.visible = up
	sun.rotation = Vector3(-deg_to_rad(4.0 + 60.0 * elev), deg_to_rad(lerpf(-100.0, 100.0, day)) + PI, 0)
	var warm := 1.0 - smoothstep(0.15, 0.45, elev)
	sun.light_color = Color(1.0, 0.97, 0.90).lerp(Color(1.0, 0.62, 0.36), warm)
	sun.light_energy = lerpf(0.25, 1.25, smoothstep(0.0, 0.5, elev))
	# Night: a dim blue world under moonlight, never black.
	night = 1.0 - smoothstep(-1.0, 1.0, minf(hour - 5.0, 20.5 - hour))
	moon.light_energy = 0.35 * night * (1.0 - 0.6 * overcast)
	# The moon crosses the night sky opposite the sun (rises about 18:30).
	var m := fposmod(hour - 18.5, 24.0) / 12.0
	var m_el := sin(clampf(m, 0.0, 1.0) * PI)
	moon.rotation = Vector3(-deg_to_rad(8.0 + 52.0 * m_el), deg_to_rad(lerpf(-100.0, 100.0, clampf(m, 0.0, 1.0))), 0)
	var top := Color(0.32, 0.55, 0.85).lerp(Color(0.30, 0.38, 0.62), warm)
	var horizon := Color(0.78, 0.84, 0.88).lerp(Color(0.98, 0.70, 0.50), warm)
	top = top.lerp(Color(0.04, 0.06, 0.16), night)
	horizon = horizon.lerp(Color(0.10, 0.12, 0.24), night)
	if LookStyle.naturalist():
		horizon = horizon.lerp(Color(0.80, 0.80, 0.78), 0.35 * (1.0 - night))
		top = top.lerp(Color(0.45, 0.52, 0.60), 0.4 * (1.0 - night))
		top = top.lerp(Color(0.03, 0.04, 0.08), 0.3 * night)
	# Cloud: greyer, flatter, the sun behind it.
	var grey := Color(0.52, 0.55, 0.60).lerp(Color(0.10, 0.11, 0.14), night)
	top = top.lerp(grey.darkened(0.15), 0.85 * overcast)
	horizon = horizon.lerp(grey, 0.8 * overcast)
	sun.light_energy *= 1.0 - 0.7 * overcast
	sun.shadow_opacity = 1.0 - 0.6 * overcast
	_sky.set_shader_parameter("top_color", top)
	_sky.set_shader_parameter("horizon_color", horizon)
	_sky.set_shader_parameter("ground_horizon", horizon.darkened(0.1))
	_sky.set_shader_parameter("ground_bottom", Color(0.12, 0.18, 0.26).lerp(Color(0.02, 0.03, 0.06), night))
	_sky.set_shader_parameter("sun_dir", sun.transform.basis.z)
	_sky.set_shader_parameter("sun_color", sun.light_color)
	_sky.set_shader_parameter("sun_visible", 1.0 if up else 0.0)
	_sky.set_shader_parameter("moon_dir", moon.transform.basis.z)
	_sky.set_shader_parameter("night", night)
	_sky.set_shader_parameter("overcast", overcast)
	# Clouds: a few fair-weather puffs on a clear day, a lid when overcast; lit
	# warm at dusk, dark blue-grey at night.
	var nat := LookStyle.naturalist()
	_sky.set_shader_parameter("cloud_cover", lerpf(0.22 if nat else 0.30, 0.97, overcast))
	var lit := Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.78, 0.62), warm * (1.0 - night)).lerp(Color(0.13, 0.15, 0.24), night)
	lit = lit.lerp(Color(0.62, 0.64, 0.68).lerp(Color(0.08, 0.09, 0.12), night), overcast * 0.85)
	_sky.set_shader_parameter("cloud_lit", lit)
	_sky.set_shader_parameter("cloud_shade", lit.darkened(0.32))
	_sky.set_shader_parameter("cloud_offset", cloud_offset)
	_ambient = lerpf(0.9, 0.35, night)
	env.ambient_light_energy = _ambient + flash * 1.5
	env.fog_light_color = Color(0.74, 0.82, 0.90).lerp(Color(0.95, 0.72, 0.58), warm).lerp(Color(0.10, 0.12, 0.22), night)
	env.fog_light_color = env.fog_light_color.lerp(grey, 0.7 * overcast)
	env.fog_density = (0.0018 if LookStyle.naturalist() else 0.0016) * (1.0 + 2.5 * overcast)
	if weather_view:
		weather_view.set_light(sun.transform.basis.z, night, warm, up and elev > 0.05)

## 0 at noon .. 1 deep night, for lanterns and fires.
func darkness(tod: float) -> float:
	var hour := tod * 24.0
	return 1.0 - smoothstep(-1.5, 1.5, minf(hour - 6.0, 19.5 - hour))

## Toward the sun (unit vector), for anything placed by it (the rainbow).
func sun_direction() -> Vector3:
	return sun.transform.basis.z
