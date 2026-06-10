shader_type canvas_item;
render_mode unshaded, blend_add;

uniform float charge = 0.0;
uniform float t = 0.0;
uniform vec4 base_col: source_color = vec4(1.0, 0.85, 0.5, 1.0);
uniform float pulse_depth = 0.08;
uniform float pulse_rate = 1.0;

void fragment() {
	vec2 d = UV - 0.5;
	float r = length(d) * 2.0;
	float pulse = 1.0 + pulse_depth * sin(t * (4.0 + charge * 14.0) * pulse_rate);
	float core_r = (0.18 + 0.55 * charge) * pulse;
	float glow = exp(-pow(r / max(core_r, 0.02), 2.0) * 3.0);
	float ring = exp(-abs(r - core_r) * 18.0) * 0.6;
	vec3 c = base_col.rgb * (glow * (1.2 + charge * 3.5) + ring);
	COLOR = vec4(c, clamp(glow * 2.0 + ring, 0.0, 1.0));
}
