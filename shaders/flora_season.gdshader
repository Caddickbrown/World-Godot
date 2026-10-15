shader_type spatial;
// Trees, bushes and grass (MultiMesh, instance colour in COLOR, sRGB), with
// the season applied here (SeasonLook.blend feeds the uniforms), so the year
// turns without rebuilding a chunk.
//   kind 0: broadleaf crown  - spring fresh, autumn orange/red/gold per tree,
//                              winter bare (a thin twiggy crown you see through)
//   kind 1: pine             - evergreen; snow on its shoulders
//   kind 2: bush / grass     - greens follow the ground; snow on top, grass sinks under it
//   kind 3: trunk / stump    - only catches snow
// Anything right in front of the camera dithers away (the walk view never
// gets swallowed by a wood), as the old StandardMaterial distance fade did.

uniform int kind = 0;
uniform float snow = 0.0;
uniform float autumn = 0.0;
uniform float bare = 0.0;
uniform float spring = 0.0;
uniform float dry = 0.0;
uniform float winter = 0.0;
uniform float naturalist = 0.0;
uniform float fade_min = 1.5;
uniform float fade_max = 5.0;
uniform float sink_in_snow = 0.0;   // grass: shrink under lying snow

varying vec3 wnrm;
varying vec3 lpos;
varying float pick;     // per-instance random, from where it stands

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

vec3 grade(vec3 c) {
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	return mix(c, mix(c, vec3(l * 1.04, l, l * 0.8), 0.32) * 0.86, naturalist);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	pick = hash3(floor(origin * 3.1));
	lpos = VERTEX;
	if (kind == 0) {
		VERTEX *= 1.0 - 0.18 * bare;
	}
	if (kind == 2 && sink_in_snow > 0.0) {
		VERTEX.y *= 1.0 - 0.85 * smoothstep(0.3, 0.9, snow);
	}
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float dist = length(VERTEX);
	float fade = smoothstep(fade_min, fade_max, dist);
	float bayer = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	if (fade < 0.999 && fade <= bayer) {
		discard;
	}
	vec3 c = COLOR.rgb;
	float green = clamp((c.g - max(c.r, c.b)) * 6.0, 0.0, 1.0);
	if (kind == 0 || kind == 2) {
		c = mix(c, c * vec3(0.92, 1.12, 0.78) + vec3(0.05, 0.07, 0.0), spring * green * 0.75);
		c = mix(c, grade(vec3(0.66, 0.64, 0.34)), dry * green * (kind == 2 ? 0.35 : 0.15));
	}
	if (kind == 0) {
		// Each tree turns in its own time and to its own colour.
		float when = smoothstep(pick * 0.45, pick * 0.45 + 0.55, autumn);
		vec3 turn = pick < 0.3 ? vec3(0.90, 0.52, 0.16) : (pick < 0.55 ? vec3(0.80, 0.30, 0.16) : (pick < 0.85 ? vec3(0.93, 0.74, 0.22) : vec3(0.62, 0.42, 0.20)));
		c = mix(c, grade(turn), when * green);
		// Bare: twigs, and gaps to see through.
		float twig = smoothstep(0.05, 0.6, bare);
		c = mix(c, grade(vec3(0.44, 0.37, 0.31)), twig);
		float holes = vnoise3(lpos * 4.5 + vec3(pick * 7.0));
		if (holes < bare * 0.62) {
			discard;
		}
	}
	if (kind == 2) {
		c = mix(c, grade(vec3(0.62, 0.56, 0.30)), autumn * green * 0.35);
		c = mix(c, grade(vec3(0.54, 0.52, 0.40)), winter * green * 0.5);
	}
	// Snow on what faces the sky.
	float up = smoothstep(0.25, 0.75, wnrm.y);
	float hold = kind == 1 ? 0.85 : (kind == 0 ? 0.55 : 0.9);
	float s = clamp(snow * 1.4 - 0.2, 0.0, 1.0) * up * hold * (0.75 + 0.25 * vnoise3(lpos * 3.0));
	c = mix(c, mix(vec3(0.93, 0.95, 1.0), vec3(0.84, 0.85, 0.86), naturalist), s);
	ALBEDO = to_linear(c);
	ROUGHNESS = 0.9;
}
