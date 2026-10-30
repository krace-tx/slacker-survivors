class_name CozyStandeeActor3D
extends Node3D

## 2.5D 二次元立牌角色组件（支持 正/侧/背 3 视图 × 待机/走路 6 行图集、相机相对朝向迟滞解算、相位连续切向与双向 3D 阴影）。

enum FacingView {
	FRONT = 0, ## 正视图（面向相机 / S 键朝下）
	SIDE = 1,  ## 侧视图（横向移动 / A·D 键与斜向移动，配合 flip_h 兼容左右）
	BACK = 2,  ## 背视图（背对相机 / W 键朝上）
}

enum AnimState {
	IDLE = 0,
	WALK = 1,
}

const _STANDEE_SHADER_PATH: String = "res://src/test/cozy_studio/assets/shaders/shd_cozy_studio_standee_2d.gdshader"
const _BLOB_SHADOW_TEX_PATH: String = "res://src/test/cozy_studio/assets/textures/fx_cozy_studio_blob_shadow.png"

## 扇区切换施密特迟滞阈值（防止斜 45° 走动或旋转相机临界角时在正/侧/背之间高频闪烁）
const _SECTOR_ENTER_BIAS: float = 0.14
const _SECTOR_EXIT_BIAS: float = -0.06

@export var sprite_texture: Texture2D = null
@export var sheet_hframes: int = 1
@export var sheet_vframes: int = 1
@export var idle_fps: float = 3.4
@export var walk_fps: float = 7.6
@export var world_height: float = 1.48
@export var camera_yaw_deg: float = 37.0
@export var standee_tilt_deg: float = -22.0
@export var idle_phase_offset: float = 0.0

@onready var _visual_pivot: Node3D = %VisualPivot as Node3D
@onready var _standee_mesh: MeshInstance3D = %StandeeMesh as MeshInstance3D
@onready var _contact_shadow: MeshInstance3D = %ContactShadow as MeshInstance3D

var _shader_mat: ShaderMaterial = null
var _shadow_mat: StandardMaterial3D = null
var _facing_view: FacingView = FacingView.FRONT
var _anim_state: AnimState = AnimState.IDLE
var _world_facing_dir: Vector3 = Vector3(sin(deg_to_rad(37.0)), 0.0, cos(deg_to_rad(37.0)))
var _frame_accum: float = 0.0
var _current_col: int = 0
var _current_frame_idx: int = -1
var _step_cushion: float = 0.0
var _idle_sway_time: float = 0.0
var _facing_left: bool = false
var _flip_tween: Tween = null


func _ready() -> void:
	_setup_standee_geometry()
	_setup_contact_shadow()
	set_camera_alignment(camera_yaw_deg, standee_tilt_deg)


func setup_character(tex: Texture2D, char_height: float = 1.48) -> void:
	setup_character_sheet(tex, 1, 1, char_height)


func setup_character_sheet(
	tex: Texture2D,
	hframes: int = 1,
	vframes: int = 1,
	char_height: float = 1.62
) -> void:
	sprite_texture = tex
	sheet_hframes = maxi(1, hframes)
	sheet_vframes = maxi(1, vframes)
	world_height = char_height
	_current_col = 0
	_current_frame_idx = -1
	_frame_accum = 0.0
	if is_node_ready():
		_setup_standee_geometry()
		_resolve_camera_relative_view()
		_refresh_sheet_frame()


## 设置角色在 3D 世界空间中的真实水平朝向，并自动解算相对于当前镜头的 正/侧/背 视图与左右翻转。
func set_world_facing_direction(world_dir: Vector3) -> void:
	var flat := Vector3(world_dir.x, 0.0, world_dir.z)
	if flat.length_squared() < 0.0001:
		return
	_world_facing_dir = flat.normalized()
	_resolve_camera_relative_view()


func get_facing_view() -> FacingView:
	return _facing_view


func is_facing_left() -> bool:
	return _facing_left


func get_facing_view_label() -> String:
	match _facing_view:
		FacingView.FRONT:
			return "正视图 (Front)"
		FacingView.SIDE:
			return "侧视图·左 (Side-L)" if _facing_left else "侧视图·右 (Side-R)"
		FacingView.BACK:
			return "背视图 (Back)"
	return "正视图"


## 推进 3 视图序列帧状态机与落地微缓冲（6 行图集走完整 3 视图 × 待机/走路；单帧立牌保留轻柔呼吸）。
func tick_visual(delta: float, is_moving: bool, speed_ratio: float = 1.0) -> void:
	_idle_sway_time += delta * 2.2
	if _visual_pivot == null:
		return

	if sheet_vframes >= 2 and sheet_hframes >= 2:
		_tick_sheet_animation(delta, is_moving, speed_ratio)
	else:
		_tick_single_sprite_breath(delta, is_moving)


