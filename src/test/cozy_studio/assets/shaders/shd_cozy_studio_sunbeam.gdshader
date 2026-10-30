shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Volumetric warm afternoon sunbeam sheet streaming from the French windows.
uniform vec4 beam_color : source_color = vec4(1.0, 0.91, 0.66, 0.22);
uniform float edge_softness : hint_range(0.05, 0.5) = 0.26;

void fragment() {
	float fade_len = pow(clamp(1.0 - UV.y, 0.0, 1.0), 1.25) * smoothstep(0.0, 0.12, UV.y);
	float fade_side = smoothstep(0.0, edge_softness, UV.x) * smoothstep(1.0, 1.0 - edge_softness, UV.x);
	float fresnel = max(0.38, pow(abs(dot(NORMAL, VIEW)), 0.55));
	float alpha = beam_color.a * fade_len * fade_side * fresnel;
	ALBEDO = beam_color.rgb * alpha;
	ALPHA = alpha;
}
