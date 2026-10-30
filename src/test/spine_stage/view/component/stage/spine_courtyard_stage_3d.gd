@tool
class_name SpineCourtyardStage3D
extends Node3D

## 2.5D 古堡火盆庭院 3D 舞台组件（支持 `@tool` 编辑器实时材质/光影预览、主太阳/月光阴影、双摇曳火盆点光源阴影与双层石阶碰撞体）。[br]
##
## [b]核心职责：[/b][br]
## 1. 在编辑器 `.tscn` 视口与运行期同步为 3D 庭院地面、北侧石阶高台、哥特石柱与双火盆赋予定制 PBR 石材材质；[br]
## 2. 实时驱动左右双火盆 [OmniLight3D] 暖橙火光呼吸摇曳，使靠近火盆的 2D 角色投射动态舞动的剪影长影；[br]
## 3. 支持一键切换「黄昏斜阳」与「幽蓝月夜 + 火把长影」两套 3D 光影环境预设。

#region Exports
@export var preview_lighting_mode: SpineStageConfig.LightingMode = SpineStageConfig.LightingMode.DUSK_COURTYARD:
	set(value):
		preview_lighting_mode = value
		if is_node_ready():
			apply_lighting_mode(int(preview_lighting_mode))
#endregion

#region Private Node Refs & State
@onready var _world_env: WorldEnvironment = %WorldEnv as WorldEnvironment
@onready var _sun_light: DirectionalLight3D = %SunLight as DirectionalLight3D
@onready var _torch_light_left: OmniLight3D = %TorchLightLeft as OmniLight3D
@onready var _torch_light_right: OmniLight3D = %TorchLightRight as OmniLight3D
@onready var _flame_orb_left: MeshInstance3D = %FlameOrbLeft as MeshInstance3D
@onready var _flame_orb_right: MeshInstance3D = %FlameOrbRight as MeshInstance3D
@onready var _floor_mesh: MeshInstance3D = %FloorMesh as MeshInstance3D
@onready var _inner_plaza_mesh: MeshInstance3D = %InnerPlazaMesh as MeshInstance3D
@onready var _dais_mesh: MeshInstance3D = %DaisMesh as MeshInstance3D
@onready var _step_mesh: MeshInstance3D = %StepMesh as MeshInstance3D
@onready var _pillar_nw: MeshInstance3D = %PillarNW as MeshInstance3D
@onready var _pillar_ne: MeshInstance3D = %PillarNE as MeshInstance3D
@onready var _brazier_left_mesh: MeshInstance3D = %BrazierLeftMesh as MeshInstance3D
@onready var _brazier_right_mesh: MeshInstance3D = %BrazierRightMesh as MeshInstance3D

var _env_res: Environment = null
var _sky_mat: ProceduralSkyMaterial = null
var _flicker_time: float = 0.0
var _base_torch_energy: float = 2.6
#endregion


#region Lifecycle
func _ready() -> void:
	_setup_environment()
	_setup_stage_materials()
	apply_lighting_mode(int(preview_lighting_mode))


func _process(delta: float) -> void:
	_flicker_time += delta
	var pulse_l: float = sin(_flicker_time * 7.3) * 0.16 + sin(_flicker_time * 13.7) * 0.08
	var pulse_r: float = cos(_flicker_time * 6.8 + 1.2) * 0.16 + sin(_flicker_time * 15.1) * 0.08
	if _torch_light_left != null:
		_torch_light_left.light_energy = _base_torch_energy * (1.0 + pulse_l)
	if _torch_light_right != null:
		_torch_light_right.light_energy = _base_torch_energy * (1.0 + pulse_r)
	if _flame_orb_left != null:
		var sl: float = 1.0 + pulse_l * 0.35
		_flame_orb_left.scale = Vector3(sl, sl * 1.25, sl)
	if _flame_orb_right != null:
		var sr: float = 1.0 + pulse_r * 0.35
		_flame_orb_right.scale = Vector3(sr, sr * 1.25, sr)
#endregion


#region Public API
## 切换 3D 舞台的环境天光、平行主光角度与火盆点光源能量配比。
func apply_lighting_mode(mode: int) -> void:
	if _env_res == null:
		_setup_environment()
	if mode == SpineStageConfig.LightingMode.MOONLIGHT_TORCH:
		if _sky_mat != null:
			_sky_mat.sky_top_color = Color("#090E1A")
			_sky_mat.sky_horizon_color = Color("#1B2845")
			_sky_mat.ground_horizon_color = Color("#0F172A")
			_sky_mat.ground_bottom_color = Color("#060911")
		_env_res.ambient_light_color = Color("#3B5284")
		_env_res.ambient_light_energy = 0.42
		if _sun_light != null:
			_sun_light.light_color = Color("#93C5FD")
			_sun_light.light_energy = 0.68
			_sun_light.rotation_degrees = Vector3(-42.0, -34.0, 0.0)
		_base_torch_energy = 3.85
	else:
		if _sky_mat != null:
			_sky_mat.sky_top_color = Color("#1E293B")
			_sky_mat.sky_horizon_color = Color("#7C4A3A")
			_sky_mat.ground_horizon_color = Color("#292524")
			_sky_mat.ground_bottom_color = Color("#0C0A09")
		_env_res.ambient_light_color = Color("#CBD5E1")
		_env_res.ambient_light_energy = 0.58
		if _sun_light != null:
			_sun_light.light_color = Color("#FDE68A")
			_sun_light.light_energy = 1.38
			_sun_light.rotation_degrees = Vector3(-46.0, 38.0, 0.0)
		_base_torch_energy = 2.45