func _tick_sheet_animation(delta: float, is_moving: bool, speed_ratio: float) -> void:
	var next_state: AnimState = AnimState.WALK if is_moving else AnimState.IDLE
	if next_state != _anim_state:
		_anim_state = next_state
		_frame_accum = 0.0
		_current_col = 0
		if _anim_state == AnimState.WALK:
			_step_cushion = 0.65

	if _anim_state == AnimState.WALK:
		var synced_fps: float = walk_fps * clampf(speed_ratio, 0.65, 1.45)
		_frame_accum += delta * synced_fps
		if _frame_accum >= 1.0:
			var step_advance: int = int(floor(_frame_accum))
			_frame_accum -= float(step_advance)
			var prev_col: int = _current_col
			_current_col = (_current_col + step_advance) % sheet_hframes
			if _current_col != prev_col and (_current_col % 2 == 0):
				_step_cushion = 1.0
	else:
		_frame_accum += delta * idle_fps
		if _frame_accum >= 1.0:
			var idle_advance: int = int(floor(_frame_accum))
			_frame_accum -= float(idle_advance)
			_current_col = (_current_col + idle_advance) % sheet_hframes

	_refresh_sheet_frame()

	_step_cushion = lerpf(_step_cushion, 0.0, 1.0 - exp(-14.0 * delta))
	var squash_y: float = 1.0 - 0.022 * _step_cushion
	_visual_pivot.position.y = 0.0
	_visual_pivot.rotation_degrees.z = lerpf(
		_visual_pivot.rotation_degrees.z,
		0.0,
		1.0 - exp(-10.0 * delta)
	)
	_visual_pivot.scale.y = squash_y
	if _contact_shadow != null:
		var is_passing_lift: bool = (_anim_state == AnimState.WALK) and (_current_col % 2 == 1)
		var target_sh: float = 0.90 if is_passing_lift else (1.03 if _step_cushion > 0.3 else 1.0)
		var cur_sh: float = lerpf(_contact_shadow.scale.x, target_sh, 1.0 - exp(-12.0 * delta))
		_contact_shadow.scale = Vector3(cur_sh, 1.0, cur_sh)


func _refresh_sheet_frame() -> void:
	var row: int = 0
	if sheet_vframes >= 6:
		# 6 行标准 3 视图契约：0=FrontIdle, 1=FrontWalk, 2=SideIdle, 3=SideWalk, 4=BackIdle, 5=BackWalk
		row = int(_facing_view) * 2 + int(_anim_state)
	elif sheet_vframes >= 2:
		row = int(_anim_state)
	row = clampi(row, 0, maxi(0, sheet_vframes - 1))
	_apply_frame_index(row * sheet_hframes + (_current_col % maxi(1, sheet_hframes)))


func _tick_single_sprite_breath(delta: float, is_moving: bool) -> void:
	if is_moving:
		var hop: float = absf(sin(_idle_sway_time * 4.0))
		_visual_pivot.position.y = hop * 0.06
		_visual_pivot.rotation_degrees.z = sin(_idle_sway_time * 4.0) * 2.5
	else:
		var breath: float = sin(_idle_sway_time + idle_phase_offset)
		_visual_pivot.position.y = lerpf(_visual_pivot.position.y, 0.0, 1.0 - exp(-10.0 * delta))
		_visual_pivot.rotation_degrees.z = lerpf(
			_visual_pivot.rotation_degrees.z,
			breath * 0.7,
			1.0 - exp(-8.0 * delta)
		)
		_visual_pivot.scale.y = 1.0 + breath * 0.012


func _apply_frame_index(frame_idx: int) -> void:
	if _current_frame_idx == frame_idx:
		return
	_current_frame_idx = frame_idx
	if _shader_mat != null:
		_shader_mat.set_shader_parameter(&"frame_index", _current_frame_idx)


## 根据 `world_facing_dir` 与相机水平基向量的点积，解算当前应显示的 正/侧/背 视图与左右翻转（保留步态相位不重置！）。
func _resolve_camera_relative_view() -> void:
	if sheet_vframes < 6:
		return

	var yaw_rad: float = deg_to_rad(camera_yaw_deg)
	var cam_right := Vector3(cos(yaw_rad), 0.0, -sin(yaw_rad))
	var cam_front := Vector3(sin(yaw_rad), 0.0, cos(yaw_rad))

	var local_x: float = _world_facing_dir.dot(cam_right)
	var local_z: float = _world_facing_dir.dot(cam_front)

	var prev_view: FacingView = _facing_view
	var next_view: FacingView = prev_view

	var abs_x: float = absf(local_x)
	var abs_z: float = absf(local_z)
	var threshold_bias: float = (
		_SECTOR_EXIT_BIAS
		if (prev_view == FacingView.FRONT or prev_view == FacingView.BACK)
		else _SECTOR_ENTER_BIAS
	)

	if abs_z > abs_x + threshold_bias:
		next_view = FacingView.FRONT if local_z >= 0.0 else FacingView.BACK
	else:
		next_view = FacingView.SIDE

	# 正视图与背视图保持原始不翻转构图（发旋呆毛/衣襟左右自然一致），仅在侧视图下根据 local_x 控制左右翻转
	var next_flip_left: bool = _facing_left
	if next_view == FacingView.SIDE:
		if abs_x > 0.08:
			next_flip_left = local_x < 0.0
	else:
		next_flip_left = false

	var view_changed: bool = next_view != prev_view
	var flip_changed: bool = next_flip_left != _facing_left

	_facing_view = next_view
	if view_changed or flip_changed:
		_apply_view_or_flip_transition(next_flip_left, flip_changed and not view_changed)


