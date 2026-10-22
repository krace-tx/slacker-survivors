class_name DisplaySettingsView
extends BaseView

## 显示与画质设置页被动视图
##
## 负责驱动简约单卡片设置表单渲染，并将用户下拉选择与按钮点击转为领域信号抛出。


#region 信号定义

signal window_mode_selected(mode_idx: int)
signal resolution_selected(res_idx: int)
signal vsync_selected(vsync_idx: int)
signal fps_selected(fps_idx: int)
signal safe_area_scale_selected(scale_idx: int)
signal lock_aspect_selected(aspect_idx: int)
signal quality_preset_selected(preset_idx: int)
signal msaa_selected(msaa_idx: int)
signal ssaa_selected(ssaa_idx: int)
signal scale_3d_selected(scale_idx: int)
signal confirm_guard_toggled(enabled: bool)
signal reset_defaults_requested()
signal back_to_lobby_requested()

#endregion


#region 节点引用

@onready var _live_badge_label: Label = $CenterContainer/SettingsCard/CardVBox/HeaderRow/LiveBadgeLabel as Label
@onready var _embed_notice_label: Label = $CenterContainer/SettingsCard/CardVBox/EmbedNoticeLabel as Label
@onready var _window_mode_option: OptionButton = $CenterContainer/SettingsCard/CardVBox/DisplayForm/WindowModeRow/WindowModeOption as OptionButton
@onready var _resolution_option: OptionButton = $CenterContainer/SettingsCard/CardVBox/DisplayForm/ResolutionRow/ResolutionOption as OptionButton
@onready var _vsync_option: OptionButton = $CenterContainer/SettingsCard/CardVBox/DisplayForm/VSyncRow/VSyncOption as OptionButton
@onready var _fps_option: OptionButton = $CenterContainer/SettingsCard/CardVBox/DisplayForm/FpsRow/FpsOption as OptionButton
@onready var _safe_area_scale_option: OptionButton = $CenterContainer/SettingsCard/CardVBox/DisplayForm/SafeAreaScaleRow/SafeAreaScaleOption as OptionButton
@onready var _lock_aspect_option: OptionButton = $CenterContainer/SettingsCard/CardVBox/DisplayForm/LockAspectRow/LockAspectOption as OptionButton
@onready var _quality_preset_option: OptionButton = $CenterContainer/SettingsCard/CardVBox/GraphicsForm/PresetRow/QualityPresetOption as OptionButton
@onready var _msaa_option: OptionButton = $CenterContainer/SettingsCard/CardVBox/GraphicsForm/MsaaRow/MsaaOption as OptionButton
@onready var _ssaa_option: OptionButton = $CenterContainer/SettingsCard/CardVBox/GraphicsForm/SsaaRow/SsaaOption as OptionButton
@onready var _scale_3d_option: OptionButton = $CenterContainer/SettingsCard/CardVBox/GraphicsForm/Scale3DRow/Scale3DOption as OptionButton
@onready var _confirm_guard_check: CheckButton = $CenterContainer/SettingsCard/CardVBox/FooterRow/ConfirmGuardCheck as CheckButton
@onready var _reset_btn: Button = $CenterContainer/SettingsCard/CardVBox/FooterRow/ResetBtn as Button
@onready var _back_btn: Button = $CenterContainer/SettingsCard/CardVBox/FooterRow/BackBtn as Button

#endregion


#region 私有变量

var _is_updating_ui: bool = false

#endregion


#region 生命周期

func _ready() -> void:
	super._ready()
	_populate_static_options()
	_bind_controls()

#endregion


#region 公开渲染接口

## 根据当前状态模型同步表单选中项
func render_state(state: DisplayTestState, service: DisplayTestService) -> void:
	_is_updating_ui = true

	_live_badge_label.text = state.get_summary_line()
	_embed_notice_label.visible = state.is_embedded_in_editor
	_confirm_guard_check.button_pressed = state.require_confirm_dialog

	_window_mode_option.selected = clampi(state.window_mode, 0, 3)
	_rebuild_resolution_options(state, service)
	_vsync_option.selected = 1 if state.vsync_enabled else 0
	_fps_option.selected = service.find_fps_index(state.max_fps)
	_safe_area_scale_option.selected = service.find_safe_area_scale_index(state.safe_area_scale)
	_lock_aspect_option.selected = 1 if state.lock_design_aspect else 0

	_quality_preset_option.selected = clampi(state.quality_preset, 0, 4)
	_msaa_option.selected = clampi(state.msaa_level, 0, 3)
	_ssaa_option.selected = clampi(state.screen_space_aa, 0, 2)
	_scale_3d_option.selected = service.find_scale_3d_index(state.render_scale)

	_is_updating_ui = false

#endregion


#region 内部初始化与事件转发

