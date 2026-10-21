class_name SpinePool
extends RefCounted

## Spine 骨骼实例对象池、视口内全管线真预热与分频错峰调度器（Spine Pool & Staggered Scheduler）。[br]
##
## [b]核心设计模式（专治 Godot + Spine 复杂骨骼瞬时卡顿）：[/b][br]
## 1. [b]享元对象池 + 租约句柄模式（Object Pool & Lease Handle）[/b]：预构建 C++ `spine::Skeleton` 树与 `MeshAttachment` 蒙皮变形缓冲区；战斗中通过 [method acquire] / [method play_oneshot] 零分配借出 [SpineController] 租约句柄，调用 [method SpineController.release] 或播完自动归还休眠容器，实现运行期 **0ms C++ 构造开销**；[br]
## 2. [b]视口内全管线真预热模式（In-Frustum Multi-Blend Warmup）[/b]：摒弃会被视口裁剪器剔除的 `(-9999, -9999)` 假预热，在视口安全角（微缩 `0.001` + 微透明 `0.005`）遍历全部动画步进采样并渲染 1 帧，强制 GPU 提前编译 `Normal / Additive / Multiply` 混合管线，预热完直接入池待命；[br]
## 3. [b]奇偶帧错峰与降频步进模式（Staggered Frame Decimation）[/b]：将同屏复杂 Spine 切换为 `Manual` 手动更新，按目标帧率（如 `30 FPS`）与相位桶（奇偶帧错峰）均匀分摊 `computeWorldVertices` 与 `ClippingAttachment` 裁剪算力，削平单帧 CPU 尖峰；[br]
## 4. [b]宿主生命周期绑定[/b]：挂载于场景宿主节点（如 `BaseScene`）下，随场景退树自动回收全部池化实例，杜绝显存与 RID 泄漏。

#region Constants
const DEFAULT_MAX_PER_SKELETON: int = 16
const DEFAULT_STAGGER_FPS: float = 30.0
const DEFAULT_STAGGER_BUCKETS: int = 2
const _WARMUP_VIEWPORT_POS := Vector2(2.0, 2.0)
const _WARMUP_SCALE := Vector2(0.001, 0.001)
const _WARMUP_MODULATE := Color(1.0, 1.0, 1.0, 0.005)
#endregion

#region Internal State
var _host_id: int = 0
var _driver_node: _SpinePoolDriver = null
var _dormant_container: Node2D = null
var _max_per_skeleton: int = DEFAULT_MAX_PER_SKELETON
var _stagger_buckets: int = DEFAULT_STAGGER_BUCKETS

## 闲置对象池：int (skeleton_res_instance_id) -> Array[SpineController]
var _idle_pools: Dictionary = {}
## 强引用持有已注册的骨骼数据 Resource，防止池化期间被意外释放：int (res_id) -> Resource
var _held_resources: Dictionary = {}
## 正在借出活跃中的租约表：int (sprite_instance_id) -> { "controller": SpineController, "res": Resource }
var _active_leases: Dictionary = {}
## 错峰分频托管表：int (sprite_instance_id) -> { "controller": SpineController, "interval": float, "accum": float, "bucket": int }
var _staggered_entries: Dictionary = {}
var _next_bucket_cursor: int = 0
var _frame_counter: int = 0
var _disposed: bool = false
#endregion


#region Lifecycle
## 构造绑定于指定场景/容器宿主的 [SpinePool]。[br]
##
## [param host] 宿主节点（推荐传入当前 `BaseScene` `self`；宿主退树时自动触发池销毁）。[br]
## [param max_per_skeleton] 单种骨骼资源的最大闲置缓存实例数（默认 16）。[br]
## [param stagger_buckets] 错峰分频相位桶数量（默认 2，即奇偶帧错峰削峰）。
func _init(
	host: Node = null,
	max_per_skeleton: int = DEFAULT_MAX_PER_SKELETON,
	stagger_buckets: int = DEFAULT_STAGGER_BUCKETS
) -> void:
	_max_per_skeleton = maxi(1, max_per_skeleton)
	_stagger_buckets = maxi(1, stagger_buckets)
	if host != null and is_instance_valid(host):
		bind_host(host)


