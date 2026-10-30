class_name CozyStudioStage3D
extends Node3D

## 3D 温馨二次元画室舞台组件（封装 3D 赛璐璐水彩笔触着色转换、暖杏色软暗部、法式窗影与丁达尔光束）。

const _ANIME_ENV_SHADER_PATH: String = "res://src/test/cozy_studio/assets/shaders/shd_cozy_studio_anime_env.gdshader"
const _SUNBEAM_SHADER_PATH: String = "res://src/test/cozy_studio/assets/shaders/shd_cozy_studio_sunbeam.gdshader"
const _SUN_MOTE_TEX_PATH: String = "res://src/test/cozy_studio/assets/textures/fx_cozy_studio_sun_mote.png"

class _AnimeSurfaceSlot extends RefCounted:
	var mesh_inst: MeshInstance3D = null
	var surface_idx: int = 0
	var toon_mat: ShaderMaterial = null

@onready var _world_env: WorldEnvironment = %WorldEnvironment as WorldEnvironment
@onready var _sun_light: DirectionalLight3D = %SunLight as DirectionalLight3D
@onready var _bounce_fill_light: DirectionalLight3D = %BounceFillLight as DirectionalLight3D
@onready var _desk_lamp_light: OmniLight3D = %DeskLampLight as OmniLight3D
@onready var _coffee_bar_light: OmniLight3D = %CoffeeBarLight as OmniLight3D
@onready var _window_fill_light: OmniLight3D = %WindowFillLight as OmniLight3D
@onready var _room_model: Node3D = %RoomModel as Node3D
@onready var _sunbeam_root: Node3D = %SunbeamRoot as Node3D
@onready var _sunbeam_sheet_0: MeshInstance3D = %SunbeamSheet0 as MeshInstance3D
@onready var _sunbeam_sheet_1: MeshInstance3D = %SunbeamSheet1 as MeshInstance3D
@onready var _dust_particles: GPUParticles3D = %SunDustParticles as GPUParticles3D

var _env: Environment = null
var _sunbeam_mat: ShaderMaterial = null
var _anime_surface_slots: Array[_AnimeSurfaceSlot] = []
var _window_glass_mats: Array[StandardMaterial3D] = []


func _ready() -> void:
	_prepare_room_anime_materials()
	_setup_environment()
	_setup_sunbeams()
	_setup_dust_particles()
	apply_lighting_mood(CozyStudioState.LightingMood.AFTERNOON_SUN, true)


func get_stage_environment() -> Environment:
	return _env


## 遍历高精 3D 场地网格：关闭半透明窗玻璃/白纱帘/玻璃罩硬阴影，并为不透明表面生成二阶暖色赛璐璐水彩材质。
func _prepare_room_anime_materials() -> void:
	_anime_surface_slots.clear()
	_window_glass_mats.clear()
	if _room_model == null:
		return
	var env_shader: Shader = load(_ANIME_ENV_SHADER_PATH) as Shader
	if env_shader == null:
		return

	var mat_cache: Dictionary = {}
	var glass_seen: Dictionary = {}
	var stack: Array[Node] = [_room_model]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var mi: MeshInstance3D = cur as MeshInstance3D
			if (
				mi.name.contains("SunlitGlass")
				or mi.name.contains("Curtain")
				or mi.name.contains("GlassCloche")
			):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

			if mi.mesh != null:
				var surf_count: int = mi.mesh.get_surface_count()
				for s_idx: int in range(surf_count):
					var base_mat: Material = mi.get_active_material(s_idx)
					if not (base_mat is StandardMaterial3D):
						continue
					var std_mat: StandardMaterial3D = base_mat as StandardMaterial3D
					var mat_name: String = std_mat.resource_name
					if mi.name.contains("SunlitGlass") and mat_name.contains("SunlitGlass"):
						var gid: int = std_mat.get_instance_id()
						if not glass_seen.has(gid):
							glass_seen[gid] = true
							_window_glass_mats.append(std_mat)
						continue
					if std_mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
						continue
					if (
						mat_name.contains("SunlitGlass")
						or mat_name.contains("Curtain")
						or mat_name.contains("Iced_Latte")
					):
						continue

					var toon_mat: ShaderMaterial = null
					var key_id: int = std_mat.get_instance_id()
					if mat_cache.has(key_id):
						toon_mat = mat_cache[key_id] as ShaderMaterial
					else:
						toon_mat = _build_toon_material_from_pbr(env_shader, std_mat, mat_name)
						mat_cache[key_id] = toon_mat

					var slot := _AnimeSurfaceSlot.new()
					slot.mesh_inst = mi
					slot.surface_idx = s_idx
					slot.toon_mat = toon_mat
					_anime_surface_slots.append(slot)

		for ch: Node in cur.get_children():
			stack.append(ch)


