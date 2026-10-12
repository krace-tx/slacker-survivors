class_name AsyncUtils
extends RefCounted

## 异步任务并发编排与安全调度工具库。
## 核心原则：安全第一（防御性校验、生命周期感知、无效任务防死锁、上下文防释放）。

#region Public API
## 并发执行一组异步任务（Callable），挂起直到所有任务全部执行完毕（等价于 Python asyncio.gather）。[br]
## [param tasks]：待并发执行的 Callable 数组（函数内部可包含 await 挂起逻辑）。[br]
## [param context]：可选的生命周期上下文节点。若提供，在节点销毁或脱离场景树时自动安全终止等待。[br]
## [param timeout_seconds]：可选的超时上限（秒），<= 0.0 表示不设硬性超时限制。[br]
## [b]返回：[/b] 按任务顺序收集的结果数组（若任务执行失败或未提供返回值则对应索引为 null）。
static func gather(tasks: Array[Callable], context: Node = null, timeout_seconds: float = 0.0) -> Array:
	if tasks.is_empty():
		return []

	# 1. 初始上下文生命周期防御校验
	if context != null and not is_instance_valid(context):
		return []

	var task_count := tasks.size()
	var results: Array = []
	results.resize(task_count)
	var pending := [task_count]

	# 2. 遍历分发任务，严格校验每一个 Callable 的有效性
	for i in range(task_count):
		var task := tasks[i]
		if not task.is_valid() or task.is_null():
			# 无效 Callable：直接记为 null 并扣减等待计数，避免死锁挂起
			results[i] = null
			pending[0] -= 1
			continue

		(func(task_index: int, callable: Callable):
			var res: Variant = null
			if callable.is_valid():
				res = await callable.call()
			results[task_index] = res
			pending[0] -= 1
		).call(i, task)

	# 3. 获取场景树安全引用
	var tree := _get_safe_tree(context)
	if tree == null:
		return results

	var elapsed := 0.0

	# 4. 安全等待循环（严格监测生命周期、场景树有效性与超时）
	while pending[0] > 0:
		# 节点生命周期防御：节点已被销毁或脱离场景树，立即安全中断
		if context != null:
			if not is_instance_valid(context) or not context.is_inside_tree():
				break

		# 超时防御：防止子任务永久挂起导致主线程死锁
		if timeout_seconds > 0.0 and elapsed >= timeout_seconds:
			break

		if tree == null:
			break

		await tree.process_frame
		elapsed += tree.root.get_process_delta_time() if (tree.root != null) else 0.016

	return results


## 并发执行一组异步任务，只要有任意一个任务完成立即返回其结果（等价于 Python asyncio.wait FIRST_COMPLETED）。[br]
## [param tasks]：待并发执行的 Callable 数组。[br]
## [param context]：可选的生命周期上下文节点。[br]
## [param timeout_seconds]：可选的超时上限（秒），<= 0.0 表示不设硬性超时限制。
static func wait_first(tasks: Array[Callable], context: Node = null, timeout_seconds: float = 0.0) -> Variant:
	if tasks.is_empty():
		return null

	if context != null and not is_instance_valid(context):
		return null

	var valid_task_count := 0
	var done := [false]
	var winner_result: Array = [null]

	for task in tasks:
		if not task.is_valid() or task.is_null():
			continue

		valid_task_count += 1
		(func(callable: Callable):
			var res: Variant = null
			if callable.is_valid():
				res = await callable.call()
			if not done[0]:
				done[0] = true
				winner_result[0] = res
		).call(task)

	if valid_task_count == 0:
		return null

	var tree := _get_safe_tree(context)
	if tree == null:
		return winner_result[0]

	var elapsed := 0.0

	while not done[0]:
		if context != null:
			if not is_instance_valid(context) or not context.is_inside_tree():
				break

		if timeout_seconds > 0.0 and elapsed >= timeout_seconds:
			break

		if tree == null:
			break

		await tree.process_frame
		elapsed += tree.root.get_process_delta_time() if (tree.root != null) else 0.016

	return winner_result[0]


## 异步挂起休眠指定秒数（等价于 Python asyncio.sleep）。[br]
## [param seconds]：休眠秒数（<= 0.0 时等待单帧 process_frame）。[br]
## [param context]：可选的生命周期上下文节点，提供 Use-After-Free 保护。
static func sleep(seconds: float = 0.0, context: Node = null) -> void:
	if context != null and not is_instance_valid(context):
		return

	var tree := _get_safe_tree(context)
	if tree == null:
		return

	if seconds <= 0.0:
		await tree.process_frame
	else:
		# process_always=false：随 SceneTree 暂停而暂停，避免暂停期间仍把等待走完
		await tree.create_timer(seconds, false).timeout

	# 恢复后再次防御校验节点有效性
	if context != null and not is_instance_valid(context):
		return


## 绑定节点生命周期的安全等待。挂起 [param seconds] 秒；恢复后若 [param node] 已销毁或脱离场景树则返回失败。[br]
##
## [codeblock]
## var res := await AsyncUtils.wait_safe(self, 2.0)
## if res.is_err():
##     return
## [/codeblock]
static func wait_safe(node: Node, seconds: float) -> Result:
	if not is_instance_valid(node):
		return Result.err("Wait failed: node is invalid.")
	var tree := node.get_tree()
	if tree == null:
		return Result.err("Wait failed: node is not in the scene tree.")

	await tree.create_timer(seconds, false).timeout

	if not is_instance_valid(node) or not node.is_inside_tree():
		return Result.err("Wait failed: node was freed or left tree.")
	return Result.ok()
#endregion


#region Internal Helpers
## 安全获取 SceneTree 引用，确保在引擎退出或节点脱离时不会发生空指针
static func _get_safe_tree(context: Node = null) -> SceneTree:
	if is_instance_valid(context) and context.is_inside_tree():
		var tree := context.get_tree()
		if tree != null:
			return tree

	var main_loop := Engine.get_main_loop()
	return main_loop as SceneTree
#endregion
