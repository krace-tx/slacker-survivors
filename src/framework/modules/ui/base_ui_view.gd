class_name BaseUIView
extends Control

## 顶层场景或视图面板的 UI 界面实例基类。
## 场景里子节点名固定为 [code]UI[/code]，脚本 extends BaseUIView。
## 提供标准视图生命周期钩子与屏幕安全区（Safe Area）适配。

signal ui_opened
signal ui_closed

#region Exports
@export_group("Layout")
## 是否自动适配异形屏安全区（刘海屏 / 灵动岛 / 底部 Home 条）
@export var apply_safe_area: bool = true
#endregion

#region State
var _ui_params: Dictionary = {}
var _is_ui_opened: bool = false
#endregion

#region Lifecycle
func _ready() -> void:
	if apply_safe_area:
		_adapt_safe_area()


## 打开/呈现该 UI 视图
func open_ui(params: Dictionary = {}) -> void:
	_ui_params = params
	visible = true
	_is_ui_opened = true
	_on_ui_open(_ui_params)
	ui_opened.emit()


## 关闭/隐藏该 UI 视图
func close_ui() -> void:
	if not _is_ui_opened:
		return
	_is_ui_opened = false
	_on_ui_close()
	visible = false
	ui_closed.emit()


## 获取打开时透传的参数字典
func get_ui_params() -> Dictionary:
	return _ui_params
#endregion

#region Subclass Hooks
## 视图打开时回调（用于挂载数据、刷新界面）
func _on_ui_open(_params: Dictionary) -> void:
	pass


## 视图关闭时回调（用于清理动效、注销本地信号）
func _on_ui_close() -> void:
	pass
#endregion

#region Safe Area
## 适配移动端异形屏与安全区边距
func _adapt_safe_area() -> void:
	var safe_area := DisplayServer.get_display_safe_area()
	var window_size := DisplayServer.window_get_size()
	if window_size.x <= 0 or window_size.y <= 0:
		return

	# 将像素 Rect2 转换为相对边距
	var left := safe_area.position.x
	var top := safe_area.position.y
	var right := window_size.x - (safe_area.position.x + safe_area.size.x)
	var bottom := window_size.y - (safe_area.position.y + safe_area.size.y)

	if left > 0 or top > 0 or right > 0 or bottom > 0:
		offset_left = left
		offset_top = top
		offset_right = -right
		offset_bottom = -bottom
#endregion