func _apply_view_or_flip_transition(target_flip_left: bool, full_paper_flip: bool) -> void:
	_facing_left = target_flip_left
	if _visual_pivot == null:
		if _shader_mat != null:
			_shader_mat.set_shader_parameter(&"flip_h", _facing_left)
		_refresh_sheet_frame()
		return

	if _flip_tween != null and _flip_tween.is_valid():
		_flip_tween.kill()

	if full_paper_flip:
		# 同为侧视图左右掉头：纸片立牌 180° 轻快窄折翻面
		_flip_tween = create_tween()
		_flip_tween.tween_property(_visual_pivot, "scale:x", 0.10, 0.055).set_trans(Tween.TRANS_SINE)
		_flip_tween.tween_callback(func() -> void:
			if _shader_mat != null:
				_shader_mat.set_shader_parameter(&"flip_h", _facing_left)
			_refresh_sheet_frame()
		)
		_flip_tween.tween_property(_visual_pivot, "scale:x", 1.0, 0.075).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		# 正 <-> 侧 <-> 背 90° 切面：立即切换对应视图行（保持脚步相位连续）并附带微弱 Q 弹过渡
		if _shader_mat != null:
			_shader_mat.set_shader_parameter(&"flip_h", _facing_left)
		_refresh_sheet_frame()
		_visual_pivot.scale.x = 0.86
		_flip_tween = create_tween()
		_flip_tween.tween_property(_visual_pivot, "scale:x", 1.0, 0.085).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 手动设置左右翻转（供单帧/2行模式兼容调用）。
func set_facing_left(face_left: bool) -> void:
	if _facing_left == face_left:
		return
	_apply_view_or_flip_transition(face_left, true)


## 一键切换 2.5D 光影融合层开关（用于 A/B 教学对比）。
func set_glue_layer_enabled(enabled: bool) -> void:
	if _contact_shadow != null:
		_contact_shadow.visible = enabled
	if _standee_mesh != null:
		_standee_mesh.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if enabled
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
	if _shader_mat != null:
		_shader_mat.set_shader_parameter(&"normal_up_bias", 0.78 if enabled else 0.0)
		_shader_mat.set_shader_parameter(&"self_warmth", 0.18 if enabled else 0.0)
		_shader_mat.set_shader_parameter(&"backlight_strength", 0.28 if enabled else 0.0)


## 视平面平行（View-Plane Parallelism）：对齐相机水平偏航角，并同步重算相机相对 3 视图（支持 Q/E 原地转镜头切面！）。
func set_camera_alignment(yaw_deg: float, tilt_deg: float) -> void:
	camera_yaw_deg = yaw_deg
	standee_tilt_deg = tilt_deg
	rotation_degrees.y = yaw_deg
	if _visual_pivot != null:
		_visual_pivot.rotation_degrees.x = tilt_deg
	_resolve_camera_relative_view()


func _setup_standee_geometry() -> void:
	if _standee_mesh == null or sprite_texture == null:
		return
	var tex_size: Vector2 = sprite_texture.get_size()
	var cell_w: float = tex_size.x / float(maxi(1, sheet_hframes))
	var cell_h: float = tex_size.y / float(maxi(1, sheet_vframes))
	var aspect: float = cell_w / maxf(1.0, cell_h)
	var quad_w: float = world_height * aspect

	var quad := QuadMesh.new()
	quad.size = Vector2(quad_w, world_height)
	quad.center_offset = Vector3(0.0, world_height * 0.5, 0.0)
	_standee_mesh.mesh = quad
	_standee_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	var shd: Shader = load(_STANDEE_SHADER_PATH) as Shader
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = shd
	_shader_mat.set_shader_parameter(&"albedo_texture", sprite_texture)
	_shader_mat.set_shader_parameter(&"sheet_grid", Vector2i(maxi(1, sheet_hframes), maxi(1, sheet_vframes)))
	_shader_mat.set_shader_parameter(&"frame_index", maxi(0, _current_frame_idx))
	_shader_mat.set_shader_parameter(&"flip_h", _facing_left)
	_standee_mesh.material_override = _shader_mat


func _setup_contact_shadow() -> void:
	if _contact_shadow == null:
		return
	var sh_quad := QuadMesh.new()
	sh_quad.size = Vector2(0.72, 0.52)
	sh_quad.orientation = PlaneMesh.FACE_Y
	_contact_shadow.mesh = sh_quad
	_contact_shadow.position = Vector3(0.0, 0.016, 0.0)
	_contact_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var blob_tex: Texture2D = load(_BLOB_SHADOW_TEX_PATH) as Texture2D
	_shadow_mat = StandardMaterial3D.new()
	_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_mat.albedo_texture = blob_tex
	_shadow_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.85)
	_shadow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_contact_shadow.material_override = _shadow_mat
