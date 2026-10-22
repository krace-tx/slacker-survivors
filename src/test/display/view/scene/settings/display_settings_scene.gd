class_name DisplaySettingsScene
extends BaseScene

## 显示与画质设置测试子场景
##
## 挂载 DisplaySettingsView 并委托 DisplaySettingsPresenter 协调表单与弹窗逻辑。


#region 节点引用

@onready var _settings_view: DisplaySettingsView = $SettingsView as DisplaySettingsView

#endregion


#region 私有变量

var _presenter: DisplaySettingsPresenter = null

#endregion


#region 生命周期

func _on_enter(_params: BaseParams = null) -> void:
	if _presenter != null:
		_presenter.unbind()
	_presenter = DisplaySettingsPresenter.new(_settings_view)
	_presenter.bind()


func _on_exit() -> void:
	if _presenter != null:
		_presenter.unbind()
		_presenter = null


func _unhandled_input(event: InputEvent) -> void:
	if _presenter == null:
		return
	if event.is_action_pressed("ui_cancel") and not DialogManager.has_modal():
		get_viewport().set_input_as_handled()
		_presenter.navigate_back()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.keycode == KEY_F11:
			get_viewport().set_input_as_handled()
			_presenter.handle_shortcut_fullscreen()

#endregion
