@tool
class_name OtomeTerraceStage3D
extends Node3D

## 乙女向户外庭院「晴风湖畔 · 花树咖啡露台」3D 舞台组件（支持 `@tool` 编辑器实时预览 + 双套户外光影天气 + 湖水波光与落樱/萤火粒子）。[br]
##
## [b]核心职责：[/b][br]
## 1. 承载由 Blender MCP 建模导出的开放式湖畔露台 [code]mdl_otome_terrace_stage.glb[/code]，并在编辑器与运行期同步挂载波光湖面着色器；[br]
## 2. 构建草坪/石板路与北侧雪松木咖啡露台（`y = 0.16m`）的精确静态碰撞体，并在三处交互点铺设呼吸玫瑰金光环；[br]
## 3. 一键切换「☀ 春昼晴风（飘落樱瓣）」与「🌅 落日星灯（四盏复古铁艺街灯暖光 + 湖畔萤火）」全户外氛围。

#region Exports
@export var preview_weather_mode: OtomeTerraceConfig.WeatherMode = OtomeTerraceConfig.WeatherMode.BREEZE_DAY:
	set(value):
		preview_weather_mode = value
		if is_node_ready():
			apply_weather_mode(int(preview_weather_mode))
#endregion

#region Node Refs & Private State
@onready var _world_env: WorldEnvironment = %WorldEnvironment as WorldEnvironment
@onready var _sun_light: DirectionalLight3D = %SunLight as DirectionalLight3D
@onready var _sky_fill_light: DirectionalLight3D = %SkyFillLight as DirectionalLight3D
@onready var _lamp_light_0: OmniLight3D = %LampLight0 as OmniLight3D
@onready var _lamp_light_1: OmniLight3D = %LampLight1 as OmniLight3D
@onready var _lamp_light_2: OmniLight3D = %LampLight2 as OmniLight3D
@onready var _lamp_light_3: OmniLight3D = %LampLight3 as OmniLight3D
@onready var _terrace_model: Node3D = %TerraceModel as Node3D
@onready var _hotspot_rings_root: Node3D = %HotspotRingsRoot as Node3D
@onready var _blossom_particles: GPUParticles3D = %BlossomParticles as GPUParticles3D

var _env_res: Environment = null
var _sky_mat: ProceduralSkyMaterial = null
var _lake_shader_mat: ShaderMaterial = null
var _ring_mats: Array[ShaderMaterial] = []
var _bulb_std_mats: Array[StandardMaterial3D] = []
var _lamp_lights: Array[OmniLight3D] = []
var _base_lamp_energy: float = 0.0
var _pulse_time: float = 0.0
#endregion


#region Lifecycle
func _ready() -> void:
	_lamp_lights = [_lamp_light_0, _lamp_light_1, _lamp_light_2, _lamp_light_3]
	_setup_environment()
	_setup_walkable_colliders()
	_bind_terrace_model_materials()
	_setup_hotspot_rings()
	_setup_ambient_particles()
	apply_weather_mode(int(preview_weather_mode))


func _process(delta: float) -> void:
	_pulse_time += delta
	if _base_lamp_energy <= 0.01:
		return
	for i: int in range(_lamp_lights.size()):
		var lamp: OmniLight3D = _lamp_lights[i]
		if lamp != null:
			var breath: float = sin(_pulse_time * 3.1 + float(i) * 1.3) * 0.08
			lamp.light_energy = _base_lamp_energy * (1.0 + breath)
#endregion