#endregion


#region Internal Material & Environment Setup
func _setup_environment() -> void:
	if _world_env == null:
		return
	_sky_mat = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = _sky_mat

	_env_res = Environment.new()
	_env_res.background_mode = Environment.BG_SKY
	_env_res.sky = sky
	_env_res.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env_res.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env_res.tonemap_exposure = 1.05
	_env_res.ssao_enabled = true
	_env_res.ssao_radius = 0.85
	_env_res.ssao_intensity = 1.45
	_env_res.glow_enabled = true
	_env_res.glow_intensity = 0.45
	_env_res.glow_bloom = 0.12
	_env_res.fog_enabled = true
	_env_res.fog_light_color = Color("#1E293B")
	_env_res.fog_density = 0.012
	_world_env.environment = _env_res

	if _sun_light != null:
		_sun_light.shadow_enabled = true
		_sun_light.directional_shadow_max_distance = 36.0
		_sun_light.shadow_blur = 0.85

	for torch: OmniLight3D in [_torch_light_left, _torch_light_right]:
		if torch != null:
			torch.shadow_enabled = true
			torch.omni_range = 8.2
			torch.omni_attenuation = 1.25
			torch.light_color = Color("#FB923C")


func _setup_stage_materials() -> void:
	var stone_tile_tex: ImageTexture = _build_stone_grid_texture(
		Color("#475569"),
		Color("#334155"),
		Color("#1E293B"),
		8
	)
	var plaza_tile_tex: ImageTexture = _build_stone_grid_texture(
		Color("#64748B"),
		Color("#475569"),
		Color("#273449"),
		6
	)

	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_texture = stone_tile_tex
	floor_mat.uv1_scale = Vector3(5.0, 4.0, 1.0)
	floor_mat.roughness = 0.86
	if _floor_mesh != null:
		_floor_mesh.material_override = floor_mat

	var plaza_mat := StandardMaterial3D.new()
	plaza_mat.albedo_texture = plaza_tile_tex
	plaza_mat.uv1_scale = Vector3(3.0, 2.5, 1.0)
	plaza_mat.roughness = 0.78
	if _inner_plaza_mesh != null:
		_inner_plaza_mesh.material_override = plaza_mat

	var dais_mat := StandardMaterial3D.new()
	dais_mat.albedo_texture = plaza_tile_tex
	dais_mat.albedo_color = Color("#CBD5E1")
	dais_mat.uv1_scale = Vector3(2.5, 1.5, 1.0)
	dais_mat.roughness = 0.76
	if _dais_mesh != null:
		_dais_mesh.material_override = dais_mat
	if _step_mesh != null:
		_step_mesh.material_override = dais_mat

	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = Color("#475569")
	pillar_mat.roughness = 0.74
	for p_mesh: MeshInstance3D in [_pillar_nw, _pillar_ne]:
		if p_mesh != null:
			p_mesh.material_override = pillar_mat

	var iron_mat := StandardMaterial3D.new()
	iron_mat.albedo_color = Color("#1F2937")
	iron_mat.metallic = 0.65
	iron_mat.roughness = 0.42
	for b_mesh: MeshInstance3D in [_brazier_left_mesh, _brazier_right_mesh]:
		if b_mesh != null:
			b_mesh.material_override = iron_mat

	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.albedo_color = Color("#FDE047")
	for f_mesh: MeshInstance3D in [_flame_orb_left, _flame_orb_right]:
		if f_mesh != null:
			f_mesh.material_override = flame_mat


func _build_stone_grid_texture(c_light: Color, c_mid: Color, c_grout: Color, cells: int) -> ImageTexture:
	var size_px: int = 256
	var cell_px: int = size_px / maxi(1, cells)
	var img := Image.create(size_px, size_px, true, Image.FORMAT_RGBA8)
	for y: int in range(size_px):
		var cy: int = y / cell_px
		var ly: int = y % cell_px
		for x: int in range(size_px):
			var row_shift: int = (cell_px / 2) if (cy % 2 == 1) else 0
			var sx: int = (x + row_shift) % size_px
			var cx: int = sx / cell_px
			var lx: int = sx % cell_px
			if lx <= 2 or ly <= 2:
				img.set_pixel(x, y, c_grout)
			else:
				var checker: bool = ((cx + cy) % 2) == 0
				var base_c: Color = c_light if checker else c_mid
				var bevel: float = 1.04 if (lx < 7 or ly < 7) else 1.0
				img.set_pixel(x, y, Color(base_c.r * bevel, base_c.g * bevel, base_c.b * bevel, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
#endregion
