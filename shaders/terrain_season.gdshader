shader_type spatial;
// The ground, vertex-coloured by LookStyle.ground (sRGB), with the season laid
// over it here so a season change is a uniform, not a mesh rebuild
// (SeasonLook.blend feeds these). Vegetation is told apart from sand, rock and
// water by how green the vertex colour is; snow lies on flat ground above the
// beach band, in patches at first.

uniform float snow = 0.0;
uniform float autumn = 0.0;
uniform float spring = 0.0;
uniform float dry = 0.0;
uniform float winter = 0.0;
uniform float naturalist = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

vec3 grade(vec3 c) {
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	return mix(c, mix(c, vec3(l * 1.04, l, l * 0.8), 0.32) * 0.86, naturalist);
}

void fragment() {
	vec3 c = COLOR.rgb;
	float green = clamp((c.g - max(c.r, c.b)) * 7.0, 0.0, 1.0);
	float watery = clamp((c.b - c.g) * 8.0, 0.0, 1.0);
	c = mix(c, c * vec3(0.92, 1.10, 0.80) + vec3(0.04, 0.06, 0.0), spring * green * 0.7);
	c = mix(c, grade(vec3(0.68, 0.64, 0.36)), dry * green * 0.35);
	c = mix(c, grade(vec3(0.64, 0.56, 0.28)), autumn * green * 0.40);
	c = mix(c, grade(vec3(0.52, 0.52, 0.42)), winter * green * 0.55);
	// Snow: flat, above the sand, never on open water; patchy as it comes and goes.
	float flat_ground = smoothstep(0.72, 0.9, wnrm.y);
	float above = smoothstep(0.9, 1.7, wpos.y);
	float n = vnoise(wpos.xz * 0.11) * 0.65 + vnoise(wpos.xz * 0.55) * 0.35;
	float cover = clamp((snow * 1.3 - (1.0 - n)) * 5.0, 0.0, 1.0) * flat_ground * above * (1.0 - watery);
	vec3 snow_col = mix(vec3(0.94, 0.96, 1.0), vec3(0.84, 0.85, 0.86), naturalist);
	c = mix(c, snow_col, cover);
	ALBEDO = to_linear(c);
	ROUGHNESS = 0.95 - cover * 0.25;
}
