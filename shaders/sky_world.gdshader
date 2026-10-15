shader_type sky;
// The sky (SkyLook drives every uniform): a gradient that follows the time of
// day and the weather, the sun, clouds drifting by day (thicker when
// overcast), and at night stars, a Milky Way band, the moon and the odd
// shooting star. The radiance pass (lighting the world) gets only the
// gradient and sun, so stars never glitter in the ambient light.

uniform vec3 top_color : source_color = vec3(0.32, 0.55, 0.85);
uniform vec3 horizon_color : source_color = vec3(0.78, 0.84, 0.88);
uniform vec3 ground_horizon : source_color = vec3(0.70, 0.75, 0.80);
uniform vec3 ground_bottom : source_color = vec3(0.12, 0.18, 0.26);
uniform vec3 sun_dir = vec3(0.0, 0.5, -0.8);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_visible = 1.0;
uniform vec3 moon_dir = vec3(0.0, 0.5, 0.8);
uniform float moon_size = 0.035;          // radians
uniform float night = 0.0;                // 0 day .. 1 deep night
uniform float overcast = 0.0;             // 0 clear .. 1 storm
uniform float star_gain = 1.0;            // storybook brighter, field notes subdued
uniform float milky_gain = 1.0;
uniform vec3 cloud_lit : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shade : source_color = vec3(0.62, 0.66, 0.74);
uniform vec2 cloud_offset = vec2(0.0);
uniform float cloud_cover = 0.35;         // fraction of the sky clouded
uniform float twinkle_t = 0.0;
uniform vec3 meteor_a = vec3(0.0, 1.0, 0.0);
uniform vec3 meteor_b = vec3(0.0, 1.0, 0.0);
uniform float meteor_t = -1.0;            // 0..1 while one falls, < 0 none
uniform float flash = 0.0;                // lightning

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x),
		mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), u.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), u.x), u.y);
	float b = mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), u.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), u.x), u.y);
	return mix(a, b, u.z);
}

// One layer of stars: a star in some cells of a grid on the sky.
float star_layer(vec3 d, float scale, float keep, float radius) {
	vec3 p = d * scale;
	vec3 i = floor(p);
	vec3 f = fract(p);
	float h = hash3(i);
	if (h < 1.0 - keep) {
		return 0.0;
	}
	vec3 c = vec3(hash3(i + 1.3), hash3(i + 2.7), hash3(i + 5.1)) * 0.6 + 0.2;
	float r = length(f - c);
	float tw = 0.75 + 0.25 * sin(twinkle_t * (2.0 + h * 5.0) + h * 40.0);
	return smoothstep(radius, 0.0, r) * (0.35 + 0.65 * (h - (1.0 - keep)) / keep) * tw;
}

void sky() {
	vec3 d = EYEDIR;
	float up = d.y;
	vec3 col;
	if (up >= 0.0) {
		col = mix(horizon_color, top_color, pow(clamp(up, 0.0, 1.0), 0.55));
	} else {
		col = mix(ground_horizon, ground_bottom, clamp(-up * 4.0, 0.0, 1.0));
	}
	// Sun disc and glow (dimmed behind cloud).
	float sd = dot(d, normalize(sun_dir));
	float glow = pow(max(sd, 0.0), 24.0) * 0.35 + pow(max(sd, 0.0), 600.0) * 4.0;
	col += sun_color * glow * sun_visible * (1.0 - 0.85 * overcast);

	if (!AT_CUBEMAP_PASS && up > -0.02) {
		float h = clamp(up, 0.0, 1.0);
		float above = smoothstep(-0.02, 0.06, up);
		// Night: stars, a Milky Way band, the moon.
		if (night > 0.01) {
			vec3 band_n = normalize(vec3(0.42, 0.30, 0.86));
			float band = exp(-pow(dot(d, band_n) / 0.17, 2.0));
			float dust = vnoise3(d * 6.0) * 0.6 + vnoise3(d * 15.0) * 0.4;
			float lane = smoothstep(0.35, 0.65, vnoise3(d * 9.0 + 3.0));
			float milky = band * (0.35 + 0.65 * dust) * (1.0 - 0.45 * band * lane);
			float s = star_layer(d, 70.0, 0.06, 0.16) + star_layer(d, 140.0, 0.10, 0.22) * 0.6
				+ star_layer(d, 220.0, 0.25, 0.25) * 0.45 * band;
			float sky_clear = 1.0 - overcast;
			float vis = night * above * sky_clear * smoothstep(0.0, 0.25, h + 0.05);
			col += vec3(0.62, 0.68, 0.95) * milky * 0.16 * milky_gain * vis;
			col += vec3(0.95, 0.95, 1.0) * s * 1.25 * star_gain * vis;
			// Moon: a cream disc with soft maria, and a halo.
			vec3 md = normalize(moon_dir);
			float mdot = dot(d, md);
			float ang = acos(clamp(mdot, -1.0, 1.0));
			float disc = smoothstep(moon_size, moon_size * 0.85, ang);
			vec3 tang = normalize(cross(md, vec3(0.0, 1.0, 0.0)) + vec3(0.0001));
			vec3 bit = cross(md, tang);
			vec2 mp = vec2(dot(d - md, tang), dot(d - md, bit)) / moon_size;
			float maria = smoothstep(0.45, 0.75, vnoise(mp * 2.5 + 4.0)) * 0.22;
			vec3 moon_col = vec3(1.0, 0.97, 0.88) * (1.0 - maria);
			float mvis = night * above * (1.0 - 0.8 * overcast);
			col = mix(col, moon_col * 1.4, disc * mvis);
			col += vec3(0.55, 0.62, 0.85) * pow(max(mdot, 0.0), 300.0) * 0.6 * mvis;
			// A shooting star: a bright head with a fading tail.
			if (meteor_t >= 0.0) {
				vec3 head = normalize(mix(meteor_a, meteor_b, meteor_t));
				vec3 tail = normalize(mix(meteor_a, meteor_b, max(meteor_t - 0.35, 0.0)));
				vec3 seg = head - tail;
				float l2 = max(dot(seg, seg), 1e-6);
				float k = clamp(dot(d - tail, seg) / l2, 0.0, 1.0);
				float dist = length(d - (tail + seg * k));
				float life = sin(meteor_t * 3.14159);
				col += vec3(1.0, 0.96, 0.85) * smoothstep(0.0025, 0.0, dist) * k * k * life * 2.5 * vis;
			}
		}
		// Clouds: a drifting layer on a plane overhead; dense and grey when overcast.
		vec2 uv = d.xz / (h + 0.12) * 0.9 + cloud_offset;
		float n = fbm(uv * 1.3);
		float cover = clamp(cloud_cover, 0.0, 1.0);
		float c = smoothstep(1.0 - cover - 0.08, 1.0 - cover + 0.22, n) * above;
		c *= mix(0.55, 1.0, smoothstep(0.0, 0.35, h));     // thin out at the horizon
		float shade = smoothstep(0.35, 0.9, fbm(uv * 1.3 + vec2(0.08, 0.05)));
		vec3 cc = mix(cloud_lit, cloud_shade, shade * 0.8 + overcast * 0.2);
		col = mix(col, cc, c * mix(0.92, 0.98, overcast));
	}
	col += vec3(0.75, 0.80, 1.0) * flash;
	COLOR = col;
}