## 绑定宿主节点并挂载内部休眠容器与错峰帧驱动器。
func bind_host(host: Node) -> Result:
	if _disposed:
		return Result.err_code("Spine.PoolDisposed", "SpinePool has already been disposed.")
	if host == null or not is_instance_valid(host):
		return Result.err_code("Spine.InvalidHost", "Host node is null or invalid.")

	_host_id = host.get_instance_id()
	if _driver_node != null and is_instance_valid(_driver_node):
		NodeUtils.safe_free(_driver_node)

	_driver_node = _SpinePoolDriver.new(self)
	_driver_node.name = "SpinePoolDriver"
	var mount_res := NodeUtils.mount(_driver_node, host, "SpinePoolDriver")
	if mount_res.is_err():
		NodeUtils.safe_free(_driver_node)
		_driver_node = null
		return mount_res

	_dormant_container = Node2D.new()
	_dormant_container.name = "DormantContainer"
	_dormant_container.visible = false
	_dormant_container.process_mode = Node.PROCESS_MODE_DISABLED
	NodeUtils.mount(_dormant_container, _driver_node, "DormantContainer")
	return Result.ok()


## 销毁对象池，立即安全释放全部闲置与托管的 `SpineSprite` 实例及资源引用。
func dispose() -> void:
	if _disposed:
		return
	_disposed = true

	for res_id in _idle_pools:
		var bucket: Array = _idle_pools[res_id]
		for ctrl in bucket:
			if ctrl is SpineController and (ctrl as SpineController).is_valid():
				NodeUtils.safe_free((ctrl as SpineController).node)
	_idle_pools.clear()
	_active_leases.clear()
	_staggered_entries.clear()
	_held_resources.clear()

	if _driver_node != null and is_instance_valid(_driver_node):
		NodeUtils.safe_free(_driver_node)
	_driver_node = null
	_dormant_container = null
#endregion


#region 1. In-Frustum True Warmup (视口内全管线真预热 -> 直接入池)
## 预热指定骨骼资源并预生成 [param count] 个已分配好 C++ 骨骼与蒙皮缓冲的 [SpineController] 实例入池待命。[br]
##
## [b]防卡顿机制：[/b]在视口内安全角微缩渲染 1 帧并遍历全部动画执行首帧采样，提前激活所有混合材质与变形网格，随后直接转入闲置池供战斗零开销复用。
func warmup(skeleton_res_or_path: Variant, count: int = 2) -> Result:
	if _disposed:
		return Result.err_code("Spine.PoolDisposed", "SpinePool is disposed.")
	if not SpineController.is_spine_supported():
		return Result.ok(0)

	var skel_res := SpineController.resolve_skeleton_resource(skeleton_res_or_path)
	if skel_res == null:
		return Result.err_code("Spine.InvalidResource", "Failed to resolve SpineSkeletonDataResource for warmup.")

	var host := _get_host_node()
	if host == null:
		return Result.err_code("Spine.NoHost", "SpinePool requires a valid bound host node for warmup.")

	var target_count := clampi(count, 1, _max_per_skeleton)
	var existing_idle := _get_idle_bucket(skel_res).size()
	var needed := maxi(0, target_count - existing_idle)
	if needed == 0:
		return Result.ok(target_count)

	var created_ctrls: Array[SpineController] = []
	for i in needed:
		var create_res := SpineController.create(skel_res)
		if create_res.is_err():
			continue
		var ctrl := create_res.value as SpineController
		ctrl._pool_ref = weakref(self)
		var sprite := ctrl.node
		sprite.position = _WARMUP_VIEWPORT_POS
		sprite.scale = _WARMUP_SCALE
		sprite.modulate = _WARMUP_MODULATE

		var mount_res := NodeUtils.mount(sprite, host, "WarmupSpine_%d" % i)
		if mount_res.is_err():
			NodeUtils.safe_free(sprite)
			continue

		ctrl.prewarm_all_animations()
		created_ctrls.append(ctrl)

	if not created_ctrls.is_empty():
		var tree := host.get_tree()
		if tree != null:
			await tree.process_frame
		if _disposed:
			for c in created_ctrls:
				if c.is_valid():
					NodeUtils.safe_free(c.node)
			return Result.err_code("Async.Cancelled", "SpinePool disposed during warmup.")

		for ctrl in created_ctrls:
			if ctrl.is_valid():
				_park_into_idle_pool(ctrl, skel_res)

	return Result.ok(_get_idle_bucket(skel_res).size())


