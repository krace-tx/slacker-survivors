class_name SpineController
extends RefCounted

## Spine 骨骼节点强类型适配器、流式控制器与池化租约句柄（Spine Adapter, Fluent Controller & Lease Handle）。[br]
##
## [b]核心设计模式：[/b][br]
## 1. [b]适配器模式（Adapter）[/b]：将 `spine-godot` C++ 扩展节点（`SpineSprite`）的反射调用封装为 100% 强类型 GDScript 接口，未编译插件时安全降级不崩溃；[br]
## 2. [b]流式接口模式（Fluent Interface）[/b]：支持 [code]controller.set_skin("v2").set_time_scale(1.2).play("attack").queue("idle", true)[/code] 链式编排；[br]
## 3. [b]租约句柄模式（Lease Handle）[/b]：由 [SpinePool] 借出的控制器内置弱引用池绑定，调用 [method release] 即可一键归还对象池，无需手动管理底层节点回收。

#region Constants
const SPINE_SPRITE_CLASS: StringName = &"SpineSprite"
const UPDATE_MODE_PROCESS: int = 0
const UPDATE_MODE_PHYSICS: int = 1
const UPDATE_MODE_MANUAL: int = 2
const _DEFAULT_SAFETY_TIMEOUT_MARGIN_SEC: float = 0.25
const _FALLBACK_ANIM_DURATION_SEC: float = 2.0
#endregion

#region State
## 受控的底层 `SpineSprite` 节点引用（只读）。
var node: Node2D:
	get:
		return _sprite

var _sprite: Node2D = null
var _pool_ref: WeakRef = null
#endregion


#region Constructors & Factory Methods
func _init(sprite_node: Node = null, owning_pool: RefCounted = null) -> void:
	if sprite_node is Node2D and is_spine_sprite(sprite_node):
		_sprite = sprite_node as Node2D
	if owning_pool != null:
		_pool_ref = weakref(owning_pool)


## 包装场景中已有的 `SpineSprite` 节点为 [SpineController] 强类型控制器。
static func wrap(sprite_node: Node) -> Result:
	if not is_spine_sprite(sprite_node):
		return Result.err_code("Spine.InvalidNode", "Target node is not a valid SpineSprite.")
	return Result.ok(SpineController.new(sprite_node))


## 根据 `SpineSkeletonDataResource`（或 `res://` 路径）新建 `SpineSprite` 节点并返回其 [SpineController] 包装。
static func create(skeleton_res_or_path: Variant) -> Result:
	if not is_spine_supported():
		return Result.err_code("Spine.Unsupported", "SpineSprite C++ module is not available in this build.")

	var skel_res := resolve_skeleton_resource(skeleton_res_or_path)
	if skel_res == null:
		return Result.err_code("Spine.InvalidResource", "Failed to resolve SpineSkeletonDataResource.")

	var raw_node: Node = ClassDB.instantiate(SPINE_SPRITE_CLASS) as Node
	if raw_node == null or not (raw_node is Node2D):
		if raw_node != null:
			NodeUtils.safe_free(raw_node)
		return Result.err_code("Spine.InstantiateFailed", "ClassDB failed to instantiate SpineSprite.")

	raw_node.set("skeleton_data_res", skel_res)
	return Result.ok(SpineController.new(raw_node))
#endregion


#region 1. Static Capability & Resource Introspection (静态能力与资源自省)
## 检查当前引擎构建是否已编译集成 `spine-godot`（支持实例化 `SpineSprite`）。
static func is_spine_supported() -> bool:
	return ClassDB.can_instantiate(SPINE_SPRITE_CLASS)


## 判断给定对象是否为有效的 `SpineSprite` 节点实例。
static func is_spine_sprite(target: Object) -> bool:
	return target != null and is_instance_valid(target) and target.get_class() == String(SPINE_SPRITE_CLASS)


## 解析骨骼数据资源（接受已加载的 [Resource] 实例或存在的 `res://` 路径）。
static func resolve_skeleton_resource(skeleton_res_or_path: Variant) -> Resource:
	if skeleton_res_or_path is Resource:
		return skeleton_res_or_path as Resource
	if skeleton_res_or_path is String or skeleton_res_or_path is StringName:
		var path := String(skeleton_res_or_path)
		if not path.is_empty() and ResourceLoader.exists(path):
			return ResourceLoader.load(path)
	return null
#endregion


#region 2. Instance Validity & Metadata Queries (实例状态与元数据查询)
## 当前控制器持有的 `SpineSprite` 节点是否有效。
func is_valid() -> bool:
	return _sprite != null and is_instance_valid(_sprite)


