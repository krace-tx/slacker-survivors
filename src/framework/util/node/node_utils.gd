@abstract
class_name NodeUtils
extends RefCounted

## 节点场景树生命周期工具：入树挂载、预制体实例化、复制、安全销毁、清空子节点与就绪等待。[br]
##
## [b]职责边界（只管「节点进出场景树与存活状态」）：[/b][br]
## 1. [method mount] 接管已有节点；[method spawn] 从 [PackedScene] 实例化；[method clone] 复制已有节点；[br]
## 2. [method safe_free] / [method clear_children] 安全销毁；[method wait_ready] 信号驱动等待 [code]ready[/code]；[br]
## 3. [b]不在此封装[/b]：节点查找/遍历直接使用引擎内置 [method Node.find_child] / [method Node.get_node_or_null]；
##    坐标与几何换算归 [CoordUtils]；绑定宿主生命周期的延时与并发等待归 [TaskScope]。[br]
##
## [b]失败语义：[/b]可失败操作返回携带 [code]Node.{Reason}[/code] 错误码的 [Result]；
## 基建中「不该失败」的挂载使用 [method mount_required]（失败即 bug）。[br]
## 纯静态工具，不依赖 App 或任何 autoload；[code]@abstract[/code] 禁止实例化。

#region Error Codes
const ERR_INVALID_NODE: String = "Node.InvalidNode"
const ERR_INVALID_PARENT: String = "Node.InvalidParent"
const ERR_INVALID_SCENE: String = "Node.InvalidScene"
const ERR_ALREADY_PARENTED: String = "Node.AlreadyParented"
const ERR_QUEUED_FOR_DELETION: String = "Node.QueuedForDeletion"
const ERR_INSTANTIATE_FAILED: String = "Node.InstantiateFailed"
const ERR_DUPLICATE_FAILED: String = "Node.DuplicateFailed"
const ERR_FREED: String = "Node.Freed"
const ERR_NO_SCENE_TREE: String = "Node.NoSceneTree"
const ERR_READY_TIMEOUT: String = "Node.ReadyTimeout"
#endregion

#region Constants
## [method clone] 默认复制标志：信号 + 分组 + 脚本 + 按实例化方式复制（与 [method Node.duplicate] 引擎默认值一致）。
const DEFAULT_DUPLICATE_FLAGS: int = (
	Node.DUPLICATE_SIGNALS
	| Node.DUPLICATE_GROUPS
	| Node.DUPLICATE_SCRIPTS
	| Node.DUPLICATE_USE_INSTANTIATION
)
#endregion


#region Public API
## 把已实例化的 [param node] 挂到 [param parent] 下，成功时 [member Result.value] 为 [param node]。[br]
## 失败不释放 [param node]（所有权仍归调用方）。[param child_name] 非空则入树前命名，避免入树后改名触发重复通知。
static func mount(node: Node, parent: Node, child_name: String = "") -> Result:
	if not is_instance_valid(node):
		return Result.err_code(ERR_INVALID_NODE, "Mount failed: node is invalid.")
	var parent_res := _validate_parent(parent, "Mount")
	if parent_res.is_err():
		return parent_res
	if node.is_queued_for_deletion():
		return Result.err_code(ERR_QUEUED_FOR_DELETION, "Mount failed: '%s' is queued for deletion." % node.name)
	var current_parent := node.get_parent()
	if current_parent != null:
		return Result.err_code(
			ERR_ALREADY_PARENTED,
			"Mount failed: '%s' already has parent '%s'." % [node.name, current_parent.name]
		)
	if node == parent or node.is_ancestor_of(parent):
		return Result.err_code(
			ERR_INVALID_PARENT,
			"Mount failed: cannot mount '%s' onto itself or its own descendant." % node.name
		)

	if not child_name.is_empty():
		node.name = child_name
	parent.add_child(node)
	return Result.ok(node)


## 挂载必须成功的节点（boot 流程、服务内部子节点等基建场景），返回 [param node] 便于链式使用。[br]
## 失败即 bug：[code]push_error[/code] + [code]assert[/code]（Release 下 assert 被剥离，仅保留错误日志）。[br]
## 不走 App.logger：本工具不依赖任何服务。
static func mount_required(node: Node, parent: Node, child_name: String = "") -> Node:
	var res := mount(node, parent, child_name)
	if res.is_err():
		push_error("NodeUtils.mount_required failed [%s]: %s" % [res.error_code(), res.error_message()])
		assert(false, "NodeUtils.mount_required failed: %s" % res.error_message())
	return node