func _build_toon_material_from_pbr(
	env_shader: Shader,
	std_mat: StandardMaterial3D,
	mat_name: String
) -> ShaderMaterial:
	var smat := ShaderMaterial.new()
	smat.shader = env_shader
	smat.set_shader_parameter("albedo_color", std_mat.albedo_color)
	smat.set_shader_parameter("roughness_val", clampf(std_mat.roughness, 0.14, 0.85))
	smat.set_shader_parameter("metallic_val", std_mat.metallic)

	if std_mat.emission_enabled:
		smat.set_shader_parameter("emission_color", std_mat.emission)
		smat.set_shader_parameter("emission_energy", std_mat.emission_energy_multiplier)
	else:
		smat.set_shader_parameter("emission_color", Color.BLACK)
		smat.set_shader_parameter("emission_energy", 0.0)

	if mat_name.contains("Wood"):
		smat.set_shader_parameter("wood_grain_strength", 0.052)
		smat.set_shader_parameter("paper_grain_strength", 0.024)
	elif mat_name.contains("Wall") or mat_name.contains("Rug") or mat_name.contains("Cushion"):
		smat.set_shader_parameter("wood_grain_strength", 0.0)
		smat.set_shader_parameter("paper_grain_strength", 0.036)
	else:
		smat.set_shader_parameter("wood_grain_strength", 0.0)
		smat.set_shader_parameter("paper_grain_strength", 0.022)
	return smat


func _set_anime_surface_materials_enabled(enabled: bool) -> void:
	for slot: _AnimeSurfaceSlot in _anime_surface_slots:
		if slot.mesh_inst != null:
			slot.mesh_inst.set_surface_override_material(
				slot.surface_idx,
				slot.toon_mat if enabled else null
			)


func _setup_environment() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color("#F5E6CF")
	RenderingServer.set_default_clear_color(Color("#F5E6CF"))

	# 高明度暖杏粉环境补光，配合赛璐璐明暗阶梯营造新海诚/吉卜力治愈插画氛围
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color("#FADFC4")
	_env.ambient_light_energy = 0.64

	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 0.98
	_env.tonemap_white = 1.28

	# 轻柔接触阴影仅加深木地板家具交界，绝不弄脏墙面水彩感
	_env.ssao_enabled = true
	_env.ssao_radius = 0.48
	_env.ssao_intensity = 0.58
	_env.ssao_light_affect = 0.52

	# 柔光漫射越过法式高窗与 2D 立牌边缘，统一空间空气感
	_env.glow_enabled = true
	_env.glow_intensity = 0.38
	_env.glow_strength = 0.94
	_env.glow_bloom = 0.06
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.07
	_env.adjustment_contrast = 1.03

	if _world_env != null:
		_world_env.environment = _env


func _setup_sunbeams() -> void:
	if _sunbeam_root == null:
		return
	var shd: Shader = load(_SUNBEAM_SHADER_PATH) as Shader
	_sunbeam_mat = ShaderMaterial.new()
	_sunbeam_mat.shader = shd
	_sunbeam_mat.render_priority = 1

	var qm := QuadMesh.new()
	qm.size = Vector2(1.88, 5.40)
	var sheets: Array[MeshInstance3D] = [_sunbeam_sheet_0, _sunbeam_sheet_1]
	for beam: MeshInstance3D in sheets:
		if beam != null:
			beam.mesh = qm
			beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			beam.material_override = _sunbeam_mat


