class_name SceneStack
extends RefCounted

## 场景栈与生命周期驱动内核 (Scene Stack Kernel)。
##
## [b]核心职责与设计原理：[/b]
## 1. [b]栈式空间管理[/b]：维护游戏顶层活动场景的线性栈结构（[code]_stack[/code]）；
## 2. [b]收环保护机制 (Loop Resolution)[/b]：同一场景路径（path）在栈内最多仅允许出现一次；
## 3. [b]生命周期编排与无缝流式衔接[/b]：
##    - 与 [SceneTransition] 深度联动，在新旧场景并存于树上的微秒窗口期内，执行 Apple / 字节跳动标准的连续空间位移与景深缩放；
##    - 动画完成后平滑释放或休眠旧场景，杜绝任何视觉断层；
## 4. [b]深度分支休眠与唤醒[/b]：休眠场景自动停用逻辑（PROCESS_MODE_DISABLED）并递归隐藏视图分支。

#region Constants & Members
const MAX_DEPTH := 8 ## 最大场景栈深度限制

var _host_node: Node                  ## 宿主服务节点引用
var _host: Node                       ## 场景挂载容器节点 (SceneHost)
var _transition: SceneTransition      ## 流式转场动画控制器
var _stack: Array[Dictionary] = []    ## 场景栈数据：Array[{path: String, scene: BaseScene}]
var _asset_service: BaseAssetSystem  ## 资源加载系统
#endregion


#region Lifecycle
func _init(host_node: Node, transition: SceneTransition, asset_service: BaseAssetSystem = null) -> void:
	_host_node = host_node
	_transition = transition
	_asset_service = asset_service
	_host = Node.new()
	NodeUtils.mount_required(_host, _host_node, "SceneHost")
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
#endregion


#region Stack Operations
## 替换栈顶场景 (Replace)
func replace(path: String, params: Dictionary, transition: int) -> Result:
	# 1. 目标已在栈下方：收环到那一层
	var idx := _index_of(path)
	if idx >= 0 and idx < _stack.size() - 1:
		return await pop_to(idx, params, transition)

	# 2. 异步实例化新场景
	var loaded := await _instantiate(path)
	if loaded.is_err():
		return loaded
	var new_scene: BaseScene = loaded.value
	var res := _mount_scene(new_scene)
	if res.is_err():
		return res

	var old_scene := current()

	# 3. 激活新场景并入栈
	_wake(new_scene)
	_stack.append({path = path, scene = new_scene})
	@warning_ignore("redundant_await")
	await new_scene._on_enter(params)

	# 4. 新旧场景在树上执行连续流式转场动画 (Apple 景深缩放交融)
	if old_scene and is_instance_valid(old_scene):
		await _transition.play(old_scene, new_scene, transition, "replace")
		# 动画结束，卸载旧场景
		if is_instance_valid(old_scene):
			@warning_ignore("redundant_await")
			await old_scene._on_exit()
			_remove_from_stack(old_scene)
			NodeUtils.safe_free(old_scene)

	return Result.ok()


## 压入新栈层 (Push)
func push(path: String, params: Dictionary, transition: int) -> Result:
	# 1. 目标已在栈中：栈顶则忽略；下方则收环
	var idx := _index_of(path)
	if idx >= 0:
		if idx == _stack.size() - 1:
			return Result.ok()
		return await pop_to(idx, params, transition)

	# 2. 深度溢出安全检查
	if _stack.size() >= MAX_DEPTH:
		return Result.err("Stack is full (max %d)." % MAX_DEPTH)

	# 3. 异步实例化新场景
	var loaded := await _instantiate(path)
	if loaded.is_err():
		return loaded
	var new_scene: BaseScene = loaded.value
	var res := _mount_scene(new_scene)
	if res.is_err():
		return res

	var old_scene := current()
	if old_scene and is_instance_valid(old_scene):
		@warning_ignore("redundant_await")
		await old_scene._on_pause()

	# 4. 激活新场景入栈
	_wake(new_scene)
	_stack.append({path = path, scene = new_scene})
	@warning_ignore("redundant_await")
	await new_scene._on_enter(params)

	# 5. 执行 iOS 经典视差侧滑推进动画
	if old_scene and is_instance_valid(old_scene):
		await _transition.play(old_scene, new_scene, transition, "push")
		_sleep(old_scene)

	return Result.ok()