## 获取底层绑定的 `SpineSkeletonDataResource`。
func get_skeleton_data() -> Resource:
	if not is_valid():
		return null
	var res: Variant = _sprite.get("skeleton_data_res")
	return res as Resource if res is Resource else null


## 获取该骨骼包含的全部动画名称列表。
func get_animation_names() -> PackedStringArray:
	var names := PackedStringArray()
	var skel_data := get_skeleton_data()
	if skel_data == null or not skel_data.has_method("get_animations"):
		return names

	var anims: Variant = skel_data.call("get_animations")
	if anims is Array:
		for anim in anims:
			if anim is Object and anim.has_method("get_name"):
				var n := str(anim.call("get_name"))
				if not n.is_empty():
					names.append(n)
			elif anim is String or anim is StringName:
				names.append(String(anim))
	return names


## 检查是否存在指定名称的动画。
func has_animation(anim_name: String) -> bool:
	if anim_name.is_empty() or not is_valid():
		return false
	var skel_data := get_skeleton_data()
	if skel_data != null and skel_data.has_method("find_animation"):
		return skel_data.call("find_animation", anim_name) != null
	return anim_name in get_animation_names()


## 智能解析可用动画名：若 [param preferred_anim] 存在则采用；若为空或不存在，自动回退该骨骼的第 1 个可用动画名。
func resolve_animation_name(preferred_anim: String = "") -> String:
	if not preferred_anim.is_empty() and has_animation(preferred_anim):
		return preferred_anim
	var all_names := get_animation_names()
	if not all_names.is_empty():
		return all_names[0]
	return preferred_anim


## 获取指定动画的时长（秒）；若未找到则返回 `0.0`。
func get_animation_duration(anim_name: String) -> float:
	if anim_name.is_empty() or not is_valid():
		return 0.0
	var skel_data := get_skeleton_data()
	if skel_data == null or not skel_data.has_method("find_animation"):
		return 0.0
	var anim_obj: Variant = skel_data.call("find_animation", anim_name)
	if anim_obj is Object and anim_obj.has_method("get_duration"):
		return maxf(0.0, float(anim_obj.call("get_duration")))
	return 0.0


## 获取该骨骼包含的全部皮肤（Skin）名称列表。
func get_skin_names() -> PackedStringArray:
	var names := PackedStringArray()
	var skel_data := get_skeleton_data()
	if skel_data == null or not skel_data.has_method("get_skins"):
		return names
	var skins: Variant = skel_data.call("get_skins")
	if skins is Array:
		for skin in skins:
			if skin is Object and skin.has_method("get_name"):
				names.append(str(skin.call("get_name")))
	return names


## 检查是否存在指定名称的皮肤（Skin）。
func has_skin(skin_name: String) -> bool:
	if skin_name.is_empty() or not is_valid():
		return false
	var skel_data := get_skeleton_data()
	if skel_data != null and skel_data.has_method("find_skin"):
		return skel_data.call("find_skin", skin_name) != null
	return skin_name in get_skin_names()
#endregion


#region 3. Fluent Playback, Multi-Track & Skin Control (流式多轨道动画与换肤控制)
## 在指定轨道播放动画（流式返回 `self`；需要校验结果时可调用 [method try_play]）。
func play(
	anim_name: String = "",
	loop: bool = false,
	track_index: int = 0,
	time_scale: float = 1.0,
	mix_duration: float = -1.0
) -> SpineController:
	try_play(anim_name, loop, track_index, time_scale, mix_duration)
	return self


## 在指定轨道播放动画并返回 [Result]（包含底层 `SpineTrackEntry`）。
func try_play(
	anim_name: String = "",
	loop: bool = false,
	track_index: int = 0,
	time_scale: float = 1.0,
	mix_duration: float = -1.0
) -> Result:
	if not is_valid():
		return Result.err_code("Spine.InvalidNode", "SpineController holds an invalid SpineSprite.")

	var resolved_anim := resolve_animation_name(anim_name)
	if resolved_anim.is_empty() or not has_animation(resolved_anim):
		return Result.err_code(
			"Spine.AnimationNotFound",
			"Animation '%s' not found on SpineSprite '%s'." % [anim_name, _sprite.name]
		)

	var anim_state := _get_animation_state()
	if anim_state == null or not anim_state.has_method("set_animation"):
		return Result.err_code("Spine.InvalidState", "SpineAnimationState is unavailable.")

	var track_entry: Variant = anim_state.call("set_animation", resolved_anim, loop, maxi(0, track_index))
	if track_entry is Object:
		if not is_equal_approx(time_scale, 1.0) and track_entry.has_method("set_time_scale"):
			track_entry.call("set_time_scale", maxf(0.0, time_scale))
		if mix_duration >= 0.0 and track_entry.has_method("set_mix_duration"):
			track_entry.call("set_mix_duration", mix_duration)

	return Result.ok(track_entry)