## 实例化 [param scene] 并挂到 [param parent]，成功时 [member Result.value] 为新实例。[br]
## 先校验父节点再实例化，避免无效父节点导致的白实例化开销；挂载失败立即 [code]free()[/code] 未入树的实例，杜绝泄漏。
static func spawn(scene: PackedScene, parent: Node, child_name: String = "") -> Result:
	if scene == null or not scene.can_instantiate():
		return Result.err_code(ERR_INVALID_SCENE, "Spawn failed: scene is null or cannot be instantiated.")
	var parent_res := _validate_parent(parent, "Spawn")
	if parent_res.is_err():
		return parent_res

	var instance: Node = scene.instantiate()
	if instance == null:
		return Result.err_code(ERR_INSTANTIATE_FAILED, "Spawn failed: instantiate() returned null.")

	var res := mount(instance, parent, child_name)
	if res.is_err():
		instance.free()
	return res


## 复制 [param node]（含子树）并挂到 [param parent]，成功时 [member Result.value] 为副本。[br]
## [param flags] 透传 [method Node.duplicate]，默认 [constant DEFAULT_DUPLICATE_FLAGS]；挂载失败立即 [code]free()[/code] 副本。
static func clone(
	node: Node,
	parent: Node,
	child_name: String = "",
	flags: int = DEFAULT_DUPLICATE_FLAGS
) -> Result:
	if not is_instance_valid(node):
		return Result.err_code(ERR_INVALID_NODE, "Clone failed: node is invalid.")
	if node.is_queued_for_deletion():
		return Result.err_code(ERR_QUEUED_FOR_DELETION, "Clone failed: '%s' is queued for deletion." % node.name)
	var parent_res := _validate_parent(parent, "Clone")
	if parent_res.is_err():
		return parent_res

	var copy := node.duplicate(flags)
	if copy == null:
		return Result.err_code(ERR_DUPLICATE_FAILED, "Clone failed: duplicate() returned null.")

	var res := mount(copy, parent, child_name)
	if res.is_err():
		copy.free()
	return res


## 延迟销毁 [param node]。无效、非 [Node] 或已排队销毁时静默忽略，避免重复 [code]queue_free[/code]。[br]
## 形参刻意声明为 [Variant]：传入已释放的幽灵引用时，强类型 [Node] 形参会在调用边界直接报错。
static func safe_free(node: Variant) -> void:
	if not is_instance_valid(node):
		return
	var n := node as Node
	if n != null and not n.is_queued_for_deletion():
		n.queue_free()


## 销毁 [param parent] 的全部直接子节点（不含 internal 子节点），返回本次处理的子节点数量。[br]
## - [param immediate] = [code]false[/code]（默认）：先 [method Node.remove_child] 立即脱离再 [code]queue_free[/code]，
##   调用后 [method Node.get_child_count] 立即归零，可安全地在同一帧重建列表；[br]
## - [param immediate] = [code]true[/code]：同步 [code]free()[/code]。[br]
## [b]注意[/b]：两种模式都会同步触发子节点退树；在物理回调（如 [signal Area2D.body_entered]）中清理碰撞体时，
## 请延迟到物理回调之外执行：[code](func() -> void: NodeUtils.clear_children(parent)).call_deferred()[/code]。
static func clear_children(parent: Node, immediate: bool = false) -> int:
	if not is_instance_valid(parent):
		return 0
	var children := parent.get_children()
	var cleared := 0
	for i in range(children.size() - 1, -1, -1):
		var child: Node = children[i]
		if not is_instance_valid(child) or child.is_queued_for_deletion():
			continue
		parent.remove_child(child)
		if immediate:
			child.free()
		else:
			child.queue_free()
		cleared += 1
	return cleared


