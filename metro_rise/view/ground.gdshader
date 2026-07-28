shader_type spatial;
// Ground plane: world-space value noise, urban gray near the core blending to
// muted field green at the fringe.

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = vnoise(v_world.xz * 0.02) * 0.6 + vnoise(v_world.xz * 0.13) * 0.4;
	float ur = length(v_world.xz) / 1100.0;
	vec3 urban = vec3(0.13, 0.125, 0.12);
	vec3 field = vec3(0.1, 0.14, 0.075);
	vec3 c = mix(urban, field, smoothstep(0.35, 0.75, ur));
	ALBEDO = c * (0.85 + 0.3 * n);
	ROUGHNESS = 1.0;
	SPECULAR = 0.02;
}