## 批量预热多组骨骼资源（传入字典 [code]{ skeleton_res_or_path: count }[/code]）。
func warmup_batch(specs: Dictionary) -> Result:
	if _disposed:
		return Result.err_code("Spine.PoolDisposed", "SpinePool is disposed.")
	if not SpineController.is_spine_supported() or specs.is_empty():
		return Result.ok()

	for key in specs:
		var count := int(specs[key])
		var res := await warmup(key, maxi(1, count))
		if res.is_err() and res.error_code() == "Async.Cancelled":
			return res
	return Result.ok()
#endregion


#region 2. Zero-Allocation Acquire / Release / Oneshot (对象池零分配借还与特效播放)
## 从对象池借出一个已构造好 C++ 骨骼与蒙皮缓冲的 [SpineController] 租约句柄并挂载其节点到 [param parent]。[br]
## 若池中暂无闲置实例，则自动新建并在调用 [method SpineController.release] 或 [method release] 时纳入池化管理。
func acquire(
	skeleton_res_or_path: Variant,
	parent: Node,
	pos: Vector2 = Vector2.ZERO,
	scale_vec: Vector2 = Vector2.ONE,
	node_name: String = ""
) -> Result:
	if _disposed:
		return Result.err_code("Spine.PoolDisposed", "SpinePool is disposed.")
	if parent == null or not is_instance_valid(parent):
		return Result.err_code("Spine.InvalidParent", "Target parent node is null or invalid.")

	var skel_res := SpineController.resolve_skeleton_resource(skeleton_res_or_path)
	if skel_res == null:
		return Result.err_code("Spine.InvalidResource", "Failed to resolve SpineSkeletonDataResource.")

	var ctrl: SpineController = _pop_from_idle_pool(skel_res)
	if ctrl == null:
		var create_res := SpineController.create(skel_res)
		if create_res.is_err():
			return create_res
		ctrl = create_res.value as SpineController
		ctrl._pool_ref = weakref(self)

	var sprite := ctrl.node
	if sprite.get_parent() != null:
		sprite.get_parent().remove_child(sprite)

	sprite.visible = true
	sprite.modulate = Color.WHITE
	sprite.position = pos
	sprite.scale = scale_vec
	sprite.rotation = 0.0
	sprite.process_mode = Node.PROCESS_MODE_INHERIT
	ctrl.set_manual_update(false).set_time_scale(1.0).reset_pose()

	var target_name := node_name
	if target_name.is_empty():
		var base := skel_res.resource_path.get_file().get_basename()
		target_name = "Spine_%s" % (base if not base.is_empty() else "Instance")

	var mount_res := NodeUtils.mount(sprite, parent, target_name)
	if mount_res.is_err():
		NodeUtils.safe_free(sprite)
		return mount_res

	var res_id := skel_res.get_instance_id()
	_held_resources[res_id] = skel_res
	_active_leases[sprite.get_instance_id()] = {
		"controller": ctrl,
		"res": skel_res,
	}
	return Result.ok(ctrl)


## 将使用完毕的 [SpineController] 或 `SpineSprite` 节点归还至对象池（自动清空动画轨道、取消错峰步进并移入休眠容器，绝不销毁重建）。
func release(target: Variant) -> void:
	var ctrl: SpineController = _resolve_controller(target)
	if ctrl == null or not ctrl.is_valid():
		return
	if _disposed:
		NodeUtils.safe_free(ctrl.node)
		return

	var sprite := ctrl.node
	var sprite_id := sprite.get_instance_id()
	unregister_staggered(ctrl)

	var skel_res: Resource = null
	if _active_leases.has(sprite_id):
		var lease: Dictionary = _active_leases[sprite_id]
		skel_res = lease.get("res", null) as Resource
		_active_leases.erase(sprite_id)
	if skel_res == null:
		skel_res = ctrl.get_skeleton_data()
	if skel_res == null:
		NodeUtils.safe_free(sprite)
		return

	_park_into_idle_pool(ctrl, skel_res)