## 将动画压入指定轨道的后续播放队列（流式返回 `self`）。
func queue(
	anim_name: String,
	loop: bool = false,
	delay_sec: float = 0.0,
	track_index: int = 0
) -> SpineController:
	if not is_valid() or not has_animation(anim_name):
		return self
	var anim_state := _get_animation_state()
	if anim_state != null and anim_state.has_method("add_animation"):
		anim_state.call("add_animation", anim_name, delay_sec, loop, maxi(0, track_index))
	return self


## 平滑停止并混出指定轨道上的动画（流式返回 `self`）。
func stop_track(track_index: int = 0, mix_duration: float = 0.1) -> SpineController:
	var anim_state := _get_animation_state()
	if anim_state == null:
		return self
	if mix_duration > 0.0 and anim_state.has_method("set_empty_animation"):
		anim_state.call("set_empty_animation", maxi(0, track_index), mix_duration)
	elif anim_state.has_method("clear_track"):
		anim_state.call("clear_track", maxi(0, track_index))
	return self


## 清空全部动画轨道并可选恢复初始装配姿态（Setup Pose）。
func clear_tracks(restore_setup_pose: bool = true) -> SpineController:
	var anim_state := _get_animation_state()
	if anim_state != null and anim_state.has_method("clear_tracks"):
		anim_state.call("clear_tracks")
	if restore_setup_pose:
		reset_pose()
	return self


## 设置全局动画时间缩放倍率（流式返回 `self`）。
func set_time_scale(scale_factor: float) -> SpineController:
	var anim_state := _get_animation_state()
	if anim_state != null and anim_state.has_method("set_time_scale"):
		anim_state.call("set_time_scale", maxf(0.0, scale_factor))
	return self


## 切换皮肤（Skin）并自动重置插槽附件（流式返回 `self`）。
func set_skin(skin_name: String, reset_slots: bool = true) -> SpineController:
	if not is_valid() or not has_skin(skin_name):
		return self
	var skeleton := _get_skeleton()
	if skeleton != null and skeleton.has_method("set_skin_by_name"):
		skeleton.call("set_skin_by_name", skin_name)
		if reset_slots and skeleton.has_method("set_slots_to_setup_pose"):
			skeleton.call("set_slots_to_setup_pose")
		step(0.0)
	return self


## 将骨骼与插槽完全重置回初始装配姿态（Setup Pose）。
func reset_pose() -> SpineController:
	var skeleton := _get_skeleton()
	if skeleton != null and skeleton.has_method("set_to_setup_pose"):
		skeleton.call("set_to_setup_pose")
	step(0.0)
	return self


## 设置骨骼更新驱动模式（`manual = true` 时关闭引擎每帧重算，交由 [SpinePool] 分频错峰步进）。
func set_manual_update(manual: bool) -> SpineController:
	if is_valid():
		_sprite.set("update_mode", UPDATE_MODE_MANUAL if manual else UPDATE_MODE_PROCESS)
	return self


## 手动推进一次骨骼动画与蒙皮网格计算。
func step(delta_sec: float = 0.0) -> SpineController:
	if is_valid() and _sprite.has_method("update_skeleton"):
		_sprite.call("update_skeleton", maxf(0.0, delta_sec))
	return self


## 遍历当前骨骼的所有动画依次执行首帧采样，提前在 C++ 层激活全部蒙皮变形缓冲（Deform Buffer）与混合材质。
func prewarm_all_animations() -> SpineController:
	if not is_valid():
		return self
	var anim_names := get_animation_names()
	var anim_state := _get_animation_state()
	if anim_state != null and anim_state.has_method("set_animation"):
		for anim_name in anim_names:
			anim_state.call("set_animation", anim_name, false, 0)
			step(0.016)
		if anim_state.has_method("clear_tracks"):
			anim_state.call("clear_tracks")
	reset_pose()
	return self
#endregion


#region 4. Transform, Bone Sockets & Coroutine Await (坐标、骨骼挂点与安全协程等待)
## 设置节点位置、缩放与旋转（流式返回 `self`）。
func set_transform_2d(pos: Vector2, scale_vec: Vector2 = Vector2.ONE, rot_rad: float = 0.0) -> SpineController:
	if is_valid():
		_sprite.position = pos
		_sprite.scale = scale_vec
		_sprite.rotation = rot_rad
	return self


