shader_type spatial;
// Cars: unit boxes scaled (4.4, 1.5, 1.9), +X forward. COLOR.rgb = body tint,
// INSTANCE_CUSTOM = (stopped, 0, 0, 0). Headlights/taillights are emissive end
// caps gated by the global `night`; brake lights also fire when stopped.

uniform float night : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_local;
varying vec3 v_nrm;
varying vec4 v_tint;
varying vec4 v_custom;

void vertex() {
	v_local = VERTEX;
	v_nrm = NORMAL;
	v_tint = COLOR;
	v_custom = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 albedo = v_tint.rgb;
	// Glass canopy band on the upper half.
	if (v_local.y > 0.12 && abs(v_nrm.y) < 0.5) {
		albedo *= 0.35;
	}
	ALBEDO = albedo;
	ROUGHNESS = 0.4;
	METALLIC = 0.3;
	SPECULAR = 0.3;

	vec3 emiss = vec3(0.0);
	if (v_nrm.x > 0.9) {
		emiss = vec3(1.0, 0.95, 0.8) * night * 4.0;
	} else if (v_nrm.x < -0.9) {
		float brake = clamp(v_custom.x, 0.0, 1.0);
		emiss = vec3(1.0, 0.08, 0.05) * (night * 1.6 + brake * (0.8 + night * 1.2));
	}
	EMISSION = emiss;
}
