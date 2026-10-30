shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec4 ring_color : source_color = vec4(0.96, 0.78, 0.68, 0.82);
uniform float highlight_boost : hint_range(0.0, 1.5) = 0.0;

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float dist = length(centered);
	float pulse = 0.5 + 0.5 * sin(TIME * 2.6);
	float outer_ring = smoothstep(0.96, 0.84, dist) * smoothstep(0.66, 0.78, dist);
	float inner_glow = smoothstep(0.76, 0.10, dist) * (0.14 + highlight_boost * 0.18);
	float petal_dash = 0.78 + 0.22 * sin(atan(centered.y, centered.x) * 6.0 + TIME * 1.4);
	float alpha = (outer_ring * petal_dash * (0.68 + 0.25 * pulse + highlight_boost * 0.35) + inner_glow) * ring_color.a;
	ALBEDO = ring_color.rgb * (1.0 + highlight_boost * 0.25);
	ALPHA = clamp(alpha, 0.0, 0.95);
}