func _populate_static_options() -> void:
	_window_mode_option.clear()
	_window_mode_option.add_item("窗口模式", BaseDisplaySystem.WindowMode.WINDOWED)
	_window_mode_option.add_item("无边框窗口", BaseDisplaySystem.WindowMode.BORDERLESS_WINDOWED)
	_window_mode_option.add_item("无边框全屏", BaseDisplaySystem.WindowMode.FULLSCREEN)
	_window_mode_option.add_item("独占全屏", BaseDisplaySystem.WindowMode.EXCLUSIVE_FULLSCREEN)

	_vsync_option.clear()
	_vsync_option.add_item("关闭", 0)
	_vsync_option.add_item("开启", 1)

	_fps_option.clear()
	for fps_val: int in DisplayTestService.FPS_OPTIONS:
		_fps_option.add_item(DisplayEnterParams.format_fps(fps_val))

	_safe_area_scale_option.clear()
	_safe_area_scale_option.add_item("100% (默认贴边)")
	_safe_area_scale_option.add_item("95% (微缩留白)")
	_safe_area_scale_option.add_item("90% (标准留白)")
	_safe_area_scale_option.add_item("85% (紧凑内缩)")

	_lock_aspect_option.clear()
	_lock_aspect_option.add_item("自适应全屏宽高比", 0)
	_lock_aspect_option.add_item("锁定设计宽高比居中", 1)

	_quality_preset_option.clear()
	_quality_preset_option.add_item("低", GraphicsSettingsData.QualityPreset.LOW)
	_quality_preset_option.add_item("中", GraphicsSettingsData.QualityPreset.MEDIUM)
	_quality_preset_option.add_item("高", GraphicsSettingsData.QualityPreset.HIGH)
	_quality_preset_option.add_item("极高", GraphicsSettingsData.QualityPreset.ULTRA)
	_quality_preset_option.add_item("自定义", GraphicsSettingsData.QualityPreset.CUSTOM)

	_msaa_option.clear()
	_msaa_option.add_item("关闭")
	_msaa_option.add_item("2x MSAA")
	_msaa_option.add_item("4x MSAA")
	_msaa_option.add_item("8x MSAA")

	_ssaa_option.clear()
	_ssaa_option.add_item("关闭")
	_ssaa_option.add_item("FXAA (快速近似)")
	_ssaa_option.add_item("SMAA (增强边缘)")

	_scale_3d_option.clear()
	for scale_val: float in DisplayTestService.SCALE_3D_OPTIONS:
		_scale_3d_option.add_item("%d%%" % roundi(scale_val * 100.0))


func _rebuild_resolution_options(state: DisplayTestState, service: DisplayTestService) -> void:
	_resolution_option.clear()
	for res: Vector2i in state.available_resolutions:
		_resolution_option.add_item("%d × %d" % [res.x, res.y])
	var res_idx: int = service.find_resolution_index(state.resolution)
	if res_idx >= 0:
		_resolution_option.selected = res_idx
	elif _resolution_option.item_count > 0:
		_resolution_option.selected = _resolution_option.item_count - 1


func _bind_controls() -> void:
	_window_mode_option.item_selected.connect(func(idx: int) -> void:
		if not _is_updating_ui:
			window_mode_selected.emit(idx)
	)
	_resolution_option.item_selected.connect(func(idx: int) -> void:
		if not _is_updating_ui:
			resolution_selected.emit(idx)
	)
	_vsync_option.item_selected.connect(func(idx: int) -> void:
		if not _is_updating_ui:
			vsync_selected.emit(idx)
	)
	_fps_option.item_selected.connect(func(idx: int) -> void:
		if not _is_updating_ui:
			fps_selected.emit(idx)
	)
	_safe_area_scale_option.item_selected.connect(func(idx: int) -> void:
		if not _is_updating_ui:
			safe_area_scale_selected.emit(idx)
	)
	_lock_aspect_option.item_selected.connect(func(idx: int) -> void:
		if not _is_updating_ui:
			lock_aspect_selected.emit(idx)
	)
	_quality_preset_option.item_selected.connect(func(idx: int) -> void:
		if not _is_updating_ui:
			quality_preset_selected.emit(idx)
	)
	_msaa_option.item_selected.connect(func(idx: int) -> void:
		if not _is_updating_ui:
			msaa_selected.emit(idx)
	)
	_ssaa_option.item_selected.connect(func(idx: int) -> void:
		if not _is_updating_ui:
			ssaa_selected.emit(idx)
	)
	_scale_3d_option.item_selected.connect(func(idx: int) -> void:
		if not _is_updating_ui:
			scale_3d_selected.emit(idx)
	)
	_confirm_guard_check.toggled.connect(func(pressed: bool) -> void:
		if not _is_updating_ui:
			confirm_guard_toggled.emit(pressed)
	)
	_reset_btn.pressed.connect(func() -> void: reset_defaults_requested.emit())
	_back_btn.pressed.connect(func() -> void: back_to_lobby_requested.emit())

#endregion
