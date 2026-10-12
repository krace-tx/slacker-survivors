class_name SpineUtils
extends RefCounted

## Spine 骨骼动画通用调度与工具库。
## 职责：
## 1. 骨骼资源（.tres）全局缓存与内存管理；
## 2. 场景外后台预热（Warmup），提前编译 Shader 与上传 GPU 纹理，消除首帧掉帧；
## 3. 全局 Root 特效层管理（GlobalVfxLayer），彻底与业务 UI / 场景容器物理隔离；
## 4. 一次性特效播放（play_vfx / play_oneshot）与循环动画（play_loop）统一调度；
## 5. 环境自省安全守护：若运行环境未编译集成 spine-godot 插件，安全空操作并记 warning，杜绝编译崩溃。

#region Constants & State
const GLOBAL_VFX_LAYER_NAME := "GlobalVfxLayer"
const GLOBAL_VFX_LAYER_INDEX := 100

static var _resource_cache: Dictionary = {}
static var _warmed_up_paths: Dictionary = {}
static var _global_vfx_layer: CanvasLayer = null
#endregion


#region Public API - Capability Check
## 检查当前引擎环境是否已集成并支持 SpineSprite 节点
static func is_spine_supported() -> bool:
	return ClassDB.can_instantiate(&"SpineSprite")
#endregion


#region Public API - Global VFX Layer
## 获取或自动在 SceneTree.root 下创建全局特效层（CanvasLayer，独立于业务场景，置顶渲染且防污染）
static func get_vfx_layer(context: Node = null) -> CanvasLayer:
	if is_instance_valid(_global_vfx_layer) and _global_vfx_layer.is_inside_tree():
		return _global_vfx_layer

	var tree: SceneTree = context.get_tree() if (is_instance_valid(context) and context.get_tree() != null) else Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null

	var existing := tree.root.get_node_or_null(GLOBAL_VFX_LAYER_NAME) as CanvasLayer
	if existing != null and is_instance_valid(existing):
		_global_vfx_layer = existing
		return _global_vfx_layer

	var layer := CanvasLayer.new()
	layer.name = GLOBAL_VFX_LAYER_NAME
	layer.layer = GLOBAL_VFX_LAYER_INDEX
	var mount_res := NodeUtils.mount(layer, tree.root, GLOBAL_VFX_LAYER_NAME)
	if mount_res.is_ok():
		_global_vfx_layer = layer
	else:
		NodeUtils.safe_free(layer)

	return _global_vfx_layer
#endregion


#region Public API - Warmup & Preload
## 预加载并预热指定的 Spine 资源列表（在场景外激活并渲染 1 帧，消除真机首帧掉帧与 Shader 编译卡顿）
static func warmup(tres_paths: Array[String], context: Node = null) -> void:
	if not is_spine_supported() or tres_paths.is_empty():
		return

	var tree: SceneTree = context.get_tree() if (is_instance_valid(context) and context.get_tree() != null) else Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return

	var dummy_nodes: Array[Node] = []

	for path in tres_paths:
		var skel_data := get_skeleton_data(path)
		if skel_data == null:
			continue

		if _warmed_up_paths.has(path):
			continue
		_warmed_up_paths[path] = true

		var sprite: Node = ClassDB.instantiate(&"SpineSprite")
		if sprite == null:
			continue
		sprite.set("skeleton_data_res", skel_data)
		sprite.set("position", Vector2(-9999.0, -9999.0))
		sprite.set("modulate", Color(1, 1, 1, 0.01))

		var dummy_name := "Spine_Warmup_%s" % path.get_file().get_basename()
		var mount_res := NodeUtils.mount(sprite, tree.root, dummy_name)
		if mount_res.is_err():
			NodeUtils.safe_free(sprite)
			continue

		dummy_nodes.append(sprite)

		if sprite.has_method("get_animation_state"):
			var anim_state = sprite.call("get_animation_state")
			if anim_state != null and anim_state.has_method("set_animation"):
				anim_state.call("set_animation", "animation", false, 0)

	if not dummy_nodes.is_empty():
		await tree.process_frame
		for node in dummy_nodes:
			NodeUtils.safe_free(node)