## 弹出栈顶场景 (Pop)
func pop(params: Dictionary, transition: int) -> Result:
	if _stack.size() < 2:
		return Result.err("Stack is too shallow to pop.")

	var top_entry: Dictionary = _stack.pop_back()
	var top_scene: BaseScene = top_entry.get("scene")
	var bottom_scene := current()

	# 1. 唤醒下层场景并触发 resume
	if bottom_scene and is_instance_valid(bottom_scene):
		_wake(bottom_scene)
		@warning_ignore("redundant_await")
		await bottom_scene._on_resume(params)

	# 2. 触发顶层 exit 钩子并执行流式侧滑退出动画
	if top_scene and is_instance_valid(top_scene):
		@warning_ignore("redundant_await")
		await top_scene._on_exit()
		await _transition.play(top_scene, bottom_scene, transition, "pop")
		NodeUtils.safe_free(top_scene)

	return Result.ok()


## 出栈收环到指定下标 idx 层 (Pop To)
func pop_to(idx: int, params: Dictionary, _transition_type: int = SceneTransitionType.AUTO) -> Result:
	while _stack.size() > idx + 1:
		var top_entry: Dictionary = _stack.pop_back()
		var top_scene: BaseScene = top_entry.get("scene")
		if is_instance_valid(top_scene):
			@warning_ignore("redundant_await")
			await top_scene._on_exit()
			NodeUtils.safe_free(top_scene)

	var target_scene := current()
	if target_scene and is_instance_valid(target_scene):
		_wake(target_scene)
		@warning_ignore("redundant_await")
		await target_scene._on_resume(params)

	return Result.ok()


## 绑定初始场景为栈底 (Bind)
func bind(path: String, scene: BaseScene, params: Dictionary) -> Result:
	if path.is_empty():
		return Result.err("Bind path is empty.")
	if not is_instance_valid(scene):
		return Result.err("Bind scene is invalid.")
	if not _stack.is_empty():
		return Result.err("Stack is not empty.")
	if scene.get_parent() != _host:
		if scene.is_inside_tree():
			await scene.get_tree().process_frame
		if is_instance_valid(scene) and scene.get_parent() != _host:
			scene.reparent(_host, false)
	if not is_instance_valid(scene):
		return Result.err("Bind scene is invalid.")
	_wake(scene)
	_stack.append({path = path, scene = scene})
	@warning_ignore("redundant_await")
	await scene._on_enter(params)
	return Result.ok()
#endregion


#region Internal - Helpers
func _mount_scene(scene: BaseScene) -> Result:
	var res := NodeUtils.mount(scene, _host)
	if res.is_err():
		NodeUtils.safe_free(scene)
		return res
	return Result.ok()


func _remove_from_stack(scene: BaseScene) -> void:
	for i in range(_stack.size() - 1, -1, -1):
		if _stack[i].get("scene") == scene:
			_stack.remove_at(i)
			break


func _sleep(scene: BaseScene) -> void:
	if not is_instance_valid(scene):
		return
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	_set_branch_visible(scene, false)


func _wake(scene: BaseScene) -> void:
	if not is_instance_valid(scene):
		return
	scene.process_mode = Node.PROCESS_MODE_INHERIT
	_set_branch_visible(scene, true)


func _set_branch_visible(node: Node, on: bool) -> void:
	if node is CanvasItem:
		(node as CanvasItem).visible = on
	elif node is Node3D:
		(node as Node3D).visible = on
	elif node is CanvasLayer:
		(node as CanvasLayer).visible = on
	elif node is Window:
		(node as Window).visible = on
		return
	for child in node.get_children():
		if node is CanvasItem and child is CanvasItem:
			continue
		if node is Node3D and child is Node3D:
			continue
		if node is CanvasLayer and child is CanvasItem:
			continue
		_set_branch_visible(child, on)


func _instantiate(path: String) -> Result:
	var packed: PackedScene = null
	if _asset_service != null:
		var loaded := await _asset_service.load(path)
		if loaded.is_err():
			return loaded
		packed = loaded.value as PackedScene
	else:
		if not ResourceLoader.exists(path):
			return Result.err("Scene file not found: %s" % path)
		packed = ResourceLoader.load(path) as PackedScene

	if packed == null:
		return Result.err("Not a PackedScene: %s." % path)

	var node := packed.instantiate()
	if node is BaseScene:
		return Result.ok(node)
	if is_instance_valid(node):
		node.free()
	return Result.err("Root is not a BaseScene: %s." % path)


func _index_of(path: String) -> int:
	if path.is_empty():
		return -1
	for i in _stack.size():
		if _stack[i]["path"] == path:
			return i
	return -1
#endregion
