class_name CozyStudioStage3D
extends Node3D

## 3D 温馨二次元画室舞台组件（封装 3D 赛璐璐水彩材质、4 大可交互家具邻近高亮、意式咖啡机微震蒸汽、转椅/沙发受迫回弹与橘猫 Q 弹呼噜动画）。

const _ANIME_ENV_SHADER_PATH: String = "res://src/test/cozy_studio/assets/shaders/shd_cozy_studio_anime_env.gdshader"
const _SUNBEAM_SHADER_PATH: String = "res://src/test/cozy_studio/assets/shaders/shd_cozy_studio_sunbeam.gdshader"
const _SUN_MOTE_TEX_PATH: String = "res://src/test/cozy_studio/assets/textures/fx_cozy_studio_sun_mote.png"
const _STEAM_PUFF_TEX_PATH: String = "res://src/test/cozy_studio/assets/textures/fx_cozy_studio_steam_puff.svg"

class _AnimeSurfaceSlot extends RefCounted:
	var mesh_inst: MeshInstance3D = null
	var surface_idx: int = 0
	var toon_mat: ShaderMaterial = null
	var spot_tag: int = 0

class _RestMeshTransform extends RefCounted:
	var node: Node3D = null
	var rest_xf: Transform3D = Transform3D.IDENTITY

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
@onready var _coffee_steam_particles: GPUParticles3D = %CoffeeSteamParticles as GPUParticles3D

var _env: Environment = null
var _sunbeam_mat: ShaderMaterial = null
var _anime_surface_slots: Array[_AnimeSurfaceSlot] = []
var _window_glass_mats: Array[StandardMaterial3D] = []
var _spot_materials: Dictionary = {}

var _espresso_meshes: Array[_RestMeshTransform] = []
var _cat_meshes: Array[_RestMeshTransform] = []
var _pouf_meshes: Array[_RestMeshTransform] = []
var _sofa_cushion_meshes: Array[_RestMeshTransform] = []
var _chair_swivel_pivot: Node3D = null
var _chair_rest_xf: Transform3D = Transform3D.IDENTITY

var _north_cutaway_nodes: Array[Node3D] = []
var _west_cutaway_nodes: Array[Node3D] = []
var _nw_corner_pillar: Node3D = null
var _north_wall_visible: bool = true
var _west_wall_visible: bool = true
var _current_mood: CozyStudioState.LightingMood = CozyStudioState.LightingMood.AFTERNOON_SUN
var _current_glue_on: bool = true

var _highlighted_spot: CozyStudioState.InteractSpotId = CozyStudioState.InteractSpotId.NONE
var _highlight_weights: Dictionary = {
	CozyStudioState.InteractSpotId.COFFEE_BAR: 0.0,
	CozyStudioState.InteractSpotId.WORKSTATION_CHAIR: 0.0,
	CozyStudioState.InteractSpotId.LOUNGE_SOFA: 0.0,
	CozyStudioState.InteractSpotId.SLEEPING_CAT: 0.0,
}

var _stage_time: float = 0.0
var _brew_timer: float = 0.0
var _steam_emit_timer: float = 0.0
var _cat_purr_timer: float = 0.0
var _chair_bounce_timer: float = 0.0
var _sofa_bounce_timer: float = 0.0
var _chair_occupied: bool = false
var _base_coffee_light_energy: float = 0.95


func _ready() -> void:
	_prepare_room_anime_materials_and_groups()
	_setup_environment()
	_setup_sunbeams()
	_setup_dust_particles()
	_setup_coffee_steam_particles()
	apply_lighting_mood(CozyStudioState.LightingMood.AFTERNOON_SUN, true)


func get_stage_environment() -> Environment:
	return _env


## 设置当前邻近高亮的 3D 可交互家具点位（平滑驱动暖金呼吸边缘高光）。
func set_highlighted_spot(spot: CozyStudioState.InteractSpotId) -> void:
	_highlighted_spot = spot