## 从池中借出 [SpineController] 播放一次性特效，播放完毕后**自动归还池中**（0ms 构造开销、零节点销毁抖动）。[br]
## @return 成功时返回携带 [SpineController] 的 [Result]。
func play_oneshot(
	skeleton_res_or_path: Variant,
	parent: Node,
	pos: Vector2 = Vector2.ZERO,
	anim_name: String = "",
	scale_vec: Vector2 = Vector2.ONE,
	time_scale: float = 1.0
) -> Result:
	var acq_res := acquire(skeleton_res_or_path, parent, pos, scale_vec)
	if acq_res.is_err():
		return acq_res

	var ctrl: SpineController = acq_res.value as SpineController
	var play_res := ctrl.try_play(anim_name, false, 0, time_scale)
	if play_res.is_err():
		release(ctrl)
		return play_res

	_recycle_after_oneshot(ctrl, anim_name)
	return Result.ok(ctrl)


func _recycle_after_oneshot(ctrl: SpineController, anim_name: String) -> void:
	if ctrl == null or not ctrl.is_valid():
		return
	var lease_id := ctrl.node.get_instance_id()
	await ctrl.await_completed(anim_name, 0)
	if not _disposed and ctrl.is_valid() and _active_leases.has(lease_id):
		release(ctrl)
#endregion


#region 3. Staggered Frame Decimation Scheduler (奇偶帧错峰与降频步进调度器)
## 将复杂 [SpineController]（或 `SpineSprite` 节点）注册至分频错峰调度器（自动切换为 `UpdateMode_Manual`，按目标帧率与奇偶帧错峰更新骨骼，削平同屏多骨骼 CPU 峰值）。[br]
##
## [param target] 待托管的 [SpineController] 或 `SpineSprite` 节点（如 Boss 或高顶点数怪物）。[br]
## [param target_fps] 目标骨骼步进帧率（默认 `30.0` FPS，与美术导出帧率对齐，相比 60/120Hz 节省 50%~75% 蒙皮算力）。
func register_staggered(target: Variant, target_fps: float = DEFAULT_STAGGER_FPS) -> Result:
	if _disposed:
		return Result.err_code("Spine.PoolDisposed", "SpinePool is disposed.")
	var ctrl := _resolve_controller(target)
	if ctrl == null or not ctrl.is_valid():
		return Result.err_code("Spine.InvalidNode", "Target is not a valid SpineController or SpineSprite.")

	ctrl.set_manual_update(true)
	var interval := 1.0 / clampf(target_fps, 5.0, 120.0)
	var bucket := _next_bucket_cursor % _stagger_buckets
	_next_bucket_cursor += 1

	_staggered_entries[ctrl.node.get_instance_id()] = {
		"controller": ctrl,
		"interval": interval,
		"accum": 0.0,
		"bucket": bucket,
	}
	return Result.ok(ctrl)


## 从分频错峰调度器中移除指定 [SpineController]（或 `SpineSprite` 节点）并恢复其默认自动更新模式。
func unregister_staggered(target: Variant) -> void:
	var ctrl := _resolve_controller(target)
	if ctrl == null or not ctrl.is_valid():
		return
	var id := ctrl.node.get_instance_id()
	if _staggered_entries.erase(id):
		ctrl.set_manual_update(false)


