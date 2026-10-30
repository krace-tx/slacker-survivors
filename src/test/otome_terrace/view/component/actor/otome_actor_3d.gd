@tool
class_name OtomeActor3D
extends CharacterBody3D

## 乙女向男主「陆星野」2.5D 角色组件（支持 `@tool` 编辑器 `.tscn` 实时预览 + 运行期 [SpinePool] 四层 Mix-and-Match 换装 + 3D 动态投射阴影）。[br]
##
## [b]核心特性：[/b][br]
## 1. 打开 `.tscn` 即可在 Godot 编辑器 3D 视口直接查看完整的 `Rev2D -> Spine 4.2` 角色立绘与 3D 地面实时剪影阴影；[br]
## 2. 支持 `default + outfit/* + expr/* + prop/*` 四层皮肤无损实时热切；[br]
## 3. 内置 `WASD` 自由漫步与鼠标点击地面/热点自动寻路走近（到达后触发 [signal walk_target_reached]）。

#region Signals
## 当点击地面或热点触发的自动漫步抵达目标点时发出。
signal walk_target_reached(pending_hotspot_id: int)
#endregion

#region Exports
@export_group("Spine & Standee 3D")
@export var skeleton_data: Resource = null:
	set(value):
		skeleton_data = value
		_notify_editor_preview_dirty()

@export var viewport_size: Vector2i = Vector2i(640, 840):
	set(value):
		viewport_size = value
		_notify_editor_preview_dirty()

@export var ground_offset_y: float = 352.0:
	set(value):
		ground_offset_y = value
		_notify_editor_preview_dirty()

@export var pixel_size_3d: float = 0.0024:
	set(value):
		pixel_size_3d = value
		_notify_editor_preview_dirty()

@export var standee_tilt_deg: float = -14.0:
	set(value):
		standee_tilt_deg = value
		_notify_editor_preview_dirty()

@export_group("Default Otome Appearance")
@export_enum("outfit/cardigan", "outfit/barista", "outfit/trench") var default_outfit_skin: String = "outfit/cardigan":
	set(value):
		default_outfit_skin = value
		_notify_editor_preview_dirty()

@export_enum("expr/gentle", "expr/happy", "expr/blush") var default_expr_skin: String = "expr/gentle":
	set(value):
		default_expr_skin = value
		_notify_editor_preview_dirty()

@export_enum("prop/none", "prop/coffee_cup", "prop/poetry_book", "prop/flower_sprig") var default_prop_skin: String = "prop/none":
	set(value):
		default_prop_skin = value
		_notify_editor_preview_dirty()

@export var editor_preview_anim: String = "idle":
	set(value):
		editor_preview_anim = value
		_notify_editor_preview_dirty()
#endregion

#region Node Refs & Private State
@onready var _body_collider: CollisionShape3D = %BodyCollider as CollisionShape3D
@onready var _spine_viewport: SubViewport = %SpineViewport as SubViewport
@onready var _spine_root: Node2D = %SpineRoot as Node2D
@onready var _visual_pivot: Node3D = %VisualPivot as Node3D
@onready var _character_sprite: Sprite3D = %CharacterSprite3D as Sprite3D
@onready var _contact_shadow: MeshInstance3D = %ContactShadow as MeshInstance3D

var _spine_ctrl: SpineController = null
var _active_anim: String = ""
var _facing_right: bool = true
var _has_walk_target: bool = false
var _walk_target_pos: Vector3 = Vector3.ZERO
var _pending_hotspot_id: int = OtomeTerraceConfig.HotspotId.NONE
var _interaction_loop_anim: String = ""
var _one_shot_remaining_sec: float = 0.0
var _skin_tween: Tween = null
var _flip_tween: Tween = null
var _standee_shader_mat: ShaderMaterial = null
#endregion


#region Lifecycle
func _ready() -> void:
	_ensure_body_collider_shape()
	_configure_viewport_and_sprite()
	_setup_contact_shadow_material()
	if Engine.is_editor_hint():
		_refresh_editor_preview()
		return

	_dispose_editor_preview_node()
	_ensure_runtime_mounted_fallback.call_deferred()


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		release_spine()
#endregion


