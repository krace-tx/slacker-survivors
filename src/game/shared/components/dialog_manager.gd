class_name DialogManager
extends RefCounted

## 游戏业务层模态弹窗管理器。
## 维护活动弹窗列表（后入先出堆栈），并在顶层弹窗正下方调度全屏暗色背景遮罩。
## 自动监听 [Bus.app_back_pressed] 事件，实现物理返回键/ESC优先关闭栈顶活动弹窗。

static var _stack: Array[Control] = []
static var _backdrop: ColorRect = null
static var _listener_connected: bool = false


## 打开一个模态弹窗。
## [param path_or_scene] 可以是弹窗 .tscn 路径 (String) 或已加载的 PackedScene。
## [param params] 传递给弹窗的数据入参。
## [param parent] 挂载的目标节点；若为空则默认挂载到 App.ui.get_layer(BaseUISystem.Layer.POPUP)。
## @return 返回实例化的弹窗根节点 Control。
static func open(path_or_scene: Variant, params: Dictionary = {}, parent: Node = null) -> Control:
	_ensure_listener()

	var packed: PackedScene = null
	if path_or_scene is String:
		var path := path_or_scene as String
		if App != null and App.asset != null:
			var res := await App.asset.load(path)
			if res.is_ok():
				packed = res.value as PackedScene
		if packed == null and ResourceLoader.exists(path):
			packed = ResourceLoader.load(path) as PackedScene
	elif path_or_scene is PackedScene:
		packed = path_or_scene

	if packed == null:
		push_error("[DialogManager] Failed to load dialog: %s" % str(path_or_scene))
		return null

	var instance := packed.instantiate()
	if not (instance is Control):
		instance.queue_free()
		push_error("[DialogManager] Dialog root must be a Control: %s" % str(path_or_scene))
		return null

	var popup_ctrl := instance as Control
	var mount_target: Node = parent
	if mount_target == null and App != null and App.ui != null:
		mount_target = App.ui.get_layer(BaseUISystem.Layer.POPUP)

	if mount_target == null:
		var scene_tree := Engine.get_main_loop() as SceneTree
		if scene_tree != null and scene_tree.current_scene != null:
			mount_target = scene_tree.current_scene

	if mount_target == null:
		popup_ctrl.queue_free()
		push_error("[DialogManager] No valid mount target available for dialog.")
		return null

	_ensure_backdrop(mount_target)
	mount_target.add_child(popup_ctrl)
	_stack.append(popup_ctrl)
	_update_backdrop_state()

	if popup_ctrl is BaseDialog:
		(popup_ctrl as BaseDialog).open(params)
	else:
		popup_ctrl.visible = true

	return popup_ctrl


## 关闭指定弹窗（若为空则关闭栈顶）。
static func close(dialog: Control = null) -> void:
	if dialog == null:
		close_top()
		return

	if _stack.has(dialog):
		_stack.erase(dialog)

	_update_backdrop_state()

	if is_instance_valid(dialog):
		dialog.queue_free()


## 关闭当前栈顶活动弹窗。
static func close_top() -> bool:
	# 清理已释放的无效引用
	_stack = _stack.filter(func(d: Control) -> bool: return is_instance_valid(d))
	if _stack.is_empty():
		return false

	var top: Control = _stack.pop_back()
	_update_backdrop_state()

	if is_instance_valid(top):
		if top is BaseDialog:
			(top as BaseDialog).close()
		else:
			top.queue_free()
		return true

	return false


## 查询当前是否有展示中的模态弹窗。
static func has_modal() -> bool:
	_stack = _stack.filter(func(d: Control) -> bool: return is_instance_valid(d))
	return not _stack.is_empty()


## 清理所有打开中的弹窗与遮罩。
static func clear() -> void:
	for dialog in _stack:
		if is_instance_valid(dialog):
			dialog.queue_free()
	_stack.clear()
	_update_backdrop_state()


#region Internal
static func _ensure_listener() -> void:
	if _listener_connected:
		return
	_listener_connected = true
	if Bus != null and not Bus.app_back_pressed.is_connected(_on_back_pressed):
		Bus.app_back_pressed.connect(_on_back_pressed)


static func _on_back_pressed() -> void:
	if has_modal():
		var top: Control = _stack.back()
		if top is BaseDialog:
			if (top as BaseDialog).close_on_back:
				close_top()
		else:
			close_top()


static func _ensure_backdrop(mount_target: Node) -> void:
	if _backdrop != null and is_instance_valid(_backdrop):
		if _backdrop.get_parent() != mount_target:
			_backdrop.get_parent().remove_child(_backdrop)
			mount_target.add_child(_backdrop)
		return

	_backdrop = ColorRect.new()
	_backdrop.name = "BackdropMask"
	_backdrop.color = Color(0, 0, 0, 0.6)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.visible = false
	_backdrop.gui_input.connect(_on_backdrop_gui_input)
	mount_target.add_child(_backdrop)


static func _on_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _stack.is_empty():
			var top: Control = _stack.back()
			if top is BaseDialog and (top as BaseDialog).close_on_backdrop:
				(top as BaseDialog).close()


static func _update_backdrop_state() -> void:
	_stack = _stack.filter(func(d: Control) -> bool: return is_instance_valid(d))
	if _backdrop == null or not is_instance_valid(_backdrop):
		return

	if _stack.is_empty():
		_backdrop.visible = false
	else:
		_backdrop.visible = true
		var top: Control = _stack.back()
		if top.get_parent() == _backdrop.get_parent():
			var idx: int = top.get_index()
			_backdrop.get_parent().move_child(_backdrop, max(0, idx))
#endregion
