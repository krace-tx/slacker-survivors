class_name ModalStack
extends RefCounted

## 模态弹窗栈与暗色遮罩管理（私有实现，仅供 [UIService] 使用）。[br]
##
## 维护活动弹窗列表（后入先出），以及放置在顶层弹窗正下方的暗色背景遮罩（BackdropMask）。[br]
## 处理遮罩点击事件并分发至顶层弹窗的 [member BaseDialog.close_on_backdrop] 逻辑。

var _popup_layer: CanvasLayer
var _backdrop_mask: ColorRect
var _stack: Array[Control] = []


## 绑定挂载的目标 CanvasLayer 并初始化背景遮罩。
func setup(popup_layer: CanvasLayer) -> void:
	_popup_layer = popup_layer
	if _popup_layer == null:
		return

	_backdrop_mask = ColorRect.new()
	_backdrop_mask.name = "BackdropMask"
	_backdrop_mask.color = Color(0, 0, 0, 0.6)
	_backdrop_mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop_mask.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop_mask.visible = false
	_backdrop_mask.gui_input.connect(_on_backdrop_gui_input)
	_popup_layer.add_child(_backdrop_mask)


## 压入新弹窗控件到栈顶并打开。
func push(popup_ctrl: Control, params: Dictionary, ui_service: BaseUISystem) -> void:
	if _popup_layer == null:
		return
	_popup_layer.add_child(popup_ctrl)
	_stack.append(popup_ctrl)
	_update_backdrop_state()

	if popup_ctrl is BaseDialog:
		(popup_ctrl as BaseDialog).open(params, ui_service)
	else:
		popup_ctrl.visible = true


## 关闭指定弹窗（若为空则关闭栈顶）。
func pop(dialog: Control = null) -> bool:
	if dialog == null:
		return pop_top()

	if _stack.has(dialog):
		_stack.erase(dialog)

	if is_instance_valid(dialog):
		dialog.queue_free()

	_update_backdrop_state()
	return true


## 关闭栈顶弹窗。
func pop_top() -> bool:
	if _stack.is_empty():
		return false

	var top_dialog := _stack.pop_back() as Control
	if top_dialog != null and is_instance_valid(top_dialog):
		if top_dialog is BaseDialog:
			(top_dialog as BaseDialog).close()
		else:
			top_dialog.queue_free()

	_update_backdrop_state()
	return true


## 当前是否存在活动模态弹窗。
func has_modal() -> bool:
	return not _stack.is_empty()


## 清空并释放所有弹窗。
func clear() -> void:
	for dialog in _stack:
		if is_instance_valid(dialog):
			dialog.queue_free()
	_stack.clear()
	_update_backdrop_state()


func _update_backdrop_state() -> void:
	if _backdrop_mask == null or not is_instance_valid(_backdrop_mask):
		return

	var has_popups := not _stack.is_empty()
	_backdrop_mask.visible = has_popups

	if has_popups:
		# 将遮罩移动到顶层弹窗正下方
		var top_popup := _stack.back() as Control
		if top_popup != null and top_popup.get_parent() == _backdrop_mask.get_parent():
			var target_index := maxi(0, top_popup.get_index() - 1)
			_backdrop_mask.get_parent().move_child(_backdrop_mask, target_index)


func _on_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _stack.is_empty():
			return
		var top: Control = _stack.back()
		if top is BaseDialog and (top as BaseDialog).close_on_backdrop:
			(top as BaseDialog).close()