## 触发右后咖啡吧台「意式咖啡机萃茶微震 + 双头喷嘴奶白蒸汽 + 吊灯暖光微涌」。
func trigger_brew_latte_reaction() -> void:
	_brew_timer = 1.05
	_steam_emit_timer = 1.85
	if _coffee_steam_particles != null:
		_coffee_steam_particles.restart()
		_coffee_steam_particles.emitting = true


## 触发窗边针织蒲团「3D 酣睡橘猫 Q 弹挤压舒展 + 幸福呼噜微颤 + 蒲团联动轻压」。
func trigger_pet_cat_reaction() -> void:
	_cat_purr_timer = 0.92


## 通知 3D 座椅或贵妃沙发角色落座/起身，播放坐垫受迫下陷回弹并在转椅入座时开启悠闲摇椅微旋。
func notify_seat_state_changed(spot: CozyStudioState.InteractSpotId, occupied: bool) -> void:
	if spot == CozyStudioState.InteractSpotId.WORKSTATION_CHAIR:
		_chair_occupied = occupied
		_chair_bounce_timer = 0.42
	elif spot == CozyStudioState.InteractSpotId.LOUNGE_SOFA:
		_sofa_bounce_timer = 0.46


## 动态箱庭剖面墙消隐（支持 Q / E 360° 环绕镜头：当相机转到北后墙或西高窗墙背侧时自动隐去遮挡墙体，如同《蔚蓝档案》咖啡厅与箱庭模拟视角）。
func update_cutaway_walls(yaw_deg: float) -> void:
	var yaw_rad: float = deg_to_rad(yaw_deg)
	var show_north: bool = cos(yaw_rad) >= 0.08
	var show_west: bool = sin(yaw_rad) >= 0.08

	if show_north != _north_wall_visible:
		_north_wall_visible = show_north
		for n_node: Node3D in _north_cutaway_nodes:
			if n_node != null:
				n_node.visible = show_north

	if show_west != _west_wall_visible:
		_west_wall_visible = show_west
		for w_node: Node3D in _west_cutaway_nodes:
			if w_node != null:
				w_node.visible = show_west
		if _sunbeam_root != null:
			_sunbeam_root.visible = (
				_current_glue_on
				and (_current_mood == CozyStudioState.LightingMood.AFTERNOON_SUN)
				and _west_wall_visible
			)

	if _nw_corner_pillar != null:
		_nw_corner_pillar.visible = (_north_wall_visible and _west_wall_visible)


