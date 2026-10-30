shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, depth_test_disabled, cull_disabled;

// Screen-Space Warm Brown Anime Pen Lineart Post-Process (`shd_cozy_studio_anime_outline.gdshader`):
// - Uses plane-normal-weighted metric step detection (`abs(dot(P_neighbor - P_center, N_center))`)
//   plus view-space normal crease detection so flat floors/walls NEVER get grazing-angle artifacts,
//   while furniture silhouettes, wainscots, rafters, books, and botanical leaves get crisp hand-drawn
//   warm brown (`#4E3121`) anime background linework.
// - Automatically masks out 2D standee characters (`ROUGHNESS > 0.96`) so 2D sprites keep only their
//   native hand-drawn lineart with zero double-outlining!

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D norm_rough_tex : hint_normal_roughness_texture, repeat_disable, filter_nearest;

uniform vec4 ink_color : source_color = vec4(0.31, 0.19, 0.13, 0.72);
uniform float line_thickness_px : hint_range(0.5, 2.5) = 1.15;
uniform float depth_step_min_m : hint_range(0.01, 0.20) = 0.038;
uniform float depth_step_max_m : hint_range(0.03, 0.40) = 0.095;
uniform float normal_edge_min : hint_range(0.05, 0.80) = 0.26;
uniform float normal_edge_max : hint_range(0.10, 0.98) = 0.52;

vec3 reconstruct_view_pos(vec2 uv, float raw_d, mat4 inv_proj) {
	vec3 ndc = vec3(uv * 2.0 - 1.0, raw_d);
	vec4 view_p = inv_proj * vec4(ndc, 1.0);
	return view_p.xyz / max(abs(view_p.w), 1e-6);
}

vec3 decode_view_normal(vec3 enc) {
	vec3 n = enc * 2.0 - 1.0;
	float len = length(n);
	return len > 0.001 ? (n / len) : vec3(0.0, 0.0, 1.0);
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 texel = (1.0 / VIEWPORT_SIZE) * line_thickness_px;

	vec4 nr_c = texture(norm_rough_tex, SCREEN_UV);
	float d_c = texture(depth_tex, SCREEN_UV).r;

	// Skip empty background sky/clear pixels (Reverse-Z far plane is 0.0)
	if (d_c <= 0.00001) {
		ALPHA = 0.0;
	} else {
		vec2 uv_l = clamp(SCREEN_UV + vec2(-texel.x, 0.0), vec2(0.001), vec2(0.999));
		vec2 uv_r = clamp(SCREEN_UV + vec2(texel.x, 0.0), vec2(0.001), vec2(0.999));
		vec2 uv_u = clamp(SCREEN_UV + vec2(0.0, -texel.y), vec2(0.001), vec2(0.999));
		vec2 uv_d = clamp(SCREEN_UV + vec2(0.0, texel.y), vec2(0.001), vec2(0.999));

		vec4 nr_l = texture(norm_rough_tex, uv_l);
		vec4 nr_r = texture(norm_rough_tex, uv_r);
		vec4 nr_u = texture(norm_rough_tex, uv_u);
		vec4 nr_d = texture(norm_rough_tex, uv_d);

		// Protect 2D standee characters (ROUGHNESS = 0.99) from receiving 3D post-process outlines
		float max_rough = max(nr_c.w, max(max(nr_l.w, nr_r.w), max(nr_u.w, nr_d.w)));
		if (max_rough > 0.96) {
			ALPHA = 0.0;
		} else {
			float d_l = texture(depth_tex, uv_l).r;
			float d_r = texture(depth_tex, uv_r).r;
			float d_u = texture(depth_tex, uv_u).r;
			float d_d = texture(depth_tex, uv_d).r;

			vec3 p_c = reconstruct_view_pos(SCREEN_UV, d_c, INV_PROJECTION_MATRIX);
			vec3 p_l = reconstruct_view_pos(uv_l, d_l, INV_PROJECTION_MATRIX);
			vec3 p_r = reconstruct_view_pos(uv_r, d_r, INV_PROJECTION_MATRIX);
			vec3 p_u = reconstruct_view_pos(uv_u, d_u, INV_PROJECTION_MATRIX);
			vec3 p_d = reconstruct_view_pos(uv_d, d_d, INV_PROJECTION_MATRIX);

			vec3 n_c = decode_view_normal(nr_c.xyz);
			vec3 n_l = decode_view_normal(nr_l.xyz);
			vec3 n_r = decode_view_normal(nr_r.xyz);
			vec3 n_u = decode_view_normal(nr_u.xyz);
			vec3 n_d = decode_view_normal(nr_d.xyz);

			// Plane-aligned metric depth discontinuity (zero false positives on angled floors/walls!)
			float dist_scale = clamp(-p_c.z / 12.0, 0.75, 1.85);
			float pd_l = abs(dot(p_l - p_c, n_c));
			float pd_r = abs(dot(p_r - p_c, n_c));
			float pd_u = abs(dot(p_u - p_c, n_c));
			float pd_d = abs(dot(p_d - p_c, n_c));
			float max_plane_step = max(max(pd_l, pd_r), max(pd_u, pd_d)) / dist_scale;
			float depth_edge = smoothstep(depth_step_min_m, depth_step_max_m, max_plane_step);

			// View-space normal crease detection (wainscoting trims, book spines, corners, beams)
			float ndiff_h = 1.0 - clamp(dot(n_l, n_r), -1.0, 1.0);
			float ndiff_v = 1.0 - clamp(dot(n_u, n_d), -1.0, 1.0);
			float ndiff_c = max(1.0 - clamp(dot(n_c, n_r), -1.0, 1.0), 1.0 - clamp(dot(n_c, n_d), -1.0, 1.0));
			float normal_crease = max(max(ndiff_h, ndiff_v) * 0.65, ndiff_c);
			float normal_edge = smoothstep(normal_edge_min, normal_edge_max, normal_crease) * 0.72;

			// Slightly soften distant background ink lines for aerial depth hierarchy
			float depth_fade = clamp(1.18 - (-p_c.z - 8.0) * 0.032, 0.52, 1.0);
			float edge = clamp(max(depth_edge, normal_edge), 0.0, 1.0) * depth_fade;

			ALBEDO = ink_color.rgb;
			ALPHA = edge * ink_color.a;
		}
	}
}