## 推进一帧错峰分频调度（若已绑定 `host` 节点，由内部 `_SpinePoolDriver` 每帧自动调用；无宿主单测时可手动调用）。
func tick(delta: float) -> void:
	if _disposed or _staggered_entries.is_empty():
		return

	var active_bucket := _frame_counter % _stagger_buckets
	_frame_counter += 1

	var stale_ids: Array[int] = []
	for id: int in _staggered_entries:
		var entry: Dictionary = _staggered_entries[id]
		var ctrl: SpineController = entry["controller"] as SpineController
		if ctrl == null or not ctrl.is_valid():
			stale_ids.append(id)
			continue
		var sprite := ctrl.node
		if not sprite.is_inside_tree() or not sprite.visible:
			continue

		var accum: float = float(entry["accum"]) + delta
		var interval: float = float(entry["interval"])
		if int(entry["bucket"]) == active_bucket and accum >= interval:
			ctrl.step(accum)
			entry["accum"] = 0.0
		else:
			entry["accum"] = accum

	for stale_id in stale_ids:
		_staggered_entries.erase(stale_id)
#endregion


#region 4. Diagnostics
## 获取当前对象池与错峰调度器的运行诊断指标。
func get_diagnostics() -> Dictionary:
	var total_idle: int = 0
	for res_id in _idle_pools:
		total_idle += (_idle_pools[res_id] as Array).size()
	return {
		"disposed": _disposed,
		"skeleton_types_cached": _idle_pools.size(),
		"idle_instances": total_idle,
		"active_leases": _active_leases.size(),
		"staggered_managed": _staggered_entries.size(),
		"stagger_buckets": _stagger_buckets,
	}
#endregion


#region Internal Pool Helpers
func _resolve_controller(target: Variant) -> SpineController:
	if target is SpineController:
		return target as SpineController
	if target is Node and SpineController.is_spine_sprite(target as Object):
		var sprite := target as Node
		var id := sprite.get_instance_id()
		if _active_leases.has(id):
			return (_active_leases[id] as Dictionary).get("controller", null) as SpineController
		return SpineController.new(sprite, self)
	return null


func _get_host_node() -> Node:
	if _host_id == 0:
		return null
	var obj := instance_from_id(_host_id)
	if obj is Node and is_instance_valid(obj):
		return obj as Node
	return null


func _get_idle_bucket(skel_res: Resource) -> Array:
	var res_id := skel_res.get_instance_id()
	if not _idle_pools.has(res_id):
		_idle_pools[res_id] = []
		_held_resources[res_id] = skel_res
	return _idle_pools[res_id] as Array


func _pop_from_idle_pool(skel_res: Resource) -> SpineController:
	var bucket := _get_idle_bucket(skel_res)
	while not bucket.is_empty():
		var candidate: Variant = bucket.pop_back()
		if candidate is SpineController and (candidate as SpineController).is_valid():
			return candidate as SpineController
	return null


func _park_into_idle_pool(ctrl: SpineController, skel_res: Resource) -> void:
	if ctrl == null or not ctrl.is_valid():
		return
	var sprite := ctrl.node
	var bucket := _get_idle_bucket(skel_res)
	if bucket.size() >= _max_per_skeleton:
		NodeUtils.safe_free(sprite)
		return

	ctrl.clear_tracks(true).set_manual_update(true)
	sprite.visible = false
	sprite.modulate = Color.WHITE
	sprite.process_mode = Node.PROCESS_MODE_DISABLED

	if sprite.get_parent() != null:
		sprite.get_parent().remove_child(sprite)
	if _dormant_container != null and is_instance_valid(_dormant_container):
		_dormant_container.add_child(sprite)

	bucket.append(ctrl)


## 内部轻量宿主驱动节点：自动将 `_process(delta)` 与 `_exit_tree()` 桥接回 [SpinePool]。
class _SpinePoolDriver extends Node:
	var _pool_ref: WeakRef = null

	func _init(pool: SpinePool = null) -> void:
		if pool != null:
			_pool_ref = weakref(pool)

	func _process(delta: float) -> void:
		if _pool_ref == null:
			return
		var pool := _pool_ref.get_ref() as SpinePool
		if pool != null:
			pool.tick(delta)

	func _exit_tree() -> void:
		if _pool_ref == null:
			return
		var pool := _pool_ref.get_ref() as SpinePool
		if pool != null:
			pool.dispose()
#endregion
