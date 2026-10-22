class_name DisplaySettingsPresenter
extends RefCounted

## 显示与画质设置页协调器
##
## 负责处理表单变更、15秒切屏确认弹窗编排、画质档位与自定义项双向联动及返回大厅通信。


#region 常量定义

const CONFIRM_DIALOG_PATH: String = "res://src/test/display/view/component/confirm/display_confirm_dialog.tscn"

#endregion


#region 私有变量

var _view: DisplaySettingsView = null
var _state: DisplayTestState = null
var _service: DisplayTestService = null

#endregion


#region 生命周期

func _init(view: DisplaySettingsView) -> void:
	_view = view
	_state = DisplayTestState.new()
	_service = DisplayTestService.new(_state)


## 绑定视图与底层事件
func bind() -> void:
	_state.state_changed.connect(_on_state_changed)

	_view.window_mode_selected.connect(_on_window_mode_selected)
	_view.resolution_selected.connect(_on_resolution_selected)
	_view.vsync_selected.connect(_on_vsync_selected)
	_view.fps_selected.connect(_on_fps_selected)
	_view.safe_area_scale_selected.connect(_on_safe_area_scale_selected)
	_view.lock_aspect_selected.connect(_on_lock_aspect_selected)
	_view.quality_preset_selected.connect(_on_quality_preset_selected)
	_view.msaa_selected.connect(_on_msaa_selected)
	_view.ssaa_selected.connect(_on_ssaa_selected)
	_view.scale_3d_selected.connect(_on_scale_3d_selected)
	_view.confirm_guard_toggled.connect(_on_confirm_guard_toggled)
	_view.reset_defaults_requested.connect(_on_reset_defaults_requested)
	_view.back_to_lobby_requested.connect(navigate_back)

	var vp: Viewport = _view.get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_viewport_size_changed):
		vp.size_changed.connect(_on_viewport_size_changed)

	_service.refresh_state()


## 解绑并释放引用
func unbind() -> void:
	if _view != null:
		var vp: Viewport = _view.get_viewport()
		if vp != null and vp.size_changed.is_connected(_on_viewport_size_changed):
			vp.size_changed.disconnect(_on_viewport_size_changed)

	if _state != null and _state.state_changed.is_connected(_on_state_changed):
		_state.state_changed.disconnect(_on_state_changed)
	_view = null
	_service = null
	_state = null

#endregion


#region 路由与快捷键

## 携带当前显示摘要返回大厅页
func navigate_back() -> void:
	if _state == null:
		return
	var result: SettingsResultParams = SettingsResultParams.new(
		_state.get_summary_line()
	)
	_pop_to_lobby_async(result)


func _pop_to_lobby_async(result: SettingsResultParams) -> void:
	await App.scene.pop(result, SceneTransitionType.CROSS_POP)


## 处理 F11 快捷切换全屏
func handle_shortcut_fullscreen() -> void:
	if _service == null:
		return
	_service.toggle_fullscreen()
	ToastManager.show(_state.last_change_text)

#endregion


#region 内部回调：屏幕与分辨率（带 15 秒保护弹窗）

func _on_state_changed() -> void:
	if _view != null and _service != null:
		_view.render_state(_state, _service)


func _on_window_mode_selected(mode_idx: int) -> void:
	if mode_idx == _state.window_mode:
		return
	_service.capture_revert_snapshot()
	_service.apply_window_mode(mode_idx)
	_trigger_confirm_or_toast(DisplayEnterParams.format_window_mode(mode_idx))


func _on_resolution_selected(res_idx: int) -> void:
	if res_idx < 0 or res_idx >= _state.available_resolutions.size():
		return
	var target_res: Vector2i = _state.available_resolutions[res_idx]
	if target_res == _state.resolution:
		return
	_service.capture_revert_snapshot()
	_service.apply_resolution(target_res)
	_trigger_confirm_or_toast("%d × %d" % [target_res.x, target_res.y])


func _trigger_confirm_or_toast(target_desc: String) -> void:
	if not _state.require_confirm_dialog:
		_service.confirm_display_change()
		ToastManager.show("已应用：%s" % target_desc)
		return

	var dialog_params: ConfirmDialogParams = ConfirmDialogParams.new(
		target_desc,
		15.0,
		_on_confirm_dialog_decided
	)
	_open_confirm_dialog_async(dialog_params)


func _open_confirm_dialog_async(params: ConfirmDialogParams) -> void:
	await DialogManager.open(CONFIRM_DIALOG_PATH, params)


func _on_confirm_dialog_decided(keep_changes: bool) -> void:
	if _service == null:
		return
	if keep_changes:
		_service.confirm_display_change()
		ToastManager.show("已保留当前显示设置")
	else:
		_service.rollback_display_change()
		ToastManager.show("已还原为更改前的显示设置")

#endregion


#region 内部回调：帧率与画质联动

func _on_vsync_selected(vsync_idx: int) -> void:
	var enabled: bool = vsync_idx > 0
	_service.apply_vsync(enabled)
	ToastManager.show(_state.last_change_text)


func _on_fps_selected(fps_idx: int) -> void:
	if fps_idx < 0 or fps_idx >= DisplayTestService.FPS_OPTIONS.size():
		return
	var fps_val: int = DisplayTestService.FPS_OPTIONS[fps_idx]
	_service.apply_target_fps(fps_val)
	ToastManager.show(_state.last_change_text)


func _on_safe_area_scale_selected(scale_idx: int) -> void:
	if scale_idx < 0 or scale_idx >= DisplayTestService.SAFE_AREA_SCALE_OPTIONS.size():
		return
	var scale_val: float = DisplayTestService.SAFE_AREA_SCALE_OPTIONS[scale_idx]
	_service.apply_safe_area_scale(scale_val)
	ToastManager.show(_state.last_change_text)


func _on_lock_aspect_selected(aspect_idx: int) -> void:
	var locked: bool = aspect_idx > 0
	_service.apply_lock_design_aspect(locked)
	ToastManager.show(_state.last_change_text)


func _on_quality_preset_selected(preset_idx: int) -> void:
	_service.apply_quality_preset(preset_idx)
	ToastManager.show(_state.last_change_text)


func _on_msaa_selected(msaa_idx: int) -> void:
	_service.apply_custom_msaa(msaa_idx)
	ToastManager.show(_state.last_change_text)


func _on_ssaa_selected(ssaa_idx: int) -> void:
	_service.apply_custom_ssaa(ssaa_idx)
	ToastManager.show(_state.last_change_text)


func _on_scale_3d_selected(scale_idx: int) -> void:
	if scale_idx < 0 or scale_idx >= DisplayTestService.SCALE_3D_OPTIONS.size():
		return
	var scale_val: float = DisplayTestService.SCALE_3D_OPTIONS[scale_idx]
	_service.apply_custom_scale_3d(scale_val)
	ToastManager.show(_state.last_change_text)


func _on_confirm_guard_toggled(enabled: bool) -> void:
	_state.require_confirm_dialog = enabled
	var status_str: String = "已开启" if enabled else "已关闭"
	ToastManager.show("切屏 15 秒确认保护%s" % status_str)


func _on_reset_defaults_requested() -> void:
	_service.reset_all_to_defaults()
	ToastManager.show(_state.last_change_text)


func _on_viewport_size_changed() -> void:
	if _service != null:
		_service.refresh_state()

#endregion