## 每帧推进 4 大交互点高光过渡、橘猫熟睡呼吸/呼噜回弹、咖啡机萃茶微震与座椅受迫弹性动画。
func tick_stage(delta: float) -> void:
	_stage_time += delta

	# 1. 邻近可交互家具暖金边缘高光平滑过渡
	for key_variant: Variant in _highlight_weights.keys():
		var spot_key: CozyStudioState.InteractSpotId = key_variant as CozyStudioState.InteractSpotId
		var target_w: float = 1.0 if spot_key == _highlighted_spot else 0.0
		var cur_w: float = float(_highlight_weights[spot_key])
		var next_w: float = lerpf(cur_w, target_w, 1.0 - exp(-11.0 * delta))
		if absf(next_w - cur_w) > 0.0005:
			_highlight_weights[spot_key] = next_w
			var mats: Array = _spot_materials.get(spot_key, []) as Array
			for mat_obj: Variant in mats:
				var smat: ShaderMaterial = mat_obj as ShaderMaterial
				if smat != null:
					smat.set_shader_parameter(&"interact_highlight", next_w)

	# 2. 意式咖啡机萃茶高频微震 + 蒸汽自动收尾
	if _steam_emit_timer > 0.0:
		_steam_emit_timer = maxf(0.0, _steam_emit_timer - delta)
		if _steam_emit_timer <= 0.0 and _coffee_steam_particles != null:
			_coffee_steam_particles.emitting = false

	if _brew_timer > 0.0:
		_brew_timer = maxf(0.0, _brew_timer - delta)
		var env_a: float = sin((_brew_timer / 1.05) * PI)
		var buzz_x: float = sin(_stage_time * 62.0) * 0.009 * env_a
		var buzz_y: float = absf(sin(_stage_time * 44.0)) * 0.007 * env_a
		var pump_s: float = 1.0 + sin(_stage_time * 36.0) * 0.024 * env_a
		_apply_group_pivot_transform(
			_espresso_meshes,
			Vector3(3.50, 1.04, -2.60),
			Basis.from_scale(Vector3(pump_s, 2.0 - pump_s, pump_s)),
			Vector3(buzz_x, buzz_y, 0.0)
		)
		if _coffee_bar_light != null:
			_coffee_bar_light.light_energy = _base_coffee_light_energy + 0.55 * env_a
		if _brew_timer <= 0.0:
			_reset_group_transforms(_espresso_meshes)
			if _coffee_bar_light != null:
				_coffee_bar_light.light_energy = _base_coffee_light_energy

	# 3. 窗边蒲团酣睡橘猫：平时轻柔睡肚呼吸；被撸时 Q 弹挤压 -> 蹿起舒展 -> 幸福呼噜微颤！
	var cat_pivot := Vector3(-3.08, 0.31, 1.05)
	if _cat_purr_timer > 0.0:
		_cat_purr_timer = maxf(0.0, _cat_purr_timer - delta)
		var p: float = 1.0 - (_cat_purr_timer / 0.92)
		var sx: float = 1.0
		var sy: float = 1.0
		var lift_y: float = 0.0
		var tilt_z: float = 0.0
		if p < 0.22:
			# 阶段 A：软乎乎下压扁平
			var k: float = sin((p / 0.22) * PI * 0.5)
			sx = lerpf(1.0, 1.20, k)
			sy = lerpf(1.0, 0.76, k)
		elif p < 0.50:
			# 阶段 B：Q 弹高高回弹蹿起
			var k2: float = (p - 0.22) / 0.28
			var arc: float = sin(k2 * PI)
			sx = lerpf(1.20, 0.91, sin(minf(1.0, k2 * 1.4) * PI * 0.5))
			sy = 1.0 + 0.22 * arc
			lift_y = 0.065 * arc
		else:
			# 阶段 C：呼噜噜高频幸福轻颤与歪头蹭手
			var decay: float = (1.0 - p) / 0.50
			var purr: float = sin(_stage_time * 48.0) * 0.045 * decay
			sx = 1.0 + purr
			sy = 1.0 - purr * 0.8
			tilt_z = sin(_stage_time * 18.0) * deg_to_rad(5.5) * decay

		var cat_basis: Basis = Basis(Vector3(0.0, 0.0, 1.0), tilt_z) * Basis.from_scale(Vector3(sx, sy, sx))
		_apply_group_pivot_transform(_cat_meshes, cat_pivot, cat_basis, Vector3(0.0, lift_y, 0.0))

		var pouf_squash: float = 1.0 - 0.07 * sin(minf(1.0, p * 2.2) * PI) * (1.0 - p)
		_apply_group_pivot_transform(
			_pouf_meshes,
			Vector3(-3.08, 0.01, 1.05),
			Basis.from_scale(Vector3(2.0 - pouf_squash, pouf_squash, 2.0 - pouf_squash)),
			Vector3.ZERO
		)
		if _cat_purr_timer <= 0.0:
			_reset_group_transforms(_pouf_meshes)
	else:
		# 橘猫安静酣睡时的慢速肚皮起伏呼吸
		var sleep_breath: float = sin(_stage_time * 2.1)
		var b_sy: float = 1.0 + sleep_breath * 0.028
		var b_sx: float = 1.0 - sleep_breath * 0.014
		_apply_group_pivot_transform(
			_cat_meshes,
			cat_pivot,
			Basis.from_scale(Vector3(b_sx, b_sy, b_sx)),
			Vector3.ZERO
		)

	# 4. 左后人体工学转椅：落座受迫回弹 + 入座摸鱼悠闲左右轻转
	if _chair_swivel_pivot != null:
		var chair_sy: float = 1.0
		var chair_drop: float = 0.0
		if _chair_bounce_timer > 0.0:
			_chair_bounce_timer = maxf(0.0, _chair_bounce_timer - delta)
			var cb: float = 1.0 - (_chair_bounce_timer / 0.42)
			var wave: float = sin(cb * PI * 2.0) * (1.0 - cb)
			chair_sy = 1.0 - 0.11 * wave
			chair_drop = -0.026 * maxf(0.0, wave)
		var swivel_rad: float = sin(_stage_time * 1.45) * deg_to_rad(6.5) if _chair_occupied else 0.0
		var cur_basis: Basis = (
			_chair_rest_xf.basis
			* Basis(Vector3.UP, swivel_rad)
			* Basis.from_scale(Vector3(2.0 - chair_sy, chair_sy, 2.0 - chair_sy))
		)
		_chair_swivel_pivot.transform = Transform3D(
			cur_basis,
			_chair_rest_xf.origin + Vector3(0.0, chair_drop, 0.0)
		)

	# 5. 右前奶油绿簇绒沙发：落座/起身柔软海绵下陷与 Q 弹回弹
	if _sofa_bounce_timer > 0.0:
		_sofa_bounce_timer = maxf(0.0, _sofa_bounce_timer - delta)
		var sb: float = 1.0 - (_sofa_bounce_timer / 0.46)
		var s_wave: float = sin(sb * PI * 2.0) * (1.0 - sb)
		var s_sy: float = 1.0 - 0.14 * s_wave
		_apply_group_pivot_transform(
			_sofa_cushion_meshes,
			Vector3(3.05, 0.18, 1.05),
			Basis.from_scale(Vector3(1.0 + 0.06 * s_wave, s_sy, 1.0 + 0.06 * s_wave)),
			Vector3(0.0, -0.024 * maxf(0.0, s_wave), 0.0)
		)
		if _sofa_bounce_timer <= 0.0:
			_reset_group_transforms(_sofa_cushion_meshes)


