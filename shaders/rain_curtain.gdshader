shader_type spatial;
// A rain curtain under a cloud (WeatherView): a soft tube of falling streaks,
// strongest at its middle, fading to nothing at the cloud and the ground's
// edge. COLOR.a is how hard it rains; COLOR.r how stormy (darker, denser).
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.56, 0.62, 0.72, 1.0);
uniform float scroll = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float col = floor(uv.x * 90.0);
	float speed = 0.6 + hash(vec2(col, 1.0)) * 0.6;
	float streak = fract(uv.y * 7.0 + scroll * speed + hash(vec2(col, 3.0)));
	float s = smoothstep(0.0, 0.25, streak) * smoothstep(0.65, 0.3, streak);
	float body = smoothstep(0.0, 0.25, uv.y) * smoothstep(1.0, 0.82, uv.y);
	// Edge-on parts of the tube read thicker: keep the curtain soft at its rim.
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	float storm = COLOR.r;
	vec3 c = mix(tint.rgb, tint.rgb * 0.55, storm);
	ALBEDO = c;
	ALPHA = COLOR.a * body * (0.10 + 0.22 * s) * (0.6 + 0.4 * rim) * (1.0 + 0.6 * storm);
}