#region Public Mount & Skin API
## 从场景级 [SpinePool] 借出 [SpineController] 挂载至内部 [SubViewport]。
func mount_from_pool(pool: SpinePool, skel_res: Resource) -> void:
	_dispose_editor_preview_node()
	release_spine()
	if pool == null or skel_res == null or _spine_root == null:
		return
	var acq_res: Result = pool.acquire(skel_res, _spine_root, Vector2.ZERO)
	if acq_res.is_err():
		mount_standalone(skel_res)
		return
	_spine_ctrl = acq_res.value as SpineController
	_post_mount_init()


## 独立创建并挂载 [SpineController]（单场景直接运行时的兜底挂载）。
func mount_standalone(skel_res: Resource) -> void:
	_dispose_editor_preview_node()
	release_spine()
	if skel_res == null or _spine_root == null:
		return
	var create_res: Result = SpineController.create(skel_res)
	if create_res.is_err():
		return
	_spine_ctrl = create_res.value as SpineController
	if _spine_ctrl != null and _spine_ctrl.is_valid():
		_spine_root.add_child(_spine_ctrl.node)
		_spine_ctrl.set_transform_2d(Vector2.ZERO)
	_post_mount_init()


## 归还或释放内部持有的 [SpineController]。
func release_spine() -> void:
	if _spine_ctrl != null:
		_spine_ctrl.release()
		_spine_ctrl = null
	_active_anim = ""


