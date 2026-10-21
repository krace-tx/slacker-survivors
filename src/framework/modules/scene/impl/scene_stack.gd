class_name SceneStack
extends RefCounted

## 场景栈与生命周期驱动内核 (Scene Stack Kernel)。[br]
##
## [b]核心职责与设计原理（第一性原理）：[/b][br]
## 1. [b]栈式空间管理与收环保护 (Loop Resolution)[/b]：维护游戏顶层活动场景的线性栈结构（[code]_stack[/code]），
##    同一场景路径（path）在栈内最多仅出现一次；[br]
## 2. [b]严谨生命周期时序[/b]：离开场景先冻结帧步进与取消任务，待流式视觉转场动画完整播放完毕后再触发 [method BaseScene._on_exit] 并释放，
##    杜绝“转场前过早清空画面”或“新旧场景并发跑帧逻辑”；[br]
## 3. [b]无损显隐快照隔离（Snapshot Visibility Isolation）[/b]：休眠场景时精准记录原本可见的顶层视觉节点，
##    唤醒时仅恢复被休眠隐藏的节点，100% 保护场景内部默认隐藏子节点（如结算弹窗/遮罩）不被误开启。

#region Constants & Error Codes
const MAX_DEPTH := 8 ## 最大场景栈深度限制

const ERR_EMPTY_PATH := "Scene.EmptyPath"
const ERR_INVALID_SCENE := "Scene.InvalidScene"
const ERR_NOT_FOUND := "Scene.NotFound"
const ERR_INVALID_ROOT := "Scene.InvalidRoot"
const ERR_STACK_OVERFLOW := "Scene.StackOverflow"
const ERR_STACK_UNDERFLOW := "Scene.StackUnderflow"
const ERR_STACK_NOT_EMPTY := "Scene.StackNotEmpty"

var _host_node: Node                  ## 宿主服务节点引用
var _host: Node                       ## 场景挂载容器节点 (SceneHost)
var _transition: SceneTransition      ## 流式转场动画控制器
var _stack: Array[Dictionary] = []    ## 场景栈数据：Array[{path: String, scene: BaseScene, hidden_nodes: Array[Node]}]
var _asset_service: BaseAssetSystem  ## 资源加载系统
var _hook_depth: int = 0              ## 当前所处的生命周期钩子调用深度（用于检测钩子内重入导航）
#endregion


#region Lifecycle
func _init(host_node: Node, transition: SceneTransition, asset_service: BaseAssetSystem = null) -> void:
	_host_node = host_node
	_transition = transition
	_asset_service = asset_service
	_host = Node.new()
	NodeUtils.mount_required(_host, _host_node, "SceneHost")


func dispose() -> void:
	for i in range(_stack.size() - 1, -1, -1):
		var scene: BaseScene = _stack[i].get("scene")
		if is_instance_valid(scene):
			scene.cancel_tasks("SceneStack disposed.")
			scene.queue_free()
	_stack.clear()
	if is_instance_valid(_host):
		_host.queue_free()
	_host = null
#endregion


#region Stack Queries
## 获取当前栈顶场景实例；若栈为空则返回 null
func current() -> BaseScene:
	if _stack.is_empty():
		return null
	return _stack.back()["scene"] as BaseScene


## 获取当前场景栈深度
func depth() -> int:
	return _stack.size()


## 获取当前栈顶场景的资源路径
func current_path() -> String:
	if _stack.is_empty():
		return ""
	return String(_stack.back()["path"])


## 场景栈是否为空
func is_empty() -> bool:
	return _stack.is_empty()


## 当前是否正处于场景生命周期钩子（_on_enter / _on_resume / _on_pause / _on_exit）执行栈中
func is_in_lifecycle_hook() -> bool:
	return _hook_depth > 0
#endregion


