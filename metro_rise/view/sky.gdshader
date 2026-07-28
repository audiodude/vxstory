shader_type sky;
// Gradient sky driven by sim/sun.gd: top/horizon colors, sun disc + halo, and
// a deterministic hash star field that fades in past dusk (no TIME — stars are
// stable frame to frame).

uniform vec3 top_color = vec3(0.12, 0.3, 0.66);
uniform vec3 horizon_color = vec3(0.44, 0.58, 0.74);
uniform vec3 ground_color = vec3(0.06, 0.055, 0.05);
uniform vec3 sun_color = vec3(1.0, 0.95, 0.85);
uniform vec3 to_sun = vec3(0.0, 1.0, 0.0);   // unit vector toward the sun
uniform float sun_energy = 1.5;
uniform float star_alpha = 0.0;
uniform float star_density = 0.5;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

void sky() {
	float up = EYEDIR.y;
	vec3 col;
	if (up < 0.0) {
		col = mix(horizon_color, ground_color, clamp(-up * 6.0, 0.0, 1.0));
	} else {
		col = mix(horizon_color, top_color, pow(clamp(up, 0.0, 1.0), 0.42));
	}

	// Sun disc + soft halo.
	float d = distance(EYEDIR, to_sun);
	float disc = 1.0 - smoothstep(0.012, 0.026, d);
	float halo = exp(-d * d * 60.0) * 0.35;
	col += sun_color * (disc * 3.0 + halo) * clamp(sun_energy, 0.0, 2.5) * step(-0.06, to_sun.y);

	// Stars: quantized-direction hash, upper hemisphere, denser toward zenith.
	if (star_alpha > 0.001 && up > 0.02) {
		vec3 cell = floor(EYEDIR * 200.0);
		float h = hash13(cell);
		float thresh = 1.0 - 0.007 * star_density;
		if (h > thresh) {
			float mag = fract(h * 913.71);
			col += vec3(0.9, 0.93, 1.0) * star_alpha * mag * clamp(up * 3.0, 0.0, 1.0) * 1.1;
		}
	}
	COLOR = col;
}
