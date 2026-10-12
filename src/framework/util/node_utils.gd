class_name NodeUtils
extends RefCounted

## 节点挂载、复制、销毁与 ready 等待。
##
## [method mount] 接管已有节点；[method spawn] 从 PackedScene 实例化。失败走 [Result]。
## [method mount_required] 给不该失败的基建（boot / 服务子节点），失败即 bug。
## 纯工具，不依赖 App 或其它 autoload。

#region Public API
## 把已实例化的 [param node] 挂到 [param parent] 下。[br]
## 失败不释放 [param node]（调用方持有）。[param child_name] 非空则入树前命名。
static func mount(node: Node, parent: Node, child_name: String = "") -> Result:
	if not is_instance_valid(node):
		return Result.err("Mount failed: node is invalid.")
	if not is_instance_valid(parent):
		return Result.err("Mount failed: parent is invalid.")
	if node.is_queued_for_deletion() or node.get_parent() != null:
		return Result.err("Mount failed: '%s' is queued for deletion or already has a parent." % node.name)

	# 入树前命名，避免入树后再改名。
	if not child_name.is_empty():
		node.name = child_name

	parent.add_child(node)
	return Result.ok(node)


## 挂载必须成功的节点。失败 [code]push_error[/code] + [code]assert[/code]，并返回 [param node]。[br]
## 不走 App.log：本工具不依赖任何服务。
static func mount_required(node: Node, parent: Node, child_name: String = "") -> Node:
	var res := mount(node, parent, child_name)
	if res.is_err():
		push_error("mount_required failed: %s" % res.error)
		assert(false, "mount_required failed: %s" % res.error)
	return node


## 实例化 [param scene] 并挂到 [param parent]。挂载失败会释放实例，避免泄漏。
static func spawn(scene: PackedScene, parent: Node, child_name: String = "") -> Result:
	if not is_instance_valid(scene):
		return Result.err("Spawn failed: scene is invalid.")

	var instance := scene.instantiate()
	if instance == null:
		return Result.err("Spawn failed: instantiate() returned null.")

	var res := mount(instance, parent, child_name)
	if res.is_err():
		instance.queue_free()
	return res


## 复制 [param node] 并挂到 [param parent]。挂载失败会释放副本。
static func clone(node: Node, parent: Node, child_name: String = "") -> Result:
	if not is_instance_valid(node):
		return Result.err("Clone failed: node is invalid.")
	if not is_instance_valid(parent):
		return Result.err("Clone failed: parent is invalid.")
	if node.is_queued_for_deletion():
		return Result.err("Clone failed: '%s' is queued for deletion." % node.name)

	var copy := node.duplicate()
	if copy == null:
		return Result.err("Clone failed: duplicate() returned null.")

	var res := mount(copy, parent, child_name)
	if res.is_err():
		copy.queue_free()
	return res


## 延迟销毁。无效或已排队则忽略，避免重复 [code]queue_free[/code]。
## 参数设为 Variant（无强类型约束），避免传入已销毁的幽灵指针时触发 GDScript 强类型参数检查崩溃。
static func safe_free(node: Variant) -> void:
	if not is_instance_valid(node):
		return
	var n := node as Node
	if n != null and not n.is_queued_for_deletion():
		n.queue_free()


## 销毁 [param parent] 的直接子节点。倒序遍历。[param immediate] 为 true 时同步 [code]free()[/code]。
static func clear_children(parent: Node, immediate: bool = false) -> void:
	if not is_instance_valid(parent):
		return
	var children := parent.get_children()
	for i in range(children.size() - 1, -1, -1):
		var child: Node = children[i]
		if not is_instance_valid(child) or child.is_queued_for_deletion():
			continue
		if immediate:
			child.free()
		else:
			safe_free(child)


## 等待 [param node] 的 [code]ready[/code]。已 ready 立即成功；须已入树。[br]
##
## [codeblock]
## var mount_res := NodeUtils.mount(widget, self)
## if mount_res.is_err():
##     return
## var ready_res := await NodeUtils.wait_ready(mount_res.value)
## if ready_res.is_err():
##     return
## widget.refresh()
## [/codeblock]
static func wait_ready(node: Node, timeout_sec: float = 5.0) -> Result:
	if not is_instance_valid(node):
		return Result.err("Wait ready failed: node is invalid.")
	if node.is_node_ready():
		return Result.ok()
	if not node.is_inside_tree():
		return Result.err("Wait ready failed: node is not in the scene tree.")

	var tree := node.get_tree()
	if tree == null:
		return Result.err("Wait ready failed: SceneTree is unavailable.")

	var elapsed := 0.0
	while elapsed < timeout_sec:
		if not is_instance_valid(node):
			return Result.err("Wait ready failed: node was freed.")
		if node.is_node_ready():
			return Result.ok()
		await tree.process_frame
		elapsed += tree.get_process_delta_time()

	if not is_instance_valid(node):
		return Result.err("Wait ready failed: node was freed.")
	if node.is_node_ready():
		return Result.ok()
	return Result.err("Wait ready failed: timed out (%.1fs)." % timeout_sec)
#endregion
