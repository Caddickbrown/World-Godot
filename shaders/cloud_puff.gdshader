shader_type spatial;
// A cloud puff (WeatherView): instance colour in COLOR, how much of it shows in
// COLOR.a. Drawn opaque and dithered away rather than blended, so clouds cast
// (dappled) shadows and sort cleanly however many overlap.
render_mode cull_back, diffuse_lambert, specular_disabled;

varying vec3 lpos;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), u.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), u.x), u.y);
	float b = mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), u.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), u.x), u.y);
	return mix(a, b, u.z);
}

vec3 to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
}

void vertex() {
	lpos = VERTEX;
	// A lumpy outline rather than a perfect ball.
	vec3 o = MODEL_MATRIX[3].xyz;
	VERTEX *= 1.0 + 0.16 * (vnoise3(VERTEX * 2.2 + o * 0.05) - 0.5);
}

void fragment() {
	float a = COLOR.a;
	float dither = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	if (a < 0.999 && a <= dither) {
		discard;
	}
	vec3 c = to_linear(COLOR.rgb);
	// Flat-bottomed, bright-topped.
	float top = smoothstep(-0.6, 0.8, lpos.y);
	ALBEDO = c * mix(0.78, 1.05, top);
	BACKLIGHT = vec3(0.25);
	ROUGHNESS = 1.0;
}
