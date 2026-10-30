shader_type spatial;
render_mode specular_schlick_ggx, cull_back;

uniform vec4 shallow_color : source_color = vec4(0.36, 0.72, 0.78, 1.0);
uniform vec4 deep_color : source_color = vec4(0.18, 0.45, 0.58, 1.0);
uniform vec4 glint_color : source_color = vec4(1.0, 0.95, 0.82, 1.0);
uniform float ripple_speed : hint_range(0.05, 2.0) = 0.42;
uniform float glint_strength : hint_range(0.0, 2.5) = 0.65;

void fragment() {
	vec2 wuv = UV * vec2(18.0, 8.0);
	float t = TIME * ripple_speed;
	float w1 = sin(wuv.x * 2.4 + t * 1.6 + sin(wuv.y * 1.8 - t)) * 0.5 + 0.5;
	float w2 = cos(wuv.x * 3.7 - t * 1.2 + wuv.y * 2.9) * 0.5 + 0.5;
	float wave_mix = clamp((w1 * 0.55 + w2 * 0.45), 0.0, 1.0);

	vec3 base_col = mix(deep_color.rgb, shallow_color.rgb, smoothstep(0.15, 0.88, UV.y) * 0.65 + wave_mix * 0.35);
	float sparkle = smoothstep(0.86, 0.99, w1 * w2);
	ALBEDO = base_col + glint_color.rgb * sparkle * glint_strength * 0.45;
	EMISSION = glint_color.rgb * sparkle * glint_strength * 0.32;
	ROUGHNESS = mix(0.12, 0.26, wave_mix);
	METALLIC = 0.08;
	NORMAL_MAP = normalize(vec3((w1 - 0.5) * 0.14, (w2 - 0.5) * 0.14, 1.0)) * 0.5 + 0.5;
}
