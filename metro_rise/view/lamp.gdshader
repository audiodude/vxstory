shader_type spatial;
// Street lamps: thin unit cylinders scaled tall; the head (top of the pole)
// glows warm after dusk. INSTANCE_CUSTOM = (ring_frac, phase, 0, 0).

uniform float ring_p = 1.0;
uniform float night : hint_range(0.0, 1.0) = 0.0;

varying vec4 v_custom;
varying float v_h01;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	float growth = smoothstep(v_custom.x, v_custom.x + 0.05, ring_p);
	VERTEX *= growth;
	v_h01 = VERTEX.y + 0.5;
}

void fragment() {
	ALBEDO = vec3(0.08, 0.08, 0.09);
	ROUGHNESS = 0.6;
	METALLIC = 0.4;
	float head = smoothstep(0.9, 0.96, v_h01);
	EMISSION = vec3(1.0, 0.75, 0.45) * head * night * 3.5;
}
