class_name DisplayLobbyScene
extends BaseScene

## 显示与画质测试大厅主场景
##
## 作为测试入口场景，挂载 DisplayLobbyView 并委托 DisplayLobbyPresenter 编排。


#region 节点引用

@onready var _lobby_view: DisplayLobbyView = $LobbyView as DisplayLobbyView

#endregion


#region 私有变量

var _presenter: DisplayLobbyPresenter = null

#endregion


#region 生命周期

func _on_enter(params: BaseParams = null) -> void:
	if _presenter != null:
		_presenter.unbind()
	_presenter = DisplayLobbyPresenter.new(_lobby_view)
	var enter_params: DisplayEnterParams = params as DisplayEnterParams
	_presenter.bind(enter_params)


func _on_resume(result: BaseParams = null) -> void:
	if _presenter != null:
		_presenter.on_return_from_settings(result)


func _on_exit() -> void:
	if _presenter != null:
		_presenter.unbind()
		_presenter = null


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.keycode == KEY_F11 and _presenter != null:
			get_viewport().set_input_as_handled()
			_presenter.handle_shortcut_fullscreen()

#endregion