#region Public Stage API
## 切换「春昼晴风」与「落日星灯」户外天光、平行主光、街灯点光源、湖面反射色及飘落花瓣/萤火。
func apply_weather_mode(mode: int) -> void:
	if _env_res == null:
		_setup_environment()

	if mode == OtomeTerraceConfig.WeatherMode.SUNSET_LIGHTS:
		if _sky_mat != null:
			_sky_mat.sky_top_color = Color("#2C325E")
			_sky_mat.sky_horizon_color = Color("#EB9172")
			_sky_mat.ground_horizon_color = Color("#C97E6A")
			_sky_mat.ground_bottom_color = Color("#262033")
		_env_res.ambient_light_color = Color("#DDA99E")
		_env_res.ambient_light_energy = 0.36
		_env_res.fog_light_color = Color("#DF917B")
		_env_res.fog_density = 0.0052
		if _sun_light != null:
			_sun_light.light_color = Color("#FF9E64")
			_sun_light.light_energy = 0.68
			_sun_light.rotation_degrees = Vector3(-26.0, 42.0, 0.0)
		if _sky_fill_light != null:
			_sky_fill_light.light_color = Color("#B5A4FA")
			_sky_fill_light.light_energy = 0.20
		_base_lamp_energy = 1.85
		for lamp: OmniLight3D in _lamp_lights:
			if lamp != null:
				lamp.visible = true
				lamp.light_energy = _base_lamp_energy
		for bmat: StandardMaterial3D in _bulb_std_mats:
			bmat.emission_enabled = true
			bmat.emission = Color("#FFC67A")
			bmat.emission_energy_multiplier = 2.8
		if _lake_shader_mat != null:
			_lake_shader_mat.set_shader_parameter("shallow_color", Color("#746896"))
			_lake_shader_mat.set_shader_parameter("deep_color", Color("#353966"))
			_lake_shader_mat.set_shader_parameter("glint_color", Color("#FFBE86"))
			_lake_shader_mat.set_shader_parameter("glint_strength", 1.10)
		_configure_particle_tint(Color("#FFE28A"), 1.65)
	else:
		if _sky_mat != null:
			_sky_mat.sky_top_color = Color("#5CA6DE")
			_sky_mat.sky_horizon_color = Color("#E8EFF6")
			_sky_mat.ground_horizon_color = Color("#C9DCC4")
			_sky_mat.ground_bottom_color = Color("#71966E")
		_env_res.ambient_light_color = Color("#F5EAE0")
		_env_res.ambient_light_energy = 0.44
		_env_res.fog_light_color = Color("#EFEAE4")
		_env_res.fog_density = 0.0028
		if _sun_light != null:
			_sun_light.light_color = Color("#FFEFD6")
			_sun_light.light_energy = 0.92
			_sun_light.rotation_degrees = Vector3(-48.0, 34.0, 0.0)
		if _sky_fill_light != null:
			_sky_fill_light.light_color = Color("#FADADD")
			_sky_fill_light.light_energy = 0.18
		_base_lamp_energy = 0.0
		for lamp: OmniLight3D in _lamp_lights:
			if lamp != null:
				lamp.light_energy = 0.0
				lamp.visible = false
		for bmat: StandardMaterial3D in _bulb_std_mats:
			bmat.emission_enabled = true
			bmat.emission = Color("#FFF5E4")
			bmat.emission_energy_multiplier = 0.25
		if _lake_shader_mat != null:
			_lake_shader_mat.set_shader_parameter("shallow_color", Color("#52B6C2"))
			_lake_shader_mat.set_shader_parameter("deep_color", Color("#286E8C"))
			_lake_shader_mat.set_shader_parameter("glint_color", Color("#FFF8E7"))
			_lake_shader_mat.set_shader_parameter("glint_strength", 0.65)
		_configure_particle_tint(Color("#FFC8D8"), 0.0)


## 高亮当前主角走近的户外热点地面光环（`hotspot_id = -1` 时全部恢复常驻柔光）。
func highlight_hotspot_ring(hotspot_id: int) -> void:
	for i: int in range(_ring_mats.size()):
		var rmat: ShaderMaterial = _ring_mats[i]
		if rmat != null:
			rmat.set_shader_parameter("highlight_boost", 1.0 if i == hotspot_id else 0.0)
#endregion


#region Internal Stage Construction & Material Wiring
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
	_env_res.tonemap_exposure = 0.88
	_env_res.ssao_enabled = true
	_env_res.ssao_radius = 0.75
	_env_res.ssao_intensity = 1.15
	_env_res.glow_enabled = true
	_env_res.glow_hdr_threshold = 1.38
	_env_res.glow_intensity = 0.28
	_env_res.glow_bloom = 0.04
	_env_res.fog_enabled = true
	_world_env.environment = _env_res

	if _sun_light != null:
		_sun_light.shadow_enabled = true
		_sun_light.directional_shadow_max_distance = 34.0
		_sun_light.shadow_blur = 0.95

	for i: int in range(_lamp_lights.size()):
		var lamp: OmniLight3D = _lamp_lights[i]
		if lamp != null and i < OtomeTerraceConfig.LAMPPOST_LIGHT_POSITIONS.size():
			lamp.position = OtomeTerraceConfig.LAMPPOST_LIGHT_POSITIONS[i]
			lamp.light_color = Color("#FFB86C")
			lamp.omni_range = 6.8
			lamp.omni_attenuation = 1.25
			lamp.shadow_enabled = (i == 1 or i == 2)


func _setup_walkable_colliders() -> void:
	if Engine.is_editor_hint():
		return
	if get_node_or_null("StageStaticBody") != null:
		return
	var body := StaticBody3D.new()
	body.name = "StageStaticBody"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	var lawn_col := CollisionShape3D.new()
	var lawn_box := BoxShape3D.new()
	lawn_box.size = Vector3(14.0, 0.4, 12.0)
	lawn_col.shape = lawn_box
	lawn_col.position = Vector3(0.0, -0.18, 0.0)
	body.add_child(lawn_col)

	var deck_col := CollisionShape3D.new()
	var deck_box := BoxShape3D.new()
	deck_box.size = Vector3(5.05, 0.16, 3.05)
	deck_col.shape = deck_box
	deck_col.position = Vector3(1.05, 0.08, -3.05)
	body.add_child(deck_col)


