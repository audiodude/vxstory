shader_type spatial;
// Low-poly canopy cones. INSTANCE_CUSTOM = (ring_frac, sway_phase, hue_var, 0).
// Trees grow out of the ground as the city expansion front (ring_p) passes them.

uniform float ring_p = 1.0;
uniform float t = 0.0;

varying vec4 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	float growth = smoothstep(v_custom.x, v_custom.x + 0.06, ring_p);
	VERTEX *= growth;
	float h01 = clamp(VERTEX.y / 6.0 + 0.5, 0.0, 1.0);
	VERTEX.x += sin(t * 1.1 + v_custom.y * 6.283) * 0.25 * h01 * growth;
	VERTEX.z += cos(t * 0.9 + v_custom.y * 6.283) * 0.2 * h01 * growth;
}

void fragment() {
	vec3 a = mix(vec3(0.12, 0.22, 0.1), vec3(0.2, 0.26, 0.12), v_custom.z);
	ALBEDO = a;
	ROUGHNESS = 1.0;
	SPECULAR = 0.05;
}