func _apply_group_pivot_transform(
	group: Array[_RestMeshTransform],
	pivot_local: Vector3,
	anim_basis: Basis,
	anim_offset: Vector3
) -> void:
	var pivot_xf: Transform3D = (
		Transform3D(anim_basis, pivot_local + anim_offset)
		* Transform3D(Basis.IDENTITY, -pivot_local)
	)
	for item: _RestMeshTransform in group:
		if item.node != null:
			item.node.transform = pivot_xf * item.rest_xf


func _reset_group_transforms(group: Array[_RestMeshTransform]) -> void:
	for item: _RestMeshTransform in group:
		if item.node != null:
			item.node.transform = item.rest_xf


func _classify_mesh_spot(mesh_name: String) -> CozyStudioState.InteractSpotId:
	if mesh_name.begins_with("MSH_Espresso_") or mesh_name.begins_with("MSH_CoffeeGrinder_"):
		return CozyStudioState.InteractSpotId.COFFEE_BAR
	if mesh_name.begins_with("MSH_Chair_") or mesh_name.begins_with("MSH_PenTablet_"):
		return CozyStudioState.InteractSpotId.WORKSTATION_CHAIR
	if (
		mesh_name.begins_with("MSH_Sofa_SeatCushion_")
		or mesh_name.begins_with("MSH_Sofa_BackPillow_")
		or mesh_name == "MSH_Sofa_ChaiseCushion"
		or mesh_name.begins_with("MSH_Sofa_AccentPillow_")
		or mesh_name == "MSH_Sofa_ThrowBlanket"
	):
		return CozyStudioState.InteractSpotId.LOUNGE_SOFA
	if mesh_name.begins_with("MSH_Cat_"):
		return CozyStudioState.InteractSpotId.SLEEPING_CAT
	return CozyStudioState.InteractSpotId.NONE