## 获取或加载 Spine 骨骼资源对象（带全局静态缓存）
static func get_skeleton_data(tres_path: String) -> Resource:
	if tres_path.is_empty():
		return null

	if _resource_cache.has(tres_path):
		return _resource_cache[tres_path] as Resource

	if not ResourceLoader.exists(tres_path):
		push_warning("SpineUtils: resource does not exist at path '%s'" % tres_path)
		return null

	var res := load(tres_path)
	if res != null:
		_resource_cache[tres_path] = res
	return res


## 清理指定资源或全部 Spine 骨骼数据缓存与预热标记，释放 GPU 显存
static func clear_cache(tres_path: String = "") -> void:
	if tres_path.is_empty():
		_resource_cache.clear()
		_warmed_up_paths.clear()
	else:
		_resource_cache.erase(tres_path)
		_warmed_up_paths.erase(tres_path)
#endregion


#region Public API - Playback
## 播放 Spine 动画
static func play(
	tres_path: String,
	parent: Node = null,
	pos: Vector2 = Vector2.ZERO,
	anim_name: String = "animation",
	scale_vec: Vector2 = Vector2.ONE,
	loop: bool = false,
	node_name: String = ""
) -> Node:
	if not is_spine_supported():
		push_warning("SpineUtils: SpineSprite is not supported in this build.")
		return null

	if tres_path.is_empty():
		return null

	var target_parent := parent
	if target_parent == null:
		target_parent = get_vfx_layer()

	if not is_instance_valid(target_parent):
		return null

	var skel_data := get_skeleton_data(tres_path)
	if skel_data == null:
		return null

	var spine_sprite: Node = ClassDB.instantiate(&"SpineSprite")
	if spine_sprite == null:
		return null

	spine_sprite.set("skeleton_data_res", skel_data)
	spine_sprite.set("position", pos)
	spine_sprite.set("scale", scale_vec)

	var target_name := node_name
	if target_name.is_empty():
		var file_base := tres_path.get_file().get_basename()
		target_name = "Spine_%s" % (file_base if not file_base.is_empty() else anim_name)

	var mount_res := NodeUtils.mount(spine_sprite, target_parent, target_name)
	if mount_res.is_err():
		NodeUtils.safe_free(spine_sprite)
		return null

	if spine_sprite.has_method("get_animation_state"):
		var anim_state = spine_sprite.call("get_animation_state")
		if anim_state != null and anim_state.has_method("set_animation"):
			anim_state.call("set_animation", anim_name, loop, 0)

	if not loop and spine_sprite.has_signal("animation_completed"):
		spine_sprite.connect("animation_completed", func(_sprite = null, _anim_state = null, _track_entry = null):
			NodeUtils.safe_free(spine_sprite)
		, Object.CONNECT_ONE_SHOT)

	return spine_sprite


## 在全局特效层播放一次性特效
static func play_vfx(
	tres_path: String,
	global_pos: Vector2,
	context: Node = null,
	anim_name: String = "animation",
	scale_vec: Vector2 = Vector2.ONE,
	node_name: String = ""
) -> Node:
	var vfx_layer := get_vfx_layer(context)
	return play(tres_path, vfx_layer, global_pos, anim_name, scale_vec, false, node_name)


## 播放一次性 Spine 特效
static func play_oneshot(
	tres_path: String,
	parent: Node,
	pos: Vector2 = Vector2.ZERO,
	anim_name: String = "animation",
	scale_vec: Vector2 = Vector2.ONE,
	node_name: String = ""
) -> Node:
	return play(tres_path, parent, pos, anim_name, scale_vec, false, node_name)


## 循环播放 Spine 动画
static func play_loop(
	tres_path: String,
	parent: Node = null,
	pos: Vector2 = Vector2.ZERO,
	anim_name: String = "animation",
	scale_vec: Vector2 = Vector2.ONE,
	node_name: String = ""
) -> Node:
	return play(tres_path, parent, pos, anim_name, scale_vec, true, node_name)
#endregion
