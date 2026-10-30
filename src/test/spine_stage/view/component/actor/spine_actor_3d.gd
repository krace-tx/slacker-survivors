@tool
class_name SpineActor3D
extends CharacterBody3D

## 「方案 B」核心 2.5D 角色载体（支持 `@tool` 编辑器 `.tscn` 实时骨骼与 3D 阴影预览 + 运行期 [SpinePool] 池化托管）。[br]
##
## [b]核心管线原理：[/b][br]
## 1. [b]编辑器 `.tscn` 即时可视化（`@tool`）[/b]：内部 `%SpineViewport/%SpineRoot/%EditorPreviewSpine` 与 `local_to_scene` 的 [ViewportTexture] 让角色、换装皮肤及 3D 地面投射阴影在打开 `.tscn` 时直接可见并可在检查器实时切换预览；[br]
## 2. [b]运行期池化与实时 Mix-and-Match 换装[/b]：运行期自动移除编辑器预览节点并由 [SpinePool] 借出 [SpineController]，通过 `new_skin()` 动态叠加 `default + weapon/* + outfit/*` 多层皮肤；[br]
## 3. [b]3D 光影与动态剪影阴影[/b]：[Sprite3D] 开启 `shaded = true`、`alpha_cut = ALPHA_CUT_DISCARD` 与双面阴影投射，使 2D 角色与武器在 3D 石板地面和台阶上实时投射真实剪影阴影。

#region Signals
signal attack_hit_frame_reached(combo_step: int)
#endregion

#region Exports
@export_group("Spine & Viewport")
@export var skeleton_data: Resource = null:
	set(value):
		skeleton_data = value
		_notify_editor_preview_dirty()

@export var viewport_size: Vector2i = Vector2i(512, 512):
	set(value):
		viewport_size = value
		_notify_editor_preview_dirty()

@export var ground_offset_y: float = 212.0:
	set(value):
		ground_offset_y = value
		_notify_editor_preview_dirty()

@export var pixel_size_3d: float = 0.0052:
	set(value):
		pixel_size_3d = value
		_notify_editor_preview_dirty()

@export var standee_tilt_deg: float = -18.0:
	set(value):
		standee_tilt_deg = value
		_notify_editor_preview_dirty()

@export var initial_facing_right: bool = true:
	set(value):
		initial_facing_right = value
		_facing_right = value
		_notify_editor_preview_dirty()

@export var is_dummy_actor: bool = false:
	set(value):
		is_dummy_actor = value
		_notify_editor_preview_dirty()

@export_group("Default Loadout & Preview")
@export_enum("weapon/sword", "weapon/scythe", "weapon/hammer") var default_weapon_skin: String = "weapon/sword":
	set(value):
		default_weapon_skin = value
		_notify_editor_preview_dirty()

@export_enum("outfit/ranger", "outfit/royal", "outfit/abyss") var default_outfit_skin: String = "outfit/royal":
	set(value):
		default_outfit_skin = value
		_notify_editor_preview_dirty()

@export var editor_preview_anim: String = "idle":
	set(value):
		editor_preview_anim = value
		_notify_editor_preview_dirty()
#endregion

#region Private State & Node Refs
@onready var _spine_viewport: SubViewport = %SpineViewport as SubViewport
@onready var _spine_root: Node2D = %SpineRoot as Node2D
@onready var _visual_pivot: Node3D = %VisualPivot as Node3D
@onready var _character_sprite: Sprite3D = %CharacterSprite3D as Sprite3D
@onready var _contact_shadow: MeshInstance3D = %ContactShadow as MeshInstance3D

var _spine_ctrl: SpineController = null
var _active_anim: String = ""
var _facing_right: bool = true
var _attack_remaining_sec: float = 0.0
var _hit_frame_pending: bool = false
var _hit_frame_delay_sec: float = 0.0
var _combo_step: int = 1
var _combo_reset_sec: float = 0.0
var _hit_flash_sec: float = 0.0
var _knockback_vel: Vector3 = Vector3.ZERO
var _flip_tween: Tween = null
var _equip_tween: Tween = null
#endregion


#region Lifecycle
func _ready() -> void:
	_facing_right = initial_facing_right
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


#region Public Setup & Skin Hot-Swap API
## 通过场景级 [SpinePool] 借出已预热的 [SpineController] 挂载至内部 [SubViewport]。
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


## 独立挂载骨骼数据资源（单预制体 `F6` 独立运行或未注入对象池时的兜底路径）。
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