func _setup_dust_particles() -> void:
	if _dust_particles == null:
		return
	var pmat := ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pmat.emission_box_extents = Vector3(3.1, 1.5, 2.8)
	pmat.direction = Vector3(0.4, -0.3, 0.1)
	pmat.spread = 65.0
	pmat.initial_velocity_min = 0.04
	pmat.initial_velocity_max = 0.11
	pmat.gravity = Vector3(0.0, -0.015, 0.0)
	pmat.scale_min = 0.75
	pmat.scale_max = 1.55

	var mote_tex: Texture2D = load(_SUN_MOTE_TEX_PATH) as Texture2D
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	var m_mat := StandardMaterial3D.new()
	m_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m_mat.albedo_texture = mote_tex
	m_mat.albedo_color = Color(1.0, 0.94, 0.76, 0.78)
	m_mat.render_priority = 2
	quad.material = m_mat

	_dust_particles.position = Vector3(-1.25, 1.65, 0.20)
	_dust_particles.amount = 64
	_dust_particles.lifetime = 5.5
	_dust_particles.preprocess = 3.0
	_dust_particles.process_material = pmat
	_dust_particles.draw_pass_1 = quad
	_dust_particles.emitting = true


## 应用光照氛围与二次元赛璐璐背景画风开关（G 键支持实时 A/B 对比）。
func apply_lighting_mood(mood: CozyStudioState.LightingMood, glue_on: bool) -> void:
	_set_anime_surface_materials_enabled(glue_on)

	if _env != null:
		_env.glow_enabled = glue_on
		_env.ssao_enabled = glue_on
		if mood == CozyStudioState.LightingMood.AFTERNOON_SUN:
			var bg_col := Color("#F5E6CF") if glue_on else Color("#CBD5E1")
			_env.background_color = bg_col
			RenderingServer.set_default_clear_color(bg_col)
			_env.ambient_light_color = Color("#FADFC4") if glue_on else Color("#94A3B8")
			_env.ambient_light_energy = 0.64 if glue_on else 0.36
		else:
			var night_bg := Color("#2D2638")
			_env.background_color = night_bg
			RenderingServer.set_default_clear_color(night_bg)
			_env.ambient_light_color = Color("#8D789F")
			_env.ambient_light_energy = 0.48

	for gmat: StandardMaterial3D in _window_glass_mats:
		if mood == CozyStudioState.LightingMood.AFTERNOON_SUN:
			gmat.albedo_color = Color(1.0, 0.97, 0.89, 0.26)
			gmat.emission = Color("#FFE8B5")
			gmat.emission_energy_multiplier = 1.10
		else:
			gmat.albedo_color = Color(0.38, 0.45, 0.68, 0.42)
			gmat.emission = Color("#5B6EA6")
			gmat.emission_energy_multiplier = 0.55

	if _sun_light != null:
		_sun_light.directional_shadow_max_distance = 23.0
		if mood == CozyStudioState.LightingMood.AFTERNOON_SUN:
			_sun_light.shadow_enabled = true
			_sun_light.shadow_blur = 1.55
			_sun_light.light_color = Color("#FFEDC8")
			_sun_light.light_energy = 1.22
			_sun_light.rotation_degrees = Vector3(-31.0, -93.0, 0.0)
		else:
			_sun_light.shadow_enabled = false
			_sun_light.light_color = Color("#93A8F4")
			_sun_light.light_energy = 0.24
			_sun_light.rotation_degrees = Vector3(-38.0, -93.0, 0.0)

	if _bounce_fill_light != null:
		_bounce_fill_light.light_energy = (
			(0.24 if glue_on else 0.08)
			if mood == CozyStudioState.LightingMood.AFTERNOON_SUN
			else 0.14
		)

	if _window_fill_light != null:
		_window_fill_light.light_energy = 0.58 if mood == CozyStudioState.LightingMood.AFTERNOON_SUN else 0.18

	if _desk_lamp_light != null:
		_desk_lamp_light.light_energy = 0.90 if mood == CozyStudioState.LightingMood.AFTERNOON_SUN else 2.35

	if _coffee_bar_light != null:
		_coffee_bar_light.light_energy = 1.05 if mood == CozyStudioState.LightingMood.AFTERNOON_SUN else 2.55

	if _sunbeam_root != null:
		_sunbeam_root.visible = glue_on and (mood == CozyStudioState.LightingMood.AFTERNOON_SUN)

	if _dust_particles != null:
		_dust_particles.visible = glue_on
