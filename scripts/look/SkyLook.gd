class_name SkyLook
extends Node3D
## Sky, sun, moonlight, haze and the time-of-day grade. set_time(time_of_day)
## each frame (0 = midnight, 0.25 = 6:00). Follows LookStyle.

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env: Environment
var _sky: ProceduralSkyMaterial
var overcast := 0.0                  # 0 clear .. 1 storm; eased towards the weather by set_weather
var _overcast_goal := 0.0
var _rain: GPUParticles3D

func _ready() -> void:
	env = Environment.new()
	var sky := Sky.new()
	_sky = ProceduralSkyMaterial.new()
	_sky.sun_angle_max = 20.0
	sky.sky_material = _sky
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
	apply_style()
	set_time(0.4)

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
	overcast = move_toward(overcast, _overcast_goal, dt * 0.25)
	if _rain:
		_rain.emitting = raining
		_rain.amount_ratio = clampf(overcast, 0.3, 1.0)
		_rain.global_position = focus + Vector3(0, 22, 0)

func apply_style() -> void:
	var nat := LookStyle.naturalist()
	env.tonemap_mode = Environment.TONE_MAPPER_ACES if nat else Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.88 if nat else 0.92
	env.fog_density = 0.0018 if nat else 0.0016
	env.fog_aerial_perspective = 0.35 if nat else 0.6

func set_time(tod: float) -> void:
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
	var night := 1.0 - smoothstep(-1.0, 1.0, minf(hour - 5.0, 20.5 - hour))
	moon.light_energy = 0.35 * night
	var top := Color(0.32, 0.55, 0.85).lerp(Color(0.30, 0.38, 0.62), warm)
	var horizon := Color(0.78, 0.84, 0.88).lerp(Color(0.98, 0.70, 0.50), warm)
	top = top.lerp(Color(0.04, 0.06, 0.16), night)
	horizon = horizon.lerp(Color(0.10, 0.12, 0.24), night)
	if LookStyle.naturalist():
		horizon = horizon.lerp(Color(0.80, 0.80, 0.78), 0.35 * (1.0 - night))
		top = top.lerp(Color(0.45, 0.52, 0.60), 0.4 * (1.0 - night))
	# Cloud: greyer, flatter, the sun behind it.
	var grey := Color(0.52, 0.55, 0.60).lerp(Color(0.10, 0.11, 0.14), night)
	top = top.lerp(grey.darkened(0.15), 0.85 * overcast)
	horizon = horizon.lerp(grey, 0.8 * overcast)
	sun.light_energy *= 1.0 - 0.7 * overcast
	sun.shadow_opacity = 1.0 - 0.6 * overcast
	_sky.sky_top_color = top
	_sky.sky_horizon_color = horizon
	_sky.ground_horizon_color = horizon.darkened(0.1)
	_sky.ground_bottom_color = Color(0.12, 0.18, 0.26).lerp(Color(0.02, 0.03, 0.06), night)
	env.ambient_light_energy = lerpf(0.9, 0.35, night)
	env.fog_light_color = Color(0.74, 0.82, 0.90).lerp(Color(0.95, 0.72, 0.58), warm).lerp(Color(0.10, 0.12, 0.22), night)
	env.fog_light_color = env.fog_light_color.lerp(grey, 0.7 * overcast)
	env.fog_density = (0.0018 if LookStyle.naturalist() else 0.0016) * (1.0 + 2.5 * overcast)

## 0 at noon .. 1 deep night, for lanterns and fires.
func darkness(tod: float) -> float:
	var hour := tod * 24.0
	return 1.0 - smoothstep(-1.5, 1.5, minf(hour - 6.0, 19.5 - hour))