## 遍历高精 3D 场地网格：构建二次元赛璐璐材质，并为 4 大交互点拆分专属高亮材质槽与弹性动画组。
func _prepare_room_anime_materials_and_groups() -> void:
	_anime_surface_slots.clear()
	_window_glass_mats.clear()
	_spot_materials.clear()
	_espresso_meshes.clear()
	_cat_meshes.clear()
	_pouf_meshes.clear()
	_sofa_cushion_meshes.clear()
	_north_cutaway_nodes.clear()
	_west_cutaway_nodes.clear()
	_nw_corner_pillar = null
	_chair_swivel_pivot = null

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
		if cur is Node3D:
			var n3d: Node3D = cur as Node3D
			var nname: String = String(n3d.name)
			if nname == "PIVOT_Chair_UpperSwivel":
				_chair_swivel_pivot = n3d
				_chair_rest_xf = _chair_swivel_pivot.transform
			elif nname == "CLUSTER_Grand_Bookcase":
				_north_cutaway_nodes.append(n3d)
			elif nname == "GRP_French_Windows_And_Curtains":
				_west_cutaway_nodes.append(n3d)

		if cur is MeshInstance3D:
			var mi: MeshInstance3D = cur as MeshInstance3D
			var mname: String = String(mi.name)
			_register_anim_mesh_group(mi, mname)
			_register_cutaway_wall_mesh(mi, mname)

			if (
				mname.contains("SunlitGlass")
				or mname.contains("Curtain")
				or mname.contains("GlassCloche")
			):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

			var spot_id: CozyStudioState.InteractSpotId = _classify_mesh_spot(mname)
			if mi.mesh != null:
				var surf_count: int = mi.mesh.get_surface_count()
				for s_idx: int in range(surf_count):
					var base_mat: Material = mi.get_active_material(s_idx)
					if not (base_mat is StandardMaterial3D):
						continue
					var std_mat: StandardMaterial3D = base_mat as StandardMaterial3D
					var mat_name: String = std_mat.resource_name
					if mname.contains("SunlitGlass") and mat_name.contains("SunlitGlass"):
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

					# 以 (基础材质实例 ID, 交互点枚举) 作为复合缓存键，使每个交互家具独立响应呼吸高光而不污染同材质背景！
					var cache_key: String = "%d_%d" % [std_mat.get_instance_id(), int(spot_id)]
					var toon_mat: ShaderMaterial = null
					if mat_cache.has(cache_key):
						toon_mat = mat_cache[cache_key] as ShaderMaterial
					else:
						toon_mat = _build_toon_material_from_pbr(env_shader, std_mat, mat_name)
						mat_cache[cache_key] = toon_mat
						if spot_id != CozyStudioState.InteractSpotId.NONE:
							if not _spot_materials.has(spot_id):
								_spot_materials[spot_id] = []
							(_spot_materials[spot_id] as Array).append(toon_mat)

					var slot := _AnimeSurfaceSlot.new()
					slot.mesh_inst = mi
					slot.surface_idx = s_idx
					slot.toon_mat = toon_mat
					slot.spot_tag = int(spot_id)
					_anime_surface_slots.append(slot)

		for ch: Node in cur.get_children():
			stack.append(ch)


func _register_anim_mesh_group(mi: MeshInstance3D, mname: String) -> void:
	if mname.begins_with("MSH_Espresso_"):
		var rec := _RestMeshTransform.new()
		rec.node = mi
		rec.rest_xf = mi.transform
		_espresso_meshes.append(rec)
	elif mname.begins_with("MSH_Cat_"):
		var rec_cat := _RestMeshTransform.new()
		rec_cat.node = mi
		rec_cat.rest_xf = mi.transform
		_cat_meshes.append(rec_cat)
	elif mname.begins_with("MSH_Pouf_"):
		var rec_pouf := _RestMeshTransform.new()
		rec_pouf.node = mi
		rec_pouf.rest_xf = mi.transform
		_pouf_meshes.append(rec_pouf)
	elif (
		mname == "MSH_Sofa_SeatCushion_01"
		or mname == "MSH_Sofa_BackPillow_01"
		or mname == "MSH_Sofa_SeatCushion_02"
		or mname == "MSH_Sofa_ChaiseCushion"
		or mname == "MSH_Sofa_ThrowBlanket"
	):
		var rec_sofa := _RestMeshTransform.new()
		rec_sofa.node = mi
		rec_sofa.rest_xf = mi.transform
		_sofa_cushion_meshes.append(rec_sofa)