#region Stack Operations
## 替换栈顶场景 (Replace)
func replace(path: String, params: BaseParams, transition: int) -> Result:
	if path.is_empty():
		return Result.err_ex(ERR_EMPTY_PATH, "Replace failed: scene path is empty.", {}, false, null, FrameworkError.CATEGORY_PARAM)

	# 1. 目标已在栈下方（非栈顶）：收环弹出到那一层并带转场动画
	var idx := _index_of(path)
	if idx >= 0 and idx < _stack.size() - 1:
		return await pop_to(idx, params, transition)

	# 2. 异步实例化并挂载新场景
	var loaded := await _instantiate(path)
	if loaded.is_err():
		return loaded
	var new_scene: BaseScene = loaded.value
	var mount_res := _mount_scene(new_scene)
	if mount_res.is_err():
		return mount_res

	# 3. 弹出旧栈顶并立即冻结其帧逻辑与异步任务（保持画面可见以供转场交融）
	var old_entry: Dictionary = _stack.pop_back() if not _stack.is_empty() else {}
	var old_scene: BaseScene = old_entry.get("scene") if not old_entry.is_empty() else null
	if is_instance_valid(old_scene):
		old_scene.cancel_tasks("Scene replaced.")
		old_scene.process_mode = Node.PROCESS_MODE_DISABLED

	# 4. 新场景入栈并执行 _on_enter
	var new_entry := {"path": path, "scene": new_scene, "hidden_nodes": [] as Array[Node]}
	_stack.append(new_entry)
	_wake_entry(new_entry)
	await _invoke_hook_with_params(new_scene, &"_on_enter", params)

	# 5. 新旧场景执行连续流式转场动画（若 _on_enter 内部未发生重入重定向），动画结束后触发旧场景 _on_exit 并销毁
	if is_instance_valid(old_scene):
		if current() == new_scene and is_instance_valid(new_scene):
			await _transition.play(old_scene, new_scene, transition, "replace")
		if is_instance_valid(old_scene):
			await _invoke_hook_no_args(old_scene, &"_on_exit")
			old_scene.cancel_tasks("Scene exited after replace.")
			NodeUtils.safe_free(old_scene)

	return Result.ok()


## 压入新栈层 (Push)
func push(path: String, params: BaseParams, transition: int) -> Result:
	if path.is_empty():
		return Result.err_ex(ERR_EMPTY_PATH, "Push failed: scene path is empty.", {}, false, null, FrameworkError.CATEGORY_PARAM)

	# 1. 目标已在栈中：栈顶则幂等忽略；下方则收环回退
	var idx := _index_of(path)
	if idx >= 0:
		if idx == _stack.size() - 1:
			return Result.ok()
		return await pop_to(idx, params, transition)

	# 2. 深度溢出安全检查
	if _stack.size() >= MAX_DEPTH:
		return Result.err_ex(
			ERR_STACK_OVERFLOW,
			"Push failed: scene stack is full (max %d)." % MAX_DEPTH,
			{"path": path, "max_depth": MAX_DEPTH},
			false,
			null,
			FrameworkError.CATEGORY_STATE
		)

	# 3. 异步实例化并挂载新场景
	var loaded := await _instantiate(path)
	if loaded.is_err():
		return loaded
	var new_scene: BaseScene = loaded.value
	var mount_res := _mount_scene(new_scene)
	if mount_res.is_err():
		return mount_res

	var old_entry: Dictionary = _stack.back() if not _stack.is_empty() else {}
	var old_scene: BaseScene = old_entry.get("scene") if not old_entry.is_empty() else null
	if is_instance_valid(old_scene):
		await _invoke_hook_no_args(old_scene, &"_on_pause")
		old_scene.process_mode = Node.PROCESS_MODE_DISABLED

	# 4. 激活新场景入栈
	var new_entry := {"path": path, "scene": new_scene, "hidden_nodes": [] as Array[Node]}
	_stack.append(new_entry)
	_wake_entry(new_entry)
	await _invoke_hook_with_params(new_scene, &"_on_enter", params)

	# 5. 执行进场淡入覆盖动画（若 _on_enter 内部未发生重入重定向），完成后快照休眠旧场景
	if is_instance_valid(old_scene):
		if current() == new_scene and is_instance_valid(new_scene):
			await _transition.play(old_scene, new_scene, transition, "push")
		if _stack.has(old_entry) and current() != old_scene:
			_sleep_entry(old_entry)

	return Result.ok()


