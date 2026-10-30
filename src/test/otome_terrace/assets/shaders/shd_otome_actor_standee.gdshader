shader_type spatial;
render_mode depth_draw_opaque, cull_disabled, specular_disabled;

uniform sampler2D standee_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool flip_h = false;
uniform float alpha_cut_threshold : hint_range(0.05, 0.9) = 0.38;
uniform float self_illum_ratio : hint_range(0.0, 1.0) = 0.62;
uniform float scene_light_influence : hint_range(0.0, 1.0) = 0.34;

void fragment() {
	vec2 uv = vec2(flip_h ? (1.0 - UV.x) : UV.x, UV.y);
	vec4 tex = texture(standee_tex, uv);
	if (tex.a < alpha_cut_threshold) {
		discard;
	}
	ALBEDO = tex.rgb * scene_light_influence;
	EMISSION = tex.rgb * self_illum_ratio;
	ROUGHNESS = 1.0;
}

void light() {
	float wrapped = clamp(dot(NORMAL, LIGHT) * 0.35 + 0.65, 0.48, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * wrapped / PI;
}
