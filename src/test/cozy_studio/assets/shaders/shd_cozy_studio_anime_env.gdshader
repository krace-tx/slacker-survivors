shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Warm Cozy Anime Illustration Environment Shader (`shd_cozy_studio_anime_env.gdshader`):
// Replaces cold/plastic linear PBR Lambertian shading on the 3D studio venue with:
// 1. World-space hand-painted gouache paper & subtle honey-oak wood grain brushwork;
// 2. Vertical warm floor-bounce & airy loft ceiling color-temperature gradient;
// 3. 2-band soft anime cel-shading ramp with warm apricot-rose shadow tint (zero muddy grey shadows)
//    plus crisp golden sunlit highlights and gentle Fresnel rim light.

uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec3 emission_color : source_color = vec3(0.0, 0.0, 0.0);
uniform float emission_energy : hint_range(0.0, 6.0) = 0.0;
uniform float roughness_val : hint_range(0.05, 0.88) = 0.65;
uniform float metallic_val : hint_range(0.0, 1.0) = 0.0;

uniform float cel_threshold : hint_range(0.15, 0.70) = 0.38;
uniform float cel_softness : hint_range(0.01, 0.25) = 0.065;
uniform vec3 shadow_warm_tint : source_color = vec3(0.90, 0.74, 0.68);
uniform vec3 sunlit_warm_tint : source_color = vec3(1.04, 0.99, 0.92);

uniform float paper_grain_strength : hint_range(0.0, 0.12) = 0.032;
uniform float wood_grain_strength : hint_range(0.0, 0.16) = 0.0;
uniform float rim_strength : hint_range(0.0, 0.35) = 0.09;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float value_noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float n000 = hash31(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0, 1.0, 1.0));

	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);

	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);
	return mix(nxy0, nxy1, f.z);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_NORMAL_MATRIX * NORMAL));
}

void fragment() {
	vec3 base_col = albedo_color.rgb;

	// 1. Subtle hand-painted gouache wash variation in world space
	float wash_a = value_noise3(v_world_pos * 2.6);
	float wash_b = value_noise3(v_world_pos * 7.8 + vec3(4.2, 1.7, 8.9));
	float paper_wash = (wash_a * 0.65 + wash_b * 0.35) - 0.5;
	base_col *= (1.0 + paper_wash * paper_grain_strength * 2.0);

	// 2. Anisotropic honey-oak brushwork streaks for wooden furniture/floors/beams
	if (wood_grain_strength > 0.001) {
		vec3 grain_coord = vec3(v_world_pos.x * 3.2, v_world_pos.y * 14.0, v_world_pos.z * 16.5);
		float fiber = value_noise3(grain_coord) * 0.7 + value_noise3(grain_coord * 2.3) * 0.3;
		float ring = sin((v_world_pos.x * 5.5 + v_world_pos.y * 8.0 + fiber * 2.8) * 3.14159) * 0.5 + 0.5;
		vec3 warm_fiber_tint = mix(vec3(0.92, 0.85, 0.79), vec3(1.06, 1.02, 0.96), ring);
		base_col = mix(base_col, base_col * warm_fiber_tint, wood_grain_strength * 4.5);
	}

	// 3. Vertical anime background gradient: warm ochre floor bounce + airy upper wall lift
	float h_norm = clamp(v_world_pos.y / 4.0, 0.0, 1.0);
	vec3 vertical_tint = mix(vec3(1.02, 0.97, 0.93), vec3(1.01, 1.01, 1.00), smoothstep(0.0, 0.45, h_norm));
	vertical_tint = mix(vertical_tint, vec3(1.03, 1.02, 0.99), smoothstep(0.55, 1.0, h_norm));
	base_col *= vertical_tint;

	ALBEDO = clamp(base_col, vec3(0.0), vec3(1.0));
	// Always keep < 0.90 so post-process ink outline distinguishes 3D room from 2D standees (0.99)
	ROUGHNESS = clamp(roughness_val, 0.08, 0.88);
	METALLIC = metallic_val;
	SPECULAR = 0.25;
	EMISSION = emission_color * emission_energy;
}

void light() {
	// Half-Lambert wrapped angle combined with real-time window-mullion / furniture shadow map
	float ndotl = dot(NORMAL, LIGHT);
	float wrapped = clamp(ndotl * 0.55 + 0.45, 0.0, 1.0);
	float lit_metric = wrapped * ATTENUATION;

	// 2-step soft anime cel-shading bands
	float band_lit = smoothstep(cel_threshold - cel_softness, cel_threshold + cel_softness, lit_metric);
	float band_hi = smoothstep(0.76, 0.88, lit_metric);

	// Warm apricot-rose shadow bounce instead of grey Lambertian falloff
	vec3 toon_ramp = mix(shadow_warm_tint * 0.14, sunlit_warm_tint * 0.84, band_lit);
	toon_ramp += vec3(1.0, 0.96, 0.86) * (band_hi * 0.14);

	// Gentle anime rim kiss on sunlit edges
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.2);
	float sun_rim = fresnel * band_lit * rim_strength;

	vec3 light_linear = LIGHT_COLOR / PI;
	DIFFUSE_LIGHT += light_linear * (toon_ramp + vec3(1.0, 0.95, 0.85) * sun_rim);

	// Crisp stylized specular highlight for brass / ceramic / espresso machine accents
	if (ROUGHNESS < 0.45) {
		vec3 half_vec = normalize(LIGHT + VIEW);
		float ndoth = max(dot(NORMAL, half_vec), 0.0);
		float spec_step = smoothstep(0.94, 0.975, ndoth) * band_lit;
		SPECULAR_LIGHT += light_linear * spec_step * (0.38 + METALLIC * 0.45);
	}
}
