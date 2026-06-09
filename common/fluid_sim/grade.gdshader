shader_type canvas_item;
render_mode unshaded;

uniform float saturation = 1.2;
uniform float contrast = 1.1;

void fragment() {
	vec3 c = texture(TEXTURE, UV).rgb;
	// multiplicative contrast preserves black background
	c = pow(max(c, vec3(0.0)), vec3(1.0 / max(contrast, 0.01)));
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	COLOR = vec4(max(c, vec3(0.0)), 1.0);
}
