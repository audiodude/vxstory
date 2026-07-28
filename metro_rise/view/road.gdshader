shader_type spatial;
// Roads, sidewalks and intersection pads (flat MultiMesh boxes).
// INSTANCE_CUSTOM = (kind, ring_frac, box_len_m, 0): kind 0 street,
// 1 boulevard, 2 sidewalk, 3 intersection pad. Streets/boulevards get lane
// markings; everything paves in (dirt -> surface) as ring_frac passes the
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
	float marking = 0.0;
	if (kind > 2.5) {
		// Intersection pad: plain surface, no markings.
		surface = vec3(0.105, 0.105, 0.115) * (0.9 + 0.2 * hash12(floor(vec2(u_m, w_m) / 4.0)));
	} else if (kind > 1.5) {
		surface = vec3(0.28, 0.28, 0.29) * (0.9 + 0.2 * hash12(floor(vec2(u_m, w_m) / 2.0)));
	} else {
		surface = vec3(0.11, 0.11, 0.12) * (0.9 + 0.2 * hash12(floor(vec2(u_m, w_m) / 4.0)));
		float half_w = v_dims.z * 0.5;
		// Anti-aliased, distance-faded markings: hard step() lines shimmer once
		// they go subpixel, so edges use fwidth and coverage fades them out.
		float fw_u = fwidth(u_m) + 1e-4;
		float fw_w = fwidth(w_m) + 1e-4;
		float cover = clamp(0.28 / fw_w, 0.0, 1.0) * clamp(3.0 / fw_u, 0.0, 1.0);
		// Markings stop a few metres short of the box ends (intersection pads).
		float ends = 1.0 - smoothstep(v_custom.z * 0.5 - 5.0, v_custom.z * 0.5 - 1.5, abs(u_m));
		if (kind > 0.5) {
			if (abs(w_m) < 1.3) surface = vec3(0.1, 0.12, 0.1);   // median band
			float lane = half_w * 0.5;
			float ph = fract(u_m / 7.0);
			float dash = smoothstep(0.0, fw_u / 7.0, ph) * (1.0 - smoothstep(0.55, 0.55 + fw_u / 7.0, ph));
			float lane_line = 1.0 - smoothstep(0.14 - fw_w, 0.14 + fw_w, abs(abs(w_m) - lane));
			float edge_line = 1.0 - smoothstep(0.12 - fw_w, 0.12 + fw_w, abs(abs(w_m) - (half_w - 0.25)));
			marking = max(lane_line * dash, edge_line * 0.8) * cover * ends;
		} else {
			float ph = fract(u_m / 6.0);
			float dash = smoothstep(0.0, fw_u / 6.0, ph) * (1.0 - smoothstep(0.5, 0.5 + fw_u / 6.0, ph));
			float center = 1.0 - smoothstep(0.13 - fw_w, 0.13 + fw_w, abs(w_m));
			marking = center * dash * cover * ends;
		}
		surface = mix(surface, vec3(0.42, 0.41, 0.35), marking);
	}
	ALBEDO = mix(dirt, surface, pave);
	ROUGHNESS = mix(0.95, 0.9, pave);
	SPECULAR = 0.02;   // no grazing sky-mirror on asphalt/dirt
	// Markings keep a faint self-light after dusk so the grid stays legible.
	EMISSION = vec3(0.42, 0.41, 0.35) * (marking * night * pave * 0.2);
}
