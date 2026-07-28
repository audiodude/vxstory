shader_type spatial;
// Roads + sidewalks (flat MultiMesh boxes). INSTANCE_CUSTOM = (kind, ring_frac,
// seg_len_m, 0): kind 0 street, 1 boulevard, 2 sidewalk. Streets/boulevards get
// lane markings; everything paves in (dirt -> surface) as ring_frac passes the
// global ring_p (city growth front).

uniform float ring_p = 1.0;
uniform float night : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_local;
varying vec3 v_dims;
varying vec4 v_custom;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	v_local = VERTEX;
	v_dims = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	v_custom = INSTANCE_CUSTOM;
}

void fragment() {
	float kind = v_custom.x;
	float pave = smoothstep(v_custom.y, v_custom.y + 0.04, ring_p);
	float u_m = v_local.x * v_dims.x;        // along the segment
	float w_m = v_local.z * v_dims.z;        // across (0 = centerline)

	vec3 dirt = vec3(0.2, 0.16, 0.12) * (0.85 + 0.3 * hash12(floor(vec2(u_m, w_m) / 3.0)));
	vec3 surface;
	if (kind > 1.5) {
		surface = vec3(0.28, 0.28, 0.29) * (0.9 + 0.2 * hash12(floor(vec2(u_m, w_m) / 2.0)));
	} else {
		surface = vec3(0.11, 0.11, 0.12) * (0.9 + 0.2 * hash12(floor(vec2(u_m, w_m) / 4.0)));
		float half_w = v_dims.z * 0.5;
		if (kind > 0.5) {
			// Boulevard: darker median band + a dashed line per carriageway.
			if (abs(w_m) < 1.3) surface = vec3(0.1, 0.12, 0.1);
			float lane = half_w * 0.5;
			float dash = step(fract(u_m / 7.0), 0.55);
			if (abs(abs(w_m) - lane) < 0.14 && dash > 0.5) surface = vec3(0.42, 0.42, 0.38);
			if (abs(abs(w_m) - (half_w - 0.25)) < 0.12) surface = vec3(0.38, 0.38, 0.35);
		} else {
			// Street: single dashed centerline.
			float dash = step(fract(u_m / 6.0), 0.5);
			if (abs(w_m) < 0.13 && dash > 0.5) surface = vec3(0.42, 0.4, 0.32);
		}
	}
	ALBEDO = mix(dirt, surface, pave);
	ROUGHNESS = mix(0.95, 0.9, pave);
	SPECULAR = 0.02;   // no grazing sky-mirror on asphalt/dirt
}
