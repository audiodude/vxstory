shader_type canvas_item;
render_mode unshaded;

uniform sampler2D prev_tex: filter_linear, repeat_disable;
uniform float dt = 0.016;
uniform float dissipation = 0.985;
uniform float flow_speed = 1.0;
uniform float noise_scale = 3.0;
uniform float noise_strength = 1.0;
uniform float time_drift = 0.15;
uniform float t = 0.0;
uniform int vortex_count = 0;
uniform vec4 vortices[8];      // xy: uv pos, z: signed strength, w: radius (uv)
uniform int splat_count = 0;
uniform vec4 splat_pos_r[16];  // xy: uv pos, z: radius (uv), w: strength
uniform vec4 splat_color[16];
uniform int impulse_count = 0;
uniform vec4 impulses[8];      // xy: uv pos, z: power, w: age (sec)
uniform vec2 aspect = vec2(1.777778, 1.0);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int k = 0; k < 4; k++) {
		v += amp * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		amp *= 0.5;
	}
	return v;
}
vec2 curl(vec2 p) {
	float e = 0.02;
	float dy = fbm(p + vec2(0.0, e)) - fbm(p - vec2(0.0, e));
	float dx = fbm(p + vec2(e, 0.0)) - fbm(p - vec2(e, 0.0));
	return vec2(dy, -dx) / (2.0 * e);
}
void fragment() {
	vec2 uv = UV;
	vec2 pa = uv * aspect;
	vec2 vel = curl(pa * noise_scale + vec2(t * time_drift, -t * time_drift * 0.7)) * noise_strength * 0.05;
	for (int k = 0; k < vortex_count; k++) {
		vec2 d = pa - vortices[k].xy * aspect;
		float fall = exp(-dot(d, d) / (vortices[k].w * vortices[k].w));
		vel += vec2(-d.y, d.x) * vortices[k].z * fall;
	}
	for (int k = 0; k < impulse_count; k++) {
		vec2 d = pa - impulses[k].xy * aspect;
		float r = length(d) + 1e-4;
		float decay = exp(-impulses[k].w * 2.5) * exp(-r * 4.0);
		vel += (d / r) * impulses[k].z * decay;
	}
	vec2 src = uv - vel * dt * flow_speed / aspect;
	vec4 c = texture(prev_tex, clamp(src, vec2(0.001), vec2(0.999))) * dissipation;
	for (int k = 0; k < splat_count; k++) {
		vec2 d = pa - splat_pos_r[k].xy * aspect;
		float g = exp(-dot(d, d) / (splat_pos_r[k].z * splat_pos_r[k].z));
		c.rgb += splat_color[k].rgb * g * splat_pos_r[k].w;
	}
	c.rgb = min(c.rgb, vec3(1.0));
	COLOR = vec4(c.rgb, 1.0);
}
