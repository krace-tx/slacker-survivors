class_name SoulsKeybindHelpDialog
extends Control

## 魂系 3D 键位教学与战斗机制弹窗（位于 src/test/souls_arena/view/component/help_dialog/，遵循 MSVP 的 `Component` 规范）。[br]
##
## [b]核心设计：[/b][br]
## 1. 完整节点树、SVG 纹章图标与双栏富文本教学卡片均直接构建于 [`souls_keybind_help_dialog.tscn`](file:///d:/code/GodotProject/slacker-survivors/src/test/souls_arena/view/component/help_dialog/souls_keybind_help_dialog.tscn)，脚本零 `.new()` 动态拼装；[br]
## 2. 按 `H` 键或点击右上角 `[H] 键位教学` 按钮即可随时呼出或关闭。


#region 信号定义

signal close_requested()

#endregion


#region 场景唯一节点绑定 (%UniqueName)

@onready var _backdrop: ColorRect = %Backdrop as ColorRect
@onready var _close_btn: Button = %CloseBtn as Button

#endregion


#region 生命周期与交互

func _ready() -> void:
	if _backdrop != null:
		_backdrop.gui_input.connect(_on_backdrop_gui_input)
	if _close_btn != null:
		_close_btn.pressed.connect(func() -> void: close_requested.emit())


func _on_backdrop_gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb: InputEventMouseButton = ev as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			close_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.keycode == KEY_ESCAPE or key_event.keycode == KEY_H:
			get_viewport().set_input_as_handled()
			close_requested.emit()

#endregion
