class_name DisplayLobbyPresenter
extends RefCounted

## 显示测试大厅页协调器
##
## 连接 DisplayTestState、DisplayTestService 与 DisplayLobbyView，编排跳转设置页与全屏快捷键。


#region 常量定义

const SETTINGS_SCENE_PATH: String = "res://src/test/display/view/scene/settings/display_settings_scene.tscn"

#endregion


#region 私有变量

var _view: DisplayLobbyView = null
var _state: DisplayTestState = null
var _service: DisplayTestService = null

#endregion


#region 生命周期

func _init(view: DisplayLobbyView) -> void:
	_view = view
	_state = DisplayTestState.new()
	_service = DisplayTestService.new(_state)


## 绑定视图与系统事件监听
func bind(enter_params: DisplayEnterParams = null) -> void:
	_state.state_changed.connect(_on_state_changed)
	_view.open_settings_requested.connect(_on_open_settings_requested)
	_view.toggle_fullscreen_requested.connect(_on_toggle_fullscreen_requested)

	var vp: Viewport = _view.get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_viewport_size_changed):
		vp.size_changed.connect(_on_viewport_size_changed)

	var model: GameSettingsModel = GameSettingsService.get_current()
	if not model.data_changed.is_connected(_on_settings_model_changed):
		model.data_changed.connect(_on_settings_model_changed)

	_service.refresh_state()
	if enter_params != null and not enter_params.notice_text.is_empty():
		_view.set_notice_text(enter_params.notice_text)


## 销毁前清理
func unbind() -> void:
	if _view != null:
		var vp: Viewport = _view.get_viewport()
		if vp != null and vp.size_changed.is_connected(_on_viewport_size_changed):
			vp.size_changed.disconnect(_on_viewport_size_changed)

	var model: GameSettingsModel = GameSettingsService.get_current()
	if model.data_changed.is_connected(_on_settings_model_changed):
		model.data_changed.disconnect(_on_settings_model_changed)

	if _state != null and _state.state_changed.is_connected(_on_state_changed):
		_state.state_changed.disconnect(_on_state_changed)
	_view = null
	_service = null
	_state = null

#endregion


#region 公开方法

## 处理设置页返回时的结果数据
func on_return_from_settings(result: BaseParams) -> void:
	if _service == null:
		return
	_service.refresh_state()
	var res_params: SettingsResultParams = result as SettingsResultParams
	if res_params != null and not res_params.summary_text.is_empty():
		_view.set_notice_text("已同步设置：%s" % res_params.summary_text)
		ToastManager.show("设置已生效：%s" % res_params.summary_text)


## 处理 F11 快捷切换全屏
func handle_shortcut_fullscreen() -> void:
	_on_toggle_fullscreen_requested()

#endregion


#region 内部回调

func _on_state_changed() -> void:
	if _view != null:
		_view.render_state(_state)


func _on_open_settings_requested() -> void:
	var params: DisplayEnterParams = DisplayEnterParams.new("lobby", "调整参数后将实时预览")
	_push_settings_async(params)


func _push_settings_async(params: DisplayEnterParams) -> void:
	await App.scene.push(
		SETTINGS_SCENE_PATH,
		params,
		SceneTransitionType.CROSS_PUSH
	)


func _on_toggle_fullscreen_requested() -> void:
	if _service == null:
		return
	_service.toggle_fullscreen()
	ToastManager.show(_state.last_change_text)


func _on_viewport_size_changed() -> void:
	if _service != null:
		_service.refresh_state()


func _on_settings_model_changed() -> void:
	if _service != null:
		_service.refresh_state()

#endregion