## 实时组合热切男主「服饰 + 表情 + 手持道具」多层皮肤。
func apply_otome_skins(
	outfit_skin: String,
	expr_skin: String,
	prop_skin: String,
	animate_pop: bool = true
) -> void:
	var changed_any: bool = (
		default_outfit_skin != outfit_skin
		or default_expr_skin != expr_skin
		or default_prop_skin != prop_skin
	)
	default_outfit_skin = outfit_skin
	default_expr_skin = expr_skin
	default_prop_skin = prop_skin

	if Engine.is_editor_hint():
		_refresh_editor_preview()
		return
	if _spine_ctrl == null or not _spine_ctrl.is_valid():
		return

	_apply_combined_skins_to_sprite_node(_spine_ctrl.node, _spine_ctrl.get_skeleton_data())
	_spine_ctrl.step(0.0)

	if animate_pop and changed_any and _visual_pivot != null and is_inside_tree():
		if _skin_tween != null and _skin_tween.is_valid():
			_skin_tween.kill()
		_visual_pivot.scale = Vector3(1.05, 0.96, 1.0)
		_skin_tween = create_tween()
		_skin_tween.tween_property(_visual_pivot, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
#endregion


#region Public Navigation & Animation API
## 设置点击地面或点击热点的自动漫步目标点。
func set_walk_target(target_pos: Vector3, hotspot_id: int = OtomeTerraceConfig.HotspotId.NONE) -> void:
	_walk_target_pos = target_pos
	_pending_hotspot_id = hotspot_id
	_has_walk_target = true
	_interaction_loop_anim = ""
	_one_shot_remaining_sec = 0.0


## 取消自动漫步目标。
func clear_walk_target() -> void:
	_has_walk_target = false
	_pending_hotspot_id = OtomeTerraceConfig.HotspotId.NONE


## 进入热点专属循环互动动作（如品咖 `interact_coffee`、读诗 `interact_book`、迎风 `interact_breeze`）。
func play_interaction_loop(anim_name: String, face_right: bool = true) -> void:
	_has_walk_target = false
	_pending_hotspot_id = OtomeTerraceConfig.HotspotId.NONE
	_one_shot_remaining_sec = 0.0
	_interaction_loop_anim = anim_name
	set_facing_right(face_right, false)
	_play_anim_if_needed(anim_name, true)


## 停止热点循环互动动作并平滑回到自然待机呼吸。
func stop_interaction_loop() -> void:
	_interaction_loop_anim = ""
	if _one_shot_remaining_sec <= 0.0:
		_play_anim_if_needed("idle", true)


## 播放一次温柔挥手问候动作，结束后自动回到待机。
func play_greeting_once() -> void:
	_has_walk_target = false
	_interaction_loop_anim = ""
	_one_shot_remaining_sec = 1.55
	if _spine_ctrl != null and _spine_ctrl.is_valid():
		_spine_ctrl.play("interact_greet", false, 0, 1.0, 0.12).queue("idle", true)
		_active_anim = "idle"


## 设置男主左右朝向（平滑微缩放翻转，保留双向 3D 投射阴影）。
func set_facing_right(face_right: bool, immediate: bool = false) -> void:
	if _facing_right == face_right and not immediate:
		return
	_facing_right = face_right
	if _standee_shader_mat != null:
		_standee_shader_mat.set_shader_parameter("flip_h", not _facing_right)
		if _character_sprite != null:
			_character_sprite.flip_h = false
	elif _character_sprite != null:
		_character_sprite.flip_h = not _facing_right
	if not immediate and _visual_pivot != null and is_inside_tree() and not Engine.is_editor_hint():
		if _flip_tween != null and _flip_tween.is_valid():
			_flip_tween.kill()
		_visual_pivot.scale = Vector3(0.90, 1.02, 1.0)
		_flip_tween = create_tween()
		_flip_tween.tween_property(_visual_pivot, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## 推进一帧 3D 庭院漫步物理移动与动画状态切换；若玩家主动输入方向键移动则返回 `true`。
func step_actor_motion(delta: float, manual_input_dir: Vector2) -> bool:
	if Engine.is_editor_hint():
		return false

	if _one_shot_remaining_sec > 0.0:
		_one_shot_remaining_sec = maxf(0.0, _one_shot_remaining_sec - delta)

	var desired_dir := Vector2.ZERO
	var manual_moving: bool = manual_input_dir.length_squared() > 0.001

	if manual_moving:
		_has_walk_target = false
		_pending_hotspot_id = OtomeTerraceConfig.HotspotId.NONE
		_interaction_loop_anim = ""
		_one_shot_remaining_sec = 0.0
		desired_dir = manual_input_dir.normalized()
	elif _has_walk_target:
		var to_target := Vector2(_walk_target_pos.x - global_position.x, _walk_target_pos.z - global_position.z)
		var dist: float = to_target.length()
		if dist <= OtomeTerraceConfig.AUTO_WALK_STOP_DIST:
			global_position.x = _walk_target_pos.x
			global_position.z = _walk_target_pos.z
			velocity.x = 0.0
			velocity.z = 0.0
			var arrived_spot: int = _pending_hotspot_id
			_has_walk_target = false
			_pending_hotspot_id = OtomeTerraceConfig.HotspotId.NONE
			walk_target_reached.emit(arrived_spot)
		else:
			desired_dir = to_target / dist

	var target_vx: float = desired_dir.x * OtomeTerraceConfig.WALK_SPEED
	var target_vz: float = desired_dir.y * OtomeTerraceConfig.WALK_SPEED
	var blend: float = 1.0 - exp(-OtomeTerraceConfig.MOVE_ACCEL * delta)
	velocity.x = lerpf(velocity.x, target_vx, blend)
	velocity.z = lerpf(velocity.z, target_vz, blend)

	if not is_on_floor():
		velocity.y -= OtomeTerraceConfig.GRAVITY * delta
	else:
		velocity.y = 0.0

	if absf(desired_dir.x) > 0.08:
		set_facing_right(desired_dir.x > 0.0, false)

	move_and_slide()
	_clamp_and_settle_deck_height(delta)
	_update_ground_contact_shadow()
	_update_locomotion_animation()
	return manual_moving
#endregion


#region Editor Preview & Internal Helpers
func _notify_editor_preview_dirty() -> void:
	if not Engine.is_editor_hint() or not is_node_ready():
		return
	_configure_viewport_and_sprite()
	_refresh_editor_preview()


func _refresh_editor_preview() -> void:
	if _spine_root == null:
		return
	var preview_node: Node2D = _spine_root.get_node_or_null("EditorPreviewSpine") as Node2D
	if preview_node == null and ClassDB.can_instantiate(&"SpineSprite"):
		preview_node = ClassDB.instantiate(&"SpineSprite") as Node2D
		if preview_node != null:
			preview_node.name = "EditorPreviewSpine"
			_spine_root.add_child(preview_node)
	if preview_node == null:
		return

	preview_node.position = Vector2.ZERO
	preview_node.scale = Vector2.ONE
	var skel_res: Resource = skeleton_data
	if skel_res == null:
		skel_res = load(OtomeTerraceConfig.HERO_SPINE_DATA_PATH) as Resource
	if skel_res == null:
		return

	if preview_node.get("skeleton_data_res") != skel_res:
		preview_node.set("skeleton_data_res", skel_res)
	preview_node.set("preview_skin", "default")
	preview_node.set("preview_animation", editor_preview_anim if not editor_preview_anim.is_empty() else "idle")
	preview_node.set("preview_frame", false)
	_apply_editor_skin_deferred.call_deferred(preview_node, skel_res)


func _apply_editor_skin_deferred(preview_node: Node2D, skel_res: Resource) -> void:
	if preview_node == null or not is_instance_valid(preview_node):
		return
	_apply_combined_skins_to_sprite_node(preview_node, skel_res)
	if preview_node.has_method("update_skeleton"):
		preview_node.call("update_skeleton", 0.0)


func _dispose_editor_preview_node() -> void:
	if _spine_root == null:
		return
	var preview_node: Node = _spine_root.get_node_or_null("EditorPreviewSpine")
	if preview_node != null:
		_spine_root.remove_child(preview_node)
		preview_node.free()


func _ensure_runtime_mounted_fallback() -> void:
	if Engine.is_editor_hint() or _spine_ctrl != null:
		return
	var skel_res: Resource = skeleton_data if skeleton_data != null else (load(OtomeTerraceConfig.HERO_SPINE_DATA_PATH) as Resource)
	if skel_res != null:
		mount_standalone(skel_res)


func _ensure_body_collider_shape() -> void:
	if _body_collider == null or _body_collider.shape != null:
		return
	var cap := CapsuleShape3D.new()
	cap.radius = 0.30
	cap.height = 1.72
	_body_collider.shape = cap
	_body_collider.position = Vector3(0.0, 0.86, 0.0)


func _configure_viewport_and_sprite() -> void:
	if _spine_viewport != null:
		_spine_viewport.size = viewport_size
		_spine_viewport.transparent_bg = true
		_spine_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_spine_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR

	if _visual_pivot != null:
		_visual_pivot.rotation_degrees = Vector3(standee_tilt_deg, 0.0, 0.0)

	if _character_sprite != null:
		var vp_tex: ViewportTexture = _spine_viewport.get_texture() if _spine_viewport != null else null
		if vp_tex != null:
			_character_sprite.texture = vp_tex
		_character_sprite.centered = true
		_character_sprite.offset = Vector2(0.0, ground_offset_y)
		_character_sprite.pixel_size = pixel_size_3d
		_character_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
		_character_sprite.flip_h = not _facing_right
		_character_sprite.shaded = true
		_character_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		_character_sprite.alpha_scissor_threshold = 0.38
		_character_sprite.double_sided = true
		_character_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		_character_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		if _standee_shader_mat == null:
			var shd: Shader = load(OtomeTerraceConfig.ACTOR_STANDEE_SHADER_PATH) as Shader
			if shd != null:
				_standee_shader_mat = ShaderMaterial.new()
				_standee_shader_mat.shader = shd
		if _standee_shader_mat != null and vp_tex != null:
			_character_sprite.flip_h = false
			_standee_shader_mat.set_shader_parameter("standee_tex", vp_tex)
			_standee_shader_mat.set_shader_parameter("flip_h", not _facing_right)
			_character_sprite.material_override = _standee_shader_mat


func _post_mount_init() -> void:
	if _spine_ctrl == null or not _spine_ctrl.is_valid():
		return
	_apply_combined_skins_to_sprite_node(_spine_ctrl.node, _spine_ctrl.get_skeleton_data())
	_play_anim_if_needed("idle", true)
	_spine_ctrl.step(0.016)


func _apply_combined_skins_to_sprite_node(sprite_node: Node2D, skel_data: Resource) -> void:
	if sprite_node == null or skel_data == null or not sprite_node.has_method("new_skin"):
		return
	var skel_var: Variant = sprite_node.call("get_skeleton")
	if not (skel_var is Object):
		return
	var skeleton: Object = skel_var as Object

	var combined_var: Variant = sprite_node.call("new_skin", "active_otome_loadout")
	if not (combined_var is Object):
		return
	var combined_skin: Object = combined_var as Object

	_append_named_skin(combined_skin, skel_data, "default")
	_append_named_skin(combined_skin, skel_data, default_outfit_skin)
	_append_named_skin(combined_skin, skel_data, default_expr_skin)
	_append_named_skin(combined_skin, skel_data, default_prop_skin)

	skeleton.call("set_skin", combined_skin)
	if skeleton.has_method("set_slots_to_setup_pose"):
		skeleton.call("set_slots_to_setup_pose")

	var anim_state_var: Variant = sprite_node.call("get_animation_state")
	if anim_state_var is Object and (anim_state_var as Object).has_method("apply"):
		(anim_state_var as Object).call("apply", skeleton)


func _append_named_skin(combined_skin: Object, skel_data: Resource, skin_name: String) -> void:
	if skin_name.is_empty() or not skel_data.has_method("find_skin"):
		return
	var part_skin: Variant = skel_data.call("find_skin", skin_name)
	if part_skin is Object and combined_skin.has_method("add_skin"):
		combined_skin.call("add_skin", part_skin)


func _update_locomotion_animation() -> void:
	if _one_shot_remaining_sec > 0.0:
		return
	var horiz_speed: float = Vector2(velocity.x, velocity.z).length()
	if horiz_speed > 0.18:
		_play_anim_if_needed("walk", true)
	elif not _interaction_loop_anim.is_empty():
		_play_anim_if_needed(_interaction_loop_anim, true)
	else:
		_play_anim_if_needed("idle", true)


func _play_anim_if_needed(anim_name: String, loop: bool) -> void:
	if _spine_ctrl == null or not _spine_ctrl.is_valid():
		return
	if _active_anim == anim_name and loop:
		return
	_active_anim = anim_name
	_spine_ctrl.play(anim_name, loop, 0, 1.0, 0.15)


func _clamp_and_settle_deck_height(delta: float) -> void:
	global_position.x = clampf(global_position.x, OtomeTerraceConfig.TERRACE_MIN_X, OtomeTerraceConfig.TERRACE_MAX_X)
	global_position.z = clampf(global_position.z, OtomeTerraceConfig.TERRACE_MIN_Z, OtomeTerraceConfig.TERRACE_MAX_Z)
	var target_floor_y: float = OtomeTerraceConfig.estimate_ground_height(global_position)
	if global_position.y < target_floor_y or absf(global_position.y - target_floor_y) < 0.24:
		global_position.y = lerpf(global_position.y, target_floor_y, 1.0 - exp(-18.0 * delta))
		velocity.y = 0.0


func _update_ground_contact_shadow() -> void:
	if _contact_shadow == null:
		return
	var floor_y: float = OtomeTerraceConfig.estimate_ground_height(global_position)
	_contact_shadow.global_position = Vector3(global_position.x, floor_y + 0.012, global_position.z)


func _setup_contact_shadow_material() -> void:
	if _contact_shadow == null:
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(0.92, 0.64)
	quad.orientation = PlaneMesh.FACE_Y
	_contact_shadow.mesh = quad
	_contact_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y: int in range(64):
		var ny: float = (float(y) - 31.5) / 31.5
		for x: int in range(64):
			var nx: float = (float(x) - 31.5) / 31.5
			var r: float = sqrt(nx * nx + ny * ny)
			var alpha: float = pow(clampf(1.0 - r, 0.0, 1.0), 1.9) * 0.34
			img.set_pixel(x, y, Color(0.16, 0.11, 0.10, alpha))
	var tex := ImageTexture.create_from_image(img)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = tex
	_contact_shadow.material_override = mat
#endregion