## 释放或归还持有的 [SpineController] 租约。
func release_spine() -> void:
	if _spine_ctrl != null:
		_spine_ctrl.release()
		_spine_ctrl = null
	_active_anim = ""


## 实时组合切换武器皮肤与服饰套装皮肤（不中断当前跑动/跳跃/挥砍动画轨迹）。
func apply_loadout_skins(weapon_skin: String, outfit_skin: String, animate_pop: bool = true) -> void:
	default_weapon_skin = weapon_skin
	default_outfit_skin = outfit_skin
	if Engine.is_editor_hint():
		_refresh_editor_preview()
		return
	if _spine_ctrl == null or not _spine_ctrl.is_valid():
		return

	_apply_combined_skins_to_sprite_node(_spine_ctrl.node, _spine_ctrl.get_skeleton_data())
	_spine_ctrl.step(0.0)

	if animate_pop and _visual_pivot != null and is_inside_tree():
		if _equip_tween != null and _equip_tween.is_valid():
			_equip_tween.kill()
		_visual_pivot.scale = Vector3(1.10 * _current_flip_scale_sign(), 0.92, 1.0)
		_equip_tween = create_tween()
		_equip_tween.tween_property(
			_visual_pivot,
			"scale",
			Vector3(_current_flip_scale_sign(), 1.0, 1.0),
			0.14
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
#endregion


#region Public Gameplay Motion & Combat API
## 当前角色是否朝向屏幕右侧（+X）。
func is_facing_right() -> bool:
	return _facing_right


## 当前角色是否正处于近战挥砍动作窗口内。
func is_attacking() -> bool:
	return _attack_remaining_sec > 0.0


## 获取当前连击段数（1 或 2）。
func get_combo_step() -> int:
	return _combo_step


## 设置水平朝向并执行轻快纸片翻面过渡。
func set_facing_right(face_right: bool, instant: bool = false) -> void:
	if _facing_right == face_right and not instant:
		return
	_facing_right = face_right
	if _character_sprite == null or _visual_pivot == null:
		return
	if instant or not is_inside_tree() or Engine.is_editor_hint():
		_character_sprite.flip_h = not _facing_right
		_visual_pivot.scale.x = 1.0
		return

	if _flip_tween != null and _flip_tween.is_valid():
		_flip_tween.kill()
	_flip_tween = create_tween()
	_flip_tween.tween_property(_visual_pivot, "scale:x", 0.14, 0.048).set_trans(Tween.TRANS_SINE)
	_flip_tween.tween_callback(func() -> void:
		if _character_sprite != null:
			_character_sprite.flip_h = not _facing_right
	)
	_flip_tween.tween_property(_visual_pivot, "scale:x", 1.0, 0.068).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 推进主角一帧 3D 物理运动、重力跳跃与骨骼状态机切换。
func step_hero_motion(delta: float, move_input_xz: Vector2, move_speed: float, want_jump: bool) -> String:
	if _combo_reset_sec > 0.0:
		_combo_reset_sec = maxf(0.0, _combo_reset_sec - delta)
		if _combo_reset_sec <= 0.0:
			_combo_step = 1

	if _attack_remaining_sec > 0.0:
		_attack_remaining_sec = maxf(0.0, _attack_remaining_sec - delta)
		if _hit_frame_pending:
			_hit_frame_delay_sec -= delta
			if _hit_frame_delay_sec <= 0.0:
				_hit_frame_pending = false
				attack_hit_frame_reached.emit(_combo_step)

	var on_floor_now: bool = is_on_floor()
	if not on_floor_now:
		velocity.y -= SpineStageConfig.GRAVITY * delta
	elif want_jump:
		velocity.y = SpineStageConfig.JUMP_VELOCITY
		on_floor_now = false
		if _attack_remaining_sec <= 0.0:
			_play_anim_if_needed("jump", false)

	var target_vx: float = move_input_xz.x * move_speed
	var target_vz: float = move_input_xz.y * move_speed
	if _attack_remaining_sec > 0.16:
		var lunge_dir: float = 1.0 if _facing_right else -1.0
		target_vx = target_vx * 0.45 + lunge_dir * SpineStageConfig.ATTACK_LUNGE_SPEED
		target_vz *= 0.45

	var accel: float = 20.0 if on_floor_now else 11.0
	velocity.x = lerpf(velocity.x, target_vx, 1.0 - exp(-accel * delta))
	velocity.z = lerpf(velocity.z, target_vz, 1.0 - exp(-accel * delta))

	if absf(move_input_xz.x) > 0.08 and _attack_remaining_sec <= 0.12:
		set_facing_right(move_input_xz.x > 0.0)

	move_and_slide()
	_clamp_within_courtyard()
	_update_ground_contact_shadow()
	_tick_hit_flash(delta)

	var is_moving_horiz: bool = (velocity.x * velocity.x + velocity.z * velocity.z) > 0.22
	if _attack_remaining_sec > 0.0:
		return "ATTACK %d · 挥砍连段" % _combo_step
	if not is_on_floor():
		if _active_anim != "jump":
			_play_anim_if_needed("jump", false)
		return "JUMP · 3D 腾空投射长影"
	if is_moving_horiz:
		_play_anim_if_needed("run", true)
		return "RUN · IK 奔跑 + 披风物理"
	_play_anim_if_needed("idle", true)
	return "IDLE · 待机呼吸"


## 触发一次近战二段连击挥砍（返回触发的连击段数，冷却中返回 0）。
func trigger_attack() -> int:
	if _attack_remaining_sec > 0.14:
		return 0
	if _combo_reset_sec > 0.0 and _active_anim == "attack_1":
		_combo_step = 2
	elif _combo_reset_sec <= 0.0:
		_combo_step = 1
	else:
		_combo_step = 2 if _combo_step == 1 else 1

	var anim_id: String = "attack_1" if _combo_step == 1 else "attack_2"
	if _spine_ctrl != null and _spine_ctrl.is_valid():
		_spine_ctrl.play(anim_id, false, 0, 1.0, 0.06)
		_active_anim = anim_id
	_attack_remaining_sec = 0.39
	_combo_reset_sec = 0.95
	_hit_frame_pending = true
	_hit_frame_delay_sec = 0.14
	return _combo_step


## 推进训练木偶一帧受击阻尼回弹与接地阴影。
func step_dummy_motion(delta: float, home_pos: Vector3) -> void:
	if not is_on_floor():
		velocity.y -= SpineStageConfig.GRAVITY * delta
	var to_home: Vector3 = home_pos - global_position
	to_home.y = 0.0
	_knockback_vel = _knockback_vel.lerp(Vector3.ZERO, 1.0 - exp(-10.0 * delta))
	velocity.x = _knockback_vel.x + to_home.x * 7.5
	velocity.z = _knockback_vel.z + to_home.z * 7.5
	move_and_slide()
	_update_ground_contact_shadow()
	_tick_hit_flash(delta)


## 对训练木偶施加受击动画、闪白高亮与击退冲量。
func apply_dummy_hit_reaction(from_pos: Vector3) -> void:
	var push_dir: Vector3 = global_position - from_pos
	push_dir.y = 0.0
	if push_dir.length_squared() < 0.001:
		push_dir = Vector3.RIGHT
	else:
		push_dir = push_dir.normalized()
	_knockback_vel = push_dir * 3.6
	_hit_flash_sec = 0.13
	if _character_sprite != null:
		_character_sprite.modulate = Color(2.2, 1.85, 1.65, 1.0)
	if _spine_ctrl != null and _spine_ctrl.is_valid():
		_spine_ctrl.play("hit", false, 0, 1.0, 0.03).queue("idle", true)
		_active_anim = "idle"
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
		var fallback_path: String = (
			SpineStageConfig.DUMMY_SPINE_DATA_PATH
			if is_dummy_actor
			else SpineStageConfig.HERO_SPINE_DATA_PATH
		)
		skel_res = load(fallback_path) as Resource
	if skel_res == null:
		return

	if preview_node.get("skeleton_data_res") != skel_res:
		preview_node.set("skeleton_data_res", skel_res)
	preview_node.set("preview_skin", "default")
	preview_node.set("preview_animation", editor_preview_anim if not editor_preview_anim.is_empty() else "idle")
	preview_node.set("preview_frame", false)

	if not is_dummy_actor:
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
	if skeleton_data != null:
		mount_standalone(skeleton_data)


func _configure_viewport_and_sprite() -> void:
	if _spine_viewport != null:
		_spine_viewport.size = viewport_size
		_spine_viewport.transparent_bg = true
		_spine_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_spine_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR

	if _visual_pivot != null:
		_visual_pivot.rotation_degrees = Vector3(standee_tilt_deg, 0.0, 0.0)

	if _character_sprite != null:
		if _spine_viewport != null:
			_character_sprite.texture = _spine_viewport.get_texture()
		_character_sprite.centered = true
		_character_sprite.offset = Vector2(0.0, ground_offset_y)
		_character_sprite.pixel_size = pixel_size_3d
		_character_sprite.flip_h = not _facing_right
		_character_sprite.shaded = true
		_character_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		_character_sprite.alpha_scissor_threshold = 0.42
		_character_sprite.double_sided = true
		_character_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		_character_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


func _post_mount_init() -> void:
	if _spine_ctrl == null or not _spine_ctrl.is_valid():
		return
	if not is_dummy_actor:
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

	var combined_var: Variant = sprite_node.call("new_skin", "active_loadout")
	if not (combined_var is Object):
		return
	var combined_skin: Object = combined_var as Object

	_append_named_skin(combined_skin, skel_data, "default")
	_append_named_skin(combined_skin, skel_data, default_weapon_skin)
	_append_named_skin(combined_skin, skel_data, default_outfit_skin)

	skeleton.call("set_skin", combined_skin)
	if skeleton.has_method("set_slots_to_setup_pose"):
		skeleton.call("set_slots_to_setup_pose")

	var anim_state_var: Variant = sprite_node.call("get_animation_state")
	if anim_state_var is Object and (anim_state_var as Object).has_method("apply"):
		(anim_state_var as Object).call("apply", skeleton)


func _play_anim_if_needed(anim_name: String, loop: bool) -> void:
	if _spine_ctrl == null or not _spine_ctrl.is_valid():
		return
	if _active_anim == anim_name and loop:
		return
	_active_anim = anim_name
	_spine_ctrl.play(anim_name, loop, 0, 1.0, 0.10)


func _append_named_skin(combined_skin: Object, skel_data: Resource, skin_name: String) -> void:
	if skin_name.is_empty() or not skel_data.has_method("find_skin"):
		return
	var part_skin: Variant = skel_data.call("find_skin", skin_name)
	if part_skin is Object and combined_skin.has_method("add_skin"):
		combined_skin.call("add_skin", part_skin)


func _current_flip_scale_sign() -> float:
	return 1.0


func _clamp_within_courtyard() -> void:
	global_position.x = clampf(global_position.x, -SpineStageConfig.ARENA_LIMIT_X, SpineStageConfig.ARENA_LIMIT_X)
	global_position.z = clampf(global_position.z, -SpineStageConfig.ARENA_LIMIT_Z, SpineStageConfig.ARENA_LIMIT_Z)
	if global_position.y < -2.0:
		global_position.y = 0.0
		velocity.y = 0.0


func _update_ground_contact_shadow() -> void:
	if _contact_shadow == null:
		return
	var floor_y: float = _estimate_floor_height(global_position)
	var air_h: float = maxf(0.0, global_position.y - floor_y)
	_contact_shadow.global_position = Vector3(global_position.x, floor_y + 0.015, global_position.z)
	var shrink: float = lerpf(1.0, 0.48, clampf(air_h / 1.65, 0.0, 1.0))
	_contact_shadow.scale = Vector3(shrink, 1.0, shrink * 0.72)


func _estimate_floor_height(pos: Vector3) -> float:
	if pos.z <= -2.35 and absf(pos.x) <= 3.85 and pos.y >= 0.34:
		return 0.44
	return 0.0


func _tick_hit_flash(delta: float) -> void:
	if _hit_flash_sec <= 0.0:
		return
	_hit_flash_sec = maxf(0.0, _hit_flash_sec - delta)
	if _hit_flash_sec <= 0.0 and _character_sprite != null:
		_character_sprite.modulate = Color.WHITE


func _setup_contact_shadow_material() -> void:
	if _contact_shadow == null:
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(1.15, 1.15)
	quad.orientation = PlaneMesh.FACE_Y
	_contact_shadow.mesh = quad
	_contact_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y: int in range(64):
		var ny: float = (float(y) - 31.5) / 31.5
		for x: int in range(64):
			var nx: float = (float(x) - 31.5) / 31.5
			var r: float = sqrt(nx * nx + ny * ny)
			var alpha: float = pow(clampf(1.0 - r, 0.0, 1.0), 1.85) * 0.46
			img.set_pixel(x, y, Color(0.04, 0.05, 0.09, alpha))
	var tex := ImageTexture.create_from_image(img)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = tex
	_contact_shadow.material_override = mat
#endregion
