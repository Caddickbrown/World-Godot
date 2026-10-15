shader_type spatial;
// The rainbow (WeatherView): a half ring, red outside, violet in, standing
// where rain has just cleared. UV.x runs along the arc, UV.y across the ring
// (0 inner, 1 outer). Faint, additive, fading into the ground at its feet.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float strength = 0.0;
uniform float gain = 0.85;
uniform float width = 0.15;   // of the ring's band that holds colour (outer part)

vec3 spectrum(float t) {
	// t: 0 violet .. 1 red
	vec3 c = vec3(0.0);
	c += vec3(0.45, 0.20, 0.75) * smoothstep(0.25, 0.0, abs(t - 0.05));
	c += vec3(0.20, 0.35, 0.95) * smoothstep(0.22, 0.0, abs(t - 0.22));
	c += vec3(0.20, 0.80, 0.40) * smoothstep(0.22, 0.0, abs(t - 0.45));
	c += vec3(0.98, 0.90, 0.25) * smoothstep(0.20, 0.0, abs(t - 0.63));
	c += vec3(1.00, 0.55, 0.15) * smoothstep(0.18, 0.0, abs(t - 0.78));
	c += vec3(0.95, 0.20, 0.18) * smoothstep(0.20, 0.0, abs(t - 0.95));
	return c;
}

void fragment() {
	float band0 = 1.0 - width / 0.2;   // the colour sits in the outer part of the ring
	float t = (UV.y - band0) / (1.0 - band0);
	float inside = smoothstep(0.0, 0.12, t) * smoothstep(1.0, 0.86, t);
	vec3 c = spectrum(clamp(t, 0.0, 1.0));
	// A faint brighter sky inside the bow, as real ones have.
	float glow = smoothstep(band0, 0.0, UV.y) * 0.06 * step(UV.y, band0);
	float ends = smoothstep(0.0, 0.18, UV.x) * smoothstep(1.0, 0.82, UV.x);
	ALBEDO = (c * inside + vec3(glow)) * strength * gain * ends;
}