## 获取指定骨骼（Bone）在 2D 场景世界坐标系下的全局位置（如武器枪口、受击中心点）。
func get_bone_global_position(bone_name: String) -> Result:
	if not is_valid():
		return Result.err_code("Spine.InvalidNode", "SpineSprite is invalid.")
	if bone_name.is_empty():
		return Result.err_code("Spine.InvalidBone", "Bone name cannot be empty.")

	if _sprite.has_method("get_bone_global_transform"):
		var xform: Variant = _sprite.call("get_bone_global_transform", bone_name)
		if xform is Transform2D:
			return Result.ok((xform as Transform2D).origin)

	var skeleton := _get_skeleton()
	if skeleton != null and skeleton.has_method("find_bone"):
		var bone: Variant = skeleton.call("find_bone", bone_name)
		if bone is Object and bone.has_method("get_world_x") and bone.has_method("get_world_y"):
			var local_pos := Vector2(float(bone.call("get_world_x")), float(bone.call("get_world_y")))
			return Result.ok(_sprite.to_global(local_pos))

	return Result.err_code("Spine.BoneNotFound", "Bone '%s' not found on SpineSprite." % bone_name)


## 异步等待指定轨道的动画播放完成（内置基于动画时长的安全超时兜底与 [CancellationToken] 取消守卫）。
func await_completed(
	anim_name: String = "",
	track_index: int = 0,
	token: CancellationToken = null
) -> Result:
	if not is_valid() or not _sprite.is_inside_tree():
		return Result.err_code("Spine.NotInTree", "SpineSprite is invalid or not inside SceneTree.")
	if token != null and token.is_cancelled():
		return Result.err_code("Async.Cancelled", token.get_reason())

	var resolved_anim := resolve_animation_name(anim_name)
	var duration := get_animation_duration(resolved_anim)
	var max_wait_sec := (duration if duration > 0.0 else _FALLBACK_ANIM_DURATION_SEC) + _DEFAULT_SAFETY_TIMEOUT_MARGIN_SEC

	var state := {"done": false}
	var on_completed := func(_s: Variant = null, _as: Variant = null, track_entry: Variant = null) -> void:
		if state["done"]:
			return
		if track_entry is Object and track_entry.has_method("get_track_index"):
			if int(track_entry.call("get_track_index")) != track_index:
				return
		state["done"] = true

	if _sprite.has_signal("animation_completed"):
		_sprite.connect("animation_completed", on_completed)

	var tree := _sprite.get_tree()
	var start_msec := Time.get_ticks_msec()
	var timeout_msec := int(max_wait_sec * 1000.0)

	while not state["done"]:
		if not is_valid() or not _sprite.is_inside_tree():
			return Result.err_code("Async.Cancelled", "SpineSprite exited tree during animation wait.")
		if token != null and token.is_cancelled():
			if is_valid() and _sprite.has_signal("animation_completed") and _sprite.is_connected("animation_completed", on_completed):
				_sprite.disconnect("animation_completed", on_completed)
			return Result.err_code("Async.Cancelled", token.get_reason())
		if Time.get_ticks_msec() - start_msec >= timeout_msec:
			break
		if tree == null:
			break
		await tree.process_frame

	if is_valid() and _sprite.has_signal("animation_completed") and _sprite.is_connected("animation_completed", on_completed):
		_sprite.disconnect("animation_completed", on_completed)

	return Result.ok()
#endregion


#region 5. Lease Lifecycle (租约回收与释放)
## 将当前受控节点归还至所属 [SpinePool] 对象池；若非池化实例则安全销毁底层节点。
func release() -> void:
	if not is_valid():
		return
	if _pool_ref != null:
		var pool: Variant = _pool_ref.get_ref()
		if pool != null and pool.has_method("release"):
			pool.call("release", _sprite)
			return
	NodeUtils.safe_free(_sprite)
	_sprite = null
#endregion


#region Internal Helpers
func _get_animation_state() -> Object:
	if not is_valid() or not _sprite.has_method("get_animation_state"):
		return null
	var state: Variant = _sprite.call("get_animation_state")
	return state as Object if state is Object else null


func _get_skeleton() -> Object:
	if not is_valid() or not _sprite.has_method("get_skeleton"):
		return null
	var skel: Variant = _sprite.call("get_skeleton")
	return skel as Object if skel is Object else null
#endregion
