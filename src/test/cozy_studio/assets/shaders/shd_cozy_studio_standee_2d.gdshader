shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// 2.5D Cozy Anime Standee Shader (with SpriteSheet UV Atlas Slicing):
// 1. Uniform cell UV slicing (`sheet_grid` + `frame_index`) drives both color & 3D shadow silhouette
//    with zero texture rebinding overhead.
// 2. Alpha scissor writes crisp animated silhouette into both main depth buffer & 3D shadow maps.
// 3. Up-biased view-space normal + paper backlight keeps warm anime colors when rotating camera.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 tint_color : source_color = vec4(1.0, 0.99, 0.97, 1.0);
uniform ivec2 sheet_grid = ivec2(1, 1);
uniform int frame_index = 0;
uniform float normal_up_bias : hint_range(0.0, 1.0) = 0.78;
uniform float self_warmth : hint_range(0.0, 0.6) = 0.18;
uniform float backlight_strength : hint_range(0.0, 0.8) = 0.28;
uniform float alpha_cutoff : hint_range(0.05, 0.95) = 0.42;
uniform bool flip_h = false;

void fragment() {
	vec2 local_uv = UV;
	if (flip_h) {
		local_uv.x = 1.0 - local_uv.x;
	}

	ivec2 safe_grid = max(ivec2(1, 1), sheet_grid);
	int total_frames = safe_grid.x * safe_grid.y;
	int safe_frame = clamp(frame_index, 0, total_frames - 1);
	int col = safe_frame % safe_grid.x;
	int row = safe_frame / safe_grid.x;

	vec2 inner_uv = clamp(local_uv, vec2(0.002), vec2(0.998));
	vec2 atlas_uv = (vec2(float(col), float(row)) + inner_uv) / vec2(safe_grid);

	vec4 tex = texture(albedo_texture, atlas_uv) * tint_color;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;

	ALBEDO = tex.rgb;
	// Signature roughness (> 0.96) lets the 3D anime ink-outline pass skip 2D standee silhouettes
	ROUGHNESS = 0.99;
	METALLIC = 0.0;
	SPECULAR = 0.04;

	vec3 up_world_in_view = normalize((VIEW_MATRIX * vec4(0.0, 0.86, 0.50, 0.0)).xyz);
	NORMAL = normalize(mix(NORMAL, up_world_in_view, normal_up_bias));

	BACKLIGHT = vec3(1.0, 0.92, 0.82) * backlight_strength;
	EMISSION = tex.rgb * self_warmth;
}
