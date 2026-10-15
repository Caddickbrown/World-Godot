shader_type spatial;
// Mockup water: depth comes in through COLOR.r (metres below the surface,
// baked from the heightfield), so it needs no depth texture. Shallows turn
// turquoise over sand, deep water goes ink blue, and a foam line follows the
// shore.
render_mode cull_disabled, specular_schlick_ggx;

uniform vec3 shallow_color : source_color = vec3(0.36, 0.78, 0.76);
uniform vec3 mid_color : source_color = vec3(0.12, 0.47, 0.62);
uniform vec3 deep_color : source_color = vec3(0.05, 0.18, 0.36);
uniform vec3 foam_color : source_color = vec3(0.96, 0.98, 0.95);
uniform float depth_mid = 1.2;
uniform float depth_deep = 6.0;
uniform float foam_width = 0.35;

varying float depth;
varying vec3 wpos;

void vertex() {
	depth = COLOR.r * 10.0;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(wpos.x * 0.35 + TIME * 0.9) * cos(wpos.z * 0.31 + TIME * 0.7);
	VERTEX.y += w * 0.04 * clamp(depth, 0.0, 1.0);
}

void fragment() {
	float d = max(depth, 0.0);
	vec3 col = mix(shallow_color, mid_color, smoothstep(0.0, depth_mid, d));
	col = mix(col, deep_color, smoothstep(depth_mid, depth_deep, d));
	// Shore foam: a broken band that breathes with the waves.
	float wobble = sin(wpos.x * 2.1 + TIME * 1.3) * sin(wpos.z * 1.7 - TIME) * 0.12;
	float foam = 1.0 - smoothstep(0.0, foam_width + wobble, d);
	col = mix(col, foam_color, foam * 0.85);
	// Ripples in the normal.
	vec2 p = wpos.xz;
	float nx = sin(p.x * 1.3 + TIME * 1.1) * 0.5 + sin(p.x * 3.1 + p.y * 1.7 + TIME * 1.9) * 0.25;
	float nz = cos(p.y * 1.2 - TIME * 0.9) * 0.5 + cos(p.y * 2.7 - p.x * 1.3 + TIME * 1.5) * 0.25;
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(normalize(vec3(nx * 0.08, 1.0, nz * 0.08)), 0.0)).xyz, 0.8));
	ALBEDO = col;
	ROUGHNESS = 0.2 + foam * 0.7;   // 0.08 gave a blown-out sun glare under the bloom
	METALLIC = 0.0;
	SPECULAR = 0.4;
	ALPHA = mix(0.78, 0.97, smoothstep(0.0, depth_deep, d)) + foam * 0.2;
}