## 弹出栈顶场景 (Pop)
func pop(params: BaseParams, transition: int) -> Result:
	if _stack.size() < 2:
		return Result.err_ex(
			ERR_STACK_UNDERFLOW,
			"Pop failed: scene stack is too shallow to pop (depth=%d)." % _stack.size(),
			{"depth": _stack.size()},
			false,
			null,
			FrameworkError.CATEGORY_STATE
		)
	return await pop_to(_stack.size() - 2, params, transition)


## 出栈收环到指定下标 idx 层 (Pop To)，具备完整的顶层与目标层流式退场动画
func pop_to(idx: int, params: BaseParams, transition: int = SceneTransitionType.AUTO) -> Result:
	if idx < 0 or idx >= _stack.size() - 1:
		return Result.err_ex(
			ERR_STACK_UNDERFLOW,
			"Pop_to failed: invalid target index %d (depth=%d)." % [idx, _stack.size()],
			{"target_idx": idx, "depth": _stack.size()},
			false,
			null,
			FrameworkError.CATEGORY_PARAM
		)

	# 1. 取出当前最顶层活动场景并冻结帧逻辑（保留画面供稍后播放退场溶解动画）
	var top_entry: Dictionary = _stack.pop_back()
	var top_scene: BaseScene = top_entry.get("scene")
	if is_instance_valid(top_scene):
		top_scene.cancel_tasks("Scene popped.")
		top_scene.process_mode = Node.PROCESS_MODE_DISABLED

	# 2. 若跨多层收环，清理中间已处于隐藏休眠态的夹层场景
	while _stack.size() > idx + 1:
		var mid_entry: Dictionary = _stack.pop_back()
		var mid_scene: BaseScene = mid_entry.get("scene")
		if is_instance_valid(mid_scene):
			mid_scene.cancel_tasks("Scene popped by loop resolution.")
			await _invoke_hook_no_args(mid_scene, &"_on_exit")
			NodeUtils.safe_free(mid_scene)

	# 3. 唤醒目标下层场景并触发 _on_resume
	var target_entry: Dictionary = _stack.back()
	var target_scene: BaseScene = target_entry.get("scene")
	if is_instance_valid(target_scene):
		_wake_entry(target_entry)
		await _invoke_hook_with_params(target_scene, &"_on_resume", params)

	# 4. 播放顶层场景向目标场景的退场溶解转场，动画完成后再触发顶层 _on_exit 并销毁
	if is_instance_valid(top_scene):
		await _transition.play(top_scene, target_scene, transition, "pop")
		if is_instance_valid(top_scene):
			await _invoke_hook_no_args(top_scene, &"_on_exit")
			NodeUtils.safe_free(top_scene)

	return Result.ok()


## 绑定初始场景为栈底 (Bind)
func bind(path: String, scene: BaseScene, params: BaseParams) -> Result:
	if path.is_empty():
		return Result.err_ex(ERR_EMPTY_PATH, "Bind failed: path is empty.", {}, false, null, FrameworkError.CATEGORY_PARAM)
	if not is_instance_valid(scene):
		return Result.err_ex(ERR_INVALID_SCENE, "Bind failed: scene instance is invalid.", {"path": path}, false, null, FrameworkError.CATEGORY_PARAM)
	if not _stack.is_empty():
		return Result.err_ex(ERR_STACK_NOT_EMPTY, "Bind failed: scene stack is not empty.", {"path": path, "depth": _stack.size()}, false, null, FrameworkError.CATEGORY_STATE)

	if scene.get_parent() != _host:
		if scene.is_inside_tree():
			await scene.get_tree().process_frame
		if is_instance_valid(scene) and scene.get_parent() != _host:
			scene.reparent(_host, false)

	if not is_instance_valid(scene):
		return Result.err_ex(ERR_INVALID_SCENE, "Bind failed: scene was freed during reparent.", {"path": path}, false, null, FrameworkError.CATEGORY_STATE)

	var entry := {"path": path, "scene": scene, "hidden_nodes": [] as Array[Node]}
	_stack.append(entry)
	_wake_entry(entry)
	await _invoke_hook_with_params(scene, &"_on_enter", params)
	return Result.ok()
#endregion


