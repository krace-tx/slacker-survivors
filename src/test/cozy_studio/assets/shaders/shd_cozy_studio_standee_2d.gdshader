shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// 2.5D Cozy Anime Standee Shader (3-View Idle/Walk/Sit UV Atlas + Plumb-Line Depth Anchor):
// 1. Uniform cell UV slicing (`sheet_grid` + `frame_index`) drives both color & 3D shadow silhouette.
// 2. Plumb-line view-space depth compensation (`tilt_depth_comp` + `seat_depth_pull`) prevents backward-tilted
//    2D standees from slicing into 3D walls, chair backrests, or sofa cushions when walking close or sitting!
// 3. Up-biased view-space normal + paper backlight keeps warm anime colors when rotating camera.

uniform sampler2D albedo_texture : source_color, filter_linear, repeat_disable;
uniform vec4 tint_color : source_color = vec4(1.0, 0.99, 0.97, 1.0);
uniform ivec2 sheet_grid = ivec2(1, 1);
uniform int frame_index = 0;
uniform float sticker_rim_px : hint_range(0.0, 14.0) = 6.5;
uniform vec4 sticker_rim_color : source_color = vec4(1.0, 0.992, 0.968, 1.0);
uniform float normal_up_bias : hint_range(0.0, 1.0) = 0.78;
uniform float self_warmth : hint_range(0.0, 0.6) = 0.18;
uniform float backlight_strength : hint_range(0.0, 0.8) = 0.28;
uniform float alpha_cutoff : hint_range(0.05, 0.95) = 0.42;
uniform float tilt_depth_comp : hint_range(0.0, 0.85) = 0.52;
uniform float seat_depth_pull : hint_range(0.0, 0.45) = 0.0;
uniform bool flip_h = false;

float sample_cell_alpha(vec2 cell_uv, int col, int row, vec2 inv_grid) {
	if (cell_uv.x <= 0.001 || cell_uv.x >= 0.999 || cell_uv.y <= 0.001 || cell_uv.y >= 0.999) {
		return 0.0;
	}
	vec2 uv = (vec2(float(col), float(row)) + cell_uv) * inv_grid;
	return texture(albedo_texture, uv).a;
}

void fragment() {
	vec2 local_uv = UV;
	if (flip_h) {
		local_uv.x = 1.0 - local_uv.x;
	}

	ivec2 safe_grid = max(ivec2(1, 1), sheet_grid);
	vec2 inv_grid = 1.0 / vec2(safe_grid);
	int total_frames = safe_grid.x * safe_grid.y;
	int safe_frame = clamp(frame_index, 0, total_frames - 1);
	int col = safe_frame % safe_grid.x;
	int row = safe_frame / safe_grid.x;

	vec2 inner_uv = clamp(local_uv, vec2(0.001), vec2(0.999));
	vec2 atlas_uv = (vec2(float(col), float(row)) + inner_uv) * inv_grid;

	vec4 raw_tex = texture(albedo_texture, atlas_uv);
	float out_alpha = raw_tex.a;
	vec3 base_rgb = raw_tex.rgb;

	if (sticker_rim_px > 0.05) {
		if (raw_tex.a < 0.82) {
			vec2 cell_texel = vec2(safe_grid) / max(vec2(1.0), vec2(textureSize(albedo_texture, 0)));
			vec2 r_outer = cell_texel * sticker_rim_px;
			vec2 r_inner = r_outer * 0.52;
			float max_neighbor_a = raw_tex.a;
			const vec2 DIRS_12[12] = vec2[12](
				vec2(1.0, 0.0), vec2(0.866025, 0.5), vec2(0.5, 0.866025),
				vec2(0.0, 1.0), vec2(-0.5, 0.866025), vec2(-0.866025, 0.5),
				vec2(-1.0, 0.0), vec2(-0.866025, -0.5), vec2(-0.5, -0.866025),
				vec2(0.0, -1.0), vec2(0.5, -0.866025), vec2(0.866025, -0.5)
			);
			for (int i = 0; i < 12; i++) {
				max_neighbor_a = max(max_neighbor_a, sample_cell_alpha(local_uv + DIRS_12[i] * r_outer, col, row, inv_grid));
				if ((i & 1) == 0) {
					max_neighbor_a = max(max_neighbor_a, sample_cell_alpha(local_uv + DIRS_12[i] * r_inner, col, row, inv_grid));
				}
			}
			out_alpha = max_neighbor_a;
		}
		vec3 unpremult_rgb = (raw_tex.a > 0.96) ? raw_tex.rgb : clamp(raw_tex.rgb / max(raw_tex.a, 0.08), vec3(0.0), vec3(1.0));
		float body_mask = smoothstep(0.26, 0.78, raw_tex.a);
		base_rgb = mix(sticker_rim_color.rgb, unpremult_rgb, body_mask);
	}

	vec3 tinted_rgb = base_rgb * tint_color.rgb;
	ALPHA = out_alpha * tint_color.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;

	// Compensate backward tilt in main camera pass so standee acts as a vertical cylinder at its foot/hip anchor!
	// Skip in directional/omni shadow passes (`PROJECTION_MATRIX[2][3]` is < -0.5 for perspective camera,
	// or check `INV_VIEW_MATRIX` camera forward vs light). Even cleaner: `seat_depth_pull` + `tilt_depth_comp`
	// moves toward camera (+Z in view space) which is safe and tiny (< 0.5m).
	float height_factor = clamp(1.0 - UV.y, 0.0, 1.0);
	float pull_z = height_factor * tilt_depth_comp + seat_depth_pull;
	vec3 biased_view = VERTEX + vec3(0.0, 0.0, pull_z);
	vec4 clip_pos = PROJECTION_MATRIX * vec4(biased_view, 1.0);
	DEPTH = clamp(clip_pos.z / clip_pos.w, 0.0, 1.0);

	ALBEDO = tinted_rgb;
	// Signature roughness (> 0.96) lets the 3D anime ink-outline pass skip 2D standee silhouettes
	ROUGHNESS = 0.99;
	METALLIC = 0.0;
	SPECULAR = 0.04;

	vec3 up_world_in_view = normalize((VIEW_MATRIX * vec4(0.0, 0.86, 0.50, 0.0)).xyz);
	NORMAL = normalize(mix(NORMAL, up_world_in_view, normal_up_bias));

	BACKLIGHT = vec3(1.0, 0.92, 0.82) * backlight_strength;
	EMISSION = tinted_rgb * self_warmth;
}