## 信号驱动等待 [param node] 的 [code]ready[/code]，成功时 [member Result.value] 为 [param node]。[br]
## - 已 ready 立即成功；尚未入树（如 [code]add_child.call_deferred[/code]）也可等待，入树就绪后唤醒；[br]
## - 零逐帧轮询：监听 [signal Node.ready]；节点被释放返回 [constant ERR_FREED]（在树内被释放于下一帧确认，
##   从未入树的孤儿节点被释放则在超时点确认），超时返回 [constant ERR_READY_TIMEOUT]；
##   超时按真实时间计（不受暂停与 [member Engine.time_scale] 影响）。[br]
##
## [codeblock]
## var mount_res := NodeUtils.mount(widget, self)
## if mount_res.is_err():
##     return
## var ready_res := await NodeUtils.wait_ready(widget)
## if ready_res.is_err():
##     return
## widget.refresh()
## [/codeblock]
static func wait_ready(node: Node, timeout_sec: float = 5.0) -> Result:
	if not is_instance_valid(node):
		return Result.err_code(ERR_INVALID_NODE, "Wait ready failed: node is invalid.")
	if node.is_node_ready():
		return Result.ok(node)
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return Result.err_code(ERR_NO_SCENE_TREE, "Wait ready failed: SceneTree is unavailable.")

	var waiter := _ReadyWaiter.new(node, tree, maxf(timeout_sec, 0.0))
	var outcome: int = await waiter.settled
	match outcome:
		_ReadyWaiter.Outcome.READY:
			return Result.ok(node)
		_ReadyWaiter.Outcome.FREED:
			return Result.err_code(ERR_FREED, "Wait ready failed: node was freed before ready.")
		_:
			return Result.err_code(ERR_READY_TIMEOUT, "Wait ready failed: timed out (%.1fs)." % timeout_sec)
#endregion


#region Internal Helpers
static func _validate_parent(parent: Node, op: String) -> Result:
	if not is_instance_valid(parent):
		return Result.err_code(ERR_INVALID_PARENT, "%s failed: parent is invalid." % op)
	if parent.is_queued_for_deletion():
		return Result.err_code(
			ERR_QUEUED_FOR_DELETION,
			"%s failed: parent '%s' is queued for deletion." % [op, parent.name]
		)
	return Result.ok()


## [method wait_ready] 的一次性信号汇合器：ready / 释放 / 超时三路竞争，先到先结算且只结算一次。[br]
## 仅通过 [WeakRef] 观察节点，不延长节点生命周期；结算后主动断开节点信号。
class _ReadyWaiter:
	extends RefCounted

	signal settled(outcome: int)

	enum Outcome { READY, FREED, TIMEOUT }

	var _node_ref: WeakRef = null
	var _tree_ref: WeakRef = null
	var _done: bool = false


	func _init(node: Node, tree: SceneTree, timeout_sec: float) -> void:
		_node_ref = weakref(node)
		_tree_ref = weakref(tree)
		node.ready.connect(_on_ready, CONNECT_ONE_SHOT)
		node.tree_exited.connect(_on_tree_exited)
		# process_always=true, process_in_physics=false, ignore_time_scale=true：按真实时间计时，暂停期间仍生效
		tree.create_timer(timeout_sec, true, false, true).timeout.connect(_on_timeout)


	func _on_ready() -> void:
		_settle(Outcome.READY)


	func _on_tree_exited() -> void:
		# 退树可能是 remove_child（仍存活）或销毁中；下一帧（删除队列已 flush）再确认存活性
		var tree := _tree_ref.get_ref() as SceneTree
		if tree != null and not tree.process_frame.is_connected(_check_alive):
			tree.process_frame.connect(_check_alive, CONNECT_ONE_SHOT)


	func _check_alive() -> void:
		if _node_ref.get_ref() == null:
			_settle(Outcome.FREED)


	func _on_timeout() -> void:
		_settle(Outcome.FREED if _node_ref.get_ref() == null else Outcome.TIMEOUT)


	func _settle(outcome: int) -> void:
		if _done:
			return
		_done = true
		var node := _node_ref.get_ref() as Node
		if node != null:
			if node.ready.is_connected(_on_ready):
				node.ready.disconnect(_on_ready)
			if node.tree_exited.is_connected(_on_tree_exited):
				node.tree_exited.disconnect(_on_tree_exited)
		var tree := _tree_ref.get_ref() as SceneTree
		if tree != null and tree.process_frame.is_connected(_check_alive):
			tree.process_frame.disconnect(_check_alive)
		settled.emit(outcome)
#endregion