func _bind_terrace_model_materials() -> void:
	_bulb_std_mats.clear()
	if _terrace_model == null:
		return
	var lake_shader: Shader = load(OtomeTerraceConfig.LAKE_SHADER_PATH) as Shader
	if lake_shader != null:
		_lake_shader_mat = ShaderMaterial.new()
		_lake_shader_mat.shader = lake_shader

	var bulb_seen: Dictionary = {}
	var stack: Array[Node] = [_terrace_model]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var mi: MeshInstance3D = cur as MeshInstance3D
			if mi.name.contains("LakeWater") and _lake_shader_mat != null:
				mi.material_override = _lake_shader_mat
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			elif mi.name.contains("DistantHills") or mi.name.contains("FallenPetal"):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

			if mi.mesh != null:
				for s_idx: int in range(mi.mesh.get_surface_count()):
					var active_mat: Material = mi.get_active_material(s_idx)
					if active_mat is StandardMaterial3D:
						var smat: StandardMaterial3D = active_mat as StandardMaterial3D
						if smat.resource_name.contains("WarmBulb") or mi.name.contains("Bulb"):
							var mid: int = smat.get_instance_id()
							if not bulb_seen.has(mid):
								bulb_seen[mid] = true
								_bulb_std_mats.append(smat)
		for ch: Node in cur.get_children():
			stack.append(ch)


func _setup_hotspot_rings() -> void:
	_ring_mats.clear()
	if _hotspot_rings_root == null:
		return
	for old_child: Node in _hotspot_rings_root.get_children():
		_hotspot_rings_root.remove_child(old_child)
		old_child.free()

	var ring_shader: Shader = load(OtomeTerraceConfig.RING_SHADER_PATH) as Shader
	if ring_shader == null:
		return

	for i: int in range(OtomeTerraceConfig.HOTSPOT_RING_POSITIONS.size()):
		var ring_mesh := MeshInstance3D.new()
		ring_mesh.name = "HotspotRing%d" % i
		var quad := QuadMesh.new()
		quad.size = Vector2(1.36, 1.36)
		quad.orientation = PlaneMesh.FACE_Y
		ring_mesh.mesh = quad
		ring_mesh.position = OtomeTerraceConfig.HOTSPOT_RING_POSITIONS[i]
		ring_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var rmat := ShaderMaterial.new()
		rmat.shader = ring_shader
		rmat.set_shader_parameter("ring_color", Color(0.95, 0.74, 0.66, 0.85))
		rmat.set_shader_parameter("highlight_boost", 0.0)
		ring_mesh.material_override = rmat
		_hotspot_rings_root.add_child(ring_mesh)
		_ring_mats.append(rmat)


func _setup_ambient_particles() -> void:
	if _blossom_particles == null:
		return
	_blossom_particles.position = Vector3(-0.6, 2.8, -0.8)
	_blossom_particles.amount = 38
	_blossom_particles.lifetime = 5.5
	_blossom_particles.preprocess = 2.0
	_blossom_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var proc_mat := ParticleProcessMaterial.new()
	proc_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc_mat.emission_box_extents = Vector3(5.2, 1.4, 4.0)
	proc_mat.direction = Vector3(0.45, -1.0, 0.25)
	proc_mat.spread = 28.0
	proc_mat.initial_velocity_min = 0.28
	proc_mat.initial_velocity_max = 0.62
	proc_mat.gravity = Vector3(0.18, -0.22, 0.08)
	proc_mat.scale_min = 0.75
	proc_mat.scale_max = 1.35
	_blossom_particles.process_material = proc_mat

	var petal_quad := QuadMesh.new()
	petal_quad.size = Vector2(0.065, 0.042)
	var pmat := StandardMaterial3D.new()
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pmat.albedo_color = Color(1.0, 0.84, 0.89, 0.88)
	pmat.roughness = 0.6
	petal_quad.material = pmat
	_blossom_particles.draw_pass_1 = petal_quad


func _configure_particle_tint(tint: Color, emission_energy: float) -> void:
	if _blossom_particles == null or _blossom_particles.draw_pass_1 == null:
		return
	var quad: QuadMesh = _blossom_particles.draw_pass_1 as QuadMesh
	if quad == null or not (quad.material is StandardMaterial3D):
		return
	var pmat: StandardMaterial3D = quad.material as StandardMaterial3D
	pmat.albedo_color = Color(tint.r, tint.g, tint.b, 0.90)
	pmat.emission_enabled = emission_energy > 0.01
	pmat.emission = tint
	pmat.emission_energy_multiplier = emission_energy
#endregion