#region Internal - Lifecycle Hook Invokers & Snapshot Visibility
func _invoke_hook_with_params(scene: BaseScene, method: StringName, params: BaseParams) -> void:
	if not is_instance_valid(scene):
		return
	_hook_depth += 1
	@warning_ignore("redundant_await")
	await scene.call(method, params)
	_hook_depth -= 1


func _invoke_hook_no_args(scene: BaseScene, method: StringName) -> void:
	if not is_instance_valid(scene):
		return
	_hook_depth += 1
	@warning_ignore("redundant_await")
	await scene.call(method)
	_hook_depth -= 1


func _mount_scene(scene: BaseScene) -> Result:
	var res := NodeUtils.mount(scene, _host)
	if res.is_err():
		NodeUtils.safe_free(scene)
		return res
	return Result.ok()


func _sleep_entry(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	var scene: BaseScene = entry.get("scene")
	if not is_instance_valid(scene):
		return
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	var hidden_nodes: Array[Node] = []
	_snapshot_and_hide_branch(scene, hidden_nodes)
	entry["hidden_nodes"] = hidden_nodes


func _wake_entry(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	var scene: BaseScene = entry.get("scene")
	if not is_instance_valid(scene):
		return
	scene.process_mode = Node.PROCESS_MODE_INHERIT
	var hidden_nodes: Array = entry.get("hidden_nodes", [])
	for n in hidden_nodes:
		if is_instance_valid(n):
			_set_single_node_visible(n, true)
	hidden_nodes.clear()


## 仅隐藏当前处于可见状态的顶层可视分支节点，并将其记录到 out_hidden，避免唤醒时误开启原本隐藏的节点。
func _snapshot_and_hide_branch(node: Node, out_hidden: Array[Node]) -> void:
	if node is CanvasItem:
		var ci := node as CanvasItem
		if ci.visible:
			ci.visible = false
			out_hidden.append(ci)
		return
	if node is Node3D:
		var n3d := node as Node3D
		if n3d.visible:
			n3d.visible = false
			out_hidden.append(n3d)
		return
	if node is CanvasLayer:
		var cl := node as CanvasLayer
		if cl.visible:
			cl.visible = false
			out_hidden.append(cl)
		return
	if node is Window:
		var win := node as Window
		if win.visible:
			win.visible = false
			out_hidden.append(win)
		return

	for child in node.get_children():
		_snapshot_and_hide_branch(child, out_hidden)


func _set_single_node_visible(node: Node, on: bool) -> void:
	if node is CanvasItem:
		(node as CanvasItem).visible = on
	elif node is Node3D:
		(node as Node3D).visible = on
	elif node is CanvasLayer:
		(node as CanvasLayer).visible = on
	elif node is Window:
		(node as Window).visible = on


func _instantiate(path: String) -> Result:
	var packed: PackedScene = null
	if _asset_service != null:
		var loaded := await _asset_service.load(path)
		if loaded.is_err():
			return loaded
		packed = loaded.value as PackedScene
	else:
		if not ResourceLoader.exists(path):
			return Result.err_ex(
				ERR_NOT_FOUND,
				"Scene file not found: %s" % path,
				{"path": path},
				false,
				ERR_FILE_NOT_FOUND,
				FrameworkError.CATEGORY_NOT_FOUND
			)
		packed = ResourceLoader.load(path) as PackedScene

	if packed == null:
		return Result.err_ex(
			ERR_INVALID_SCENE,
			"Resource is not a PackedScene: %s." % path,
			{"path": path},
			false,
			null,
			FrameworkError.CATEGORY_VALIDATION
		)

	var node := packed.instantiate()
	if node is BaseScene:
		return Result.ok(node)
	if is_instance_valid(node):
		node.free()
	return Result.err_ex(
		ERR_INVALID_ROOT,
		"Scene root node must extend BaseScene: %s." % path,
		{"path": path},
		false,
		null,
		FrameworkError.CATEGORY_VALIDATION
	)


func _index_of(path: String) -> int:
	if path.is_empty():
		return -1
	for i in _stack.size():
		if _stack[i]["path"] == path:
			return i
	return -1
#endregion
