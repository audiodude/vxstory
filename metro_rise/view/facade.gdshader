shader_type spatial;
// Era-styled procedural facades for MultiMesh unit-box building instances.
// Per-instance INSTANCE_CUSTOM = (style_id, window_cell_w_m, lit_seed, progress);
// COLOR.rgb = albedo tint, COLOR.a = accent hue (0..1). Buildings are unit boxes
// scaled to (w, visible_h, d) — the VIEW scales Y to progress*full_h while a
// build is rising, so the top face self-caps as a slab (no discard, correct
// shadows). Window grids are computed in face-space meters (the Y scale IS the
// visible meters), so windows stay square and rows stay floor-aligned as the
// building grows. progress < 1 adds a work-light band at the build line.

uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform float lit_fraction : hint_range(0.0, 1.0) = 0.6;
uniform float neon : hint_range(0.0, 1.0) = 0.4;
uniform float floor_h = 3.2;
uniform float hue_shift = 0.0;            // degrees, applied to accent hues
uniform vec3 interior_warm : source_color = vec3(1.0, 0.82, 0.55);
uniform vec3 interior_cool : source_color = vec3(0.75, 0.85, 1.0);
uniform vec3 worklight : source_color = vec3(1.0, 0.65, 0.3);

varying vec3 v_local;
varying vec3 v_nrm;
varying vec3 v_dims;
varying vec4 v_custom;
varying vec4 v_tint;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void vertex() {
	v_local = VERTEX;
	v_nrm = NORMAL;
	v_dims = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	v_custom = INSTANCE_CUSTOM;
	v_tint = COLOR;
}

void fragment() {
	float style = v_custom.x;        // 0 brick, 1 concrete, 2 glass
	float win_w = max(v_custom.y, 0.6);
	float lit_seed = v_custom.z;
	float progress = v_custom.w;

	float y_m = (v_local.y + 0.5) * v_dims.y;   // meters above this box's base

	vec3 an = abs(v_nrm);
	vec3 albedo = v_tint.rgb;
	float rough = 0.9;
	float metal = 0.0;
	vec3 emiss = vec3(0.0);

	if (an.y > 0.9) {
		// Roof: flat, darker, no windows. Under construction it reads as a slab.
		albedo *= (progress < 0.999) ? 0.4 : 0.55;
		rough = 0.95;
	} else {
		// Face-space meters: u along the face, v = height above base.
		float u_m = (an.x > an.z) ? (v_local.z * v_dims.z) : (v_local.x * v_dims.x);
		float face_id = (an.x > an.z) ? (1.0 + sign(v_nrm.x)) : (7.0 + sign(v_nrm.z));

		float row = floor(y_m / floor_h);
		float storefront = (style < 1.5 && row < 0.5) ? 1.0 : 0.0;
		float cell_w = win_w * mix(1.0, 1.6, storefront);
		float col = floor(u_m / cell_w);
		vec2 cuv = vec2(fract(u_m / cell_w), fract(y_m / floor_h));
		vec2 cell_id = vec2(col + face_id * 137.0, row);

		// Window mask per style.
		float wr_u; float wr_v;              // window fraction of cell, u and v
		if (style < 0.5) { wr_u = 0.5; wr_v = 0.55; }
		else if (style < 1.5) { wr_u = 0.92; wr_v = 0.55; }
		else { wr_u = 0.9; wr_v = 0.86; }
		wr_u = mix(wr_u, 0.94, storefront);
		wr_v = mix(wr_v, 0.7, storefront);
		float in_u = step(abs(cuv.x - 0.5), wr_u * 0.5);
		float in_v = step(abs(cuv.y - 0.55), wr_v * 0.5);
		float window = in_u * in_v;
		if (style > 0.5 && style < 1.5) {
			// Concrete ribbons: full-width bands with a pier every 3rd cell.
			float pier = step(0.85, fract(col / 3.0 + 0.28));
			window = in_v * (1.0 - pier * step(abs(cuv.x - 0.5), 0.12));
		}

		// Base materials per style.
		if (style < 0.5) {
			rough = 0.92;
			// Brick banding: darker mortar row every 4th floor + fine course lines.
			float band = step(0.72, fract(row / 4.0));
			albedo *= mix(1.0, 0.78, band);
			albedo *= mix(0.94, 1.06, hash12(cell_id * 3.7));
		} else if (style < 1.5) {
			rough = 0.75;
			albedo *= mix(0.96, 1.04, hash12(vec2(row, face_id)));
		} else {
			rough = 0.35;
			metal = 0.05;
		}

		// Grime gradient near street level.
		albedo *= mix(0.8, 1.0, clamp(y_m / 14.0, 0.0, 1.0));

		if (window > 0.5) {
			float h_lit = hash12(cell_id + vec2(lit_seed * 97.0, lit_seed * 13.0));
			float style_bias = (style > 1.5) ? 1.15 : 1.0;
			float lit = step(h_lit, lit_fraction * night * style_bias * mix(1.0, 1.5, storefront));
			// Dark glazing by day; interior light at night.
			vec3 glass_day = vec3(0.16, 0.19, 0.24) * mix(0.8, 1.2, hash12(cell_id * 1.3));
			albedo = mix(albedo, glass_day, (style > 1.5) ? 0.85 : 1.0);
			rough = (style > 1.5) ? 0.12 : 0.25;
			metal = (style > 1.5) ? 0.35 : 0.15;
			float temp = hash12(cell_id * 7.9 + 0.31);
			vec3 interior = mix(interior_warm, interior_cool, step(0.62, temp));
			emiss += interior * lit * (1.1 + 0.8 * hash12(cell_id * 5.1)) * night;
		}

		// Storefront neon strip along the top of the ground floor.
		if (storefront > 0.5 && cuv.y > 0.86 && cuv.y < 0.97) {
			float acc_h = fract(v_tint.a + hue_shift / 360.0 + hash12(vec2(face_id, lit_seed)) * 0.15);
			vec3 acc = hsv2rgb(vec3(acc_h, 0.85, 1.0));
			emiss += acc * neon * night * 2.2;
		}

		// Work-light band at the build line while under construction.
		if (progress < 0.999) {
			float in_band = step(v_dims.y - floor_h, y_m);
			albedo = mix(albedo, vec3(0.45, 0.44, 0.42), in_band * 0.7);
			emiss += worklight * in_band * (0.5 + 0.5 * hash12(vec2(row, lit_seed)))
					* (0.25 + 0.75 * night);
		}
	}

	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emiss;
}