func _register_cutaway_wall_mesh(mi: MeshInstance3D, mname: String) -> void:
	if mname == "MSH_Pillar_CornerBL":
		_nw_corner_pillar = mi
	elif (
		mname.begins_with("MSH_Wall_Back_")
		or mname.begins_with("MSH_Loft_Rafter_")
		or mname.begins_with("MSH_Loft_Corbel_")
		or mname == "MSH_Pillar_CornerBR"
		or mname.begins_with("MSH_Corkboard_")
		or mname.begins_with("MSH_PinNote_")
		or mname.begins_with("MSH_WallClock_")
		or mname.begins_with("MSH_MenuBoard_")
	):
		_north_cutaway_nodes.append(mi)
	elif (
		mname.begins_with("MSH_Wall_Left_")
		or mname == "MSH_Pillar_CornerFL"
		or mname.begins_with("MSH_WallShelf_Left_")
		or mname.begins_with("MSH_WallShelf_Book_")
		or mname.begins_with("MSH_FramedArt_LeftWall_")
	):
		_west_cutaway_nodes.append(mi)


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

	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color("#FADFC4")
	_env.ambient_light_energy = 0.64

	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 0.98
	_env.tonemap_white = 1.28

	_env.ssao_enabled = true
	_env.ssao_radius = 0.48
	_env.ssao_intensity = 0.58
	_env.ssao_light_affect = 0.52

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


func _setup_coffee_steam_particles() -> void:
	if _coffee_steam_particles == null:
		return
	var pmat := ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pmat.emission_box_extents = Vector3(0.14, 0.03, 0.06)
	pmat.direction = Vector3(0.0, 1.0, 0.18)
	pmat.spread = 24.0
	pmat.initial_velocity_min = 0.26
	pmat.initial_velocity_max = 0.48
	pmat.gravity = Vector3(0.0, 0.16, 0.0)
	pmat.damping_min = 0.35
	pmat.damping_max = 0.65
	pmat.scale_min = 0.85
	pmat.scale_max = 1.75

	var steam_tex: Texture2D = load(_STEAM_PUFF_TEX_PATH) as Texture2D
	var quad := QuadMesh.new()
	quad.size = Vector2(0.24, 0.24)
	var s_mat := StandardMaterial3D.new()
	s_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	s_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	s_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	s_mat.albedo_texture = steam_tex
	s_mat.albedo_color = Color(1.0, 0.99, 0.95, 0.88)
	s_mat.render_priority = 3
	quad.material = s_mat

	_coffee_steam_particles.position = Vector3(3.50, 1.25, -2.42)
	_coffee_steam_particles.amount = 26
	_coffee_steam_particles.lifetime = 1.35
	_coffee_steam_particles.process_material = pmat
	_coffee_steam_particles.draw_pass_1 = quad
	_coffee_steam_particles.emitting = false


## 应用光照氛围与二次元赛璐璐背景画风开关（G 键支持实时 A/B 对比）。
func apply_lighting_mood(mood: CozyStudioState.LightingMood, glue_on: bool) -> void:
	_current_mood = mood
	_current_glue_on = glue_on
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
		_window_fill_light.light_energy = 0.55 if mood == CozyStudioState.LightingMood.AFTERNOON_SUN else 0.22

	if _desk_lamp_light != null:
		_desk_lamp_light.light_energy = 0.85 if mood == CozyStudioState.LightingMood.AFTERNOON_SUN else 1.85

	_base_coffee_light_energy = 0.95 if mood == CozyStudioState.LightingMood.AFTERNOON_SUN else 1.95
	if _coffee_bar_light != null and _brew_timer <= 0.0:
		_coffee_bar_light.light_energy = _base_coffee_light_energy

	if _sunbeam_root != null:
		_sunbeam_root.visible = (
			glue_on
			and (mood == CozyStudioState.LightingMood.AFTERNOON_SUN)
			and _west_wall_visible
		)

	if _dust_particles != null:
		_dust_particles.visible = glue_on
