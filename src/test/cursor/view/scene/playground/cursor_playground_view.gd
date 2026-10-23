class_name CursorPlaygroundView
extends BaseView

## 自定义鼠标教学演练场被动视图（位于 src/test/cursor/view/scene/playground/，遵循 `BaseView` 规范）。[br]
##
## [b]核心职责：[/b][br]
## 1. 仅负责渲染声明式 `.tscn` 节点状态与转发 UI 交互信号；[br]
## 2. 不直接调用 `App.cursor`，所有业务动作均通过信号交由 [CursorPlaygroundPresenter] 编排。


#region 信号定义

signal theme_preset_selected(preset_id: int)
signal toggle_gameplay_cursor_requested()
signal toggle_wait_override_requested()
signal toggle_software_mode_requested()
signal trigger_recoil_pulse_requested()
signal toggle_trail_vfx_requested()
signal toggle_click_vfx_requested()
signal toggle_confinement_requested()
signal rerun_verification_requested()

#endregion


#region 节点引用

@onready var _status_pill_label: Label = %StatusPillLabel as Label
@onready var _theme_option_btn: OptionButton = %ThemeOptionBtn as OptionButton
@onready var _rerun_verify_btn: Button = %RerunVerifyBtn as Button

## L4 UI 控件自动/声明式悬停靶标
@onready var _grab_card_btn: Button = %GrabCardBtn as Button
@onready var _help_tip_btn: Button = %HelpTipBtn as Button

## L3/语义光标体验靶标
@onready var _target_interact_btn: Button = %TargetInteractBtn as Button
@onready var _target_attack_btn: Button = %TargetAttackBtn as Button
@onready var _target_crosshair_btn: Button = %TargetCrosshairBtn as Button
@onready var _target_zoom_in_btn: Button = %TargetZoomInBtn as Button
@onready var _target_zoom_out_btn: Button = %TargetZoomOutBtn as Button

## 优先级与特效控制按钮
@onready var _gameplay_mode_btn: Button = %GameplayModeBtn as Button
@onready var _wait_override_btn: Button = %WaitOverrideBtn as Button
@onready var _software_mode_btn: Button = %SoftwareModeBtn as Button
@onready var _recoil_pulse_btn: Button = %RecoilPulseBtn as Button
@onready var _trail_vfx_btn: Button = %TrailVfxBtn as Button
@onready var _click_vfx_btn: Button = %ClickVfxBtn as Button
@onready var _confined_btn: Button = %ConfinedBtn as Button

## 教学日志与契约验证输出框
@onready var _log_output: RichTextLabel = %LogOutput as RichTextLabel

#endregion


#region 生命周期

func _ready() -> void:
	super._ready()
	_setup_theme_options()
	_bind_ui_signals()


func _setup_theme_options() -> void:
	_theme_option_btn.clear()
	_theme_option_btn.add_item(
		"0 · 系统原生鼠标 (App.cursor.set_theme(null))",
		CursorTestState.ThemePreset.OS_NATIVE
	)
	_theme_option_btn.add_item(
		"1 · 赛博青白主题 (CursorThemeConfig.create_procedural_default())",
		CursorTestState.ThemePreset.CYBER_PROCEDURAL
	)
	_theme_option_btn.add_item(
		"2 · 绯红战术主题 (业务自定义构建 CursorThemeConfig 示例)",
		CursorTestState.ThemePreset.CRIMSON_TACTICAL
	)


func _bind_ui_signals() -> void:
	_theme_option_btn.item_selected.connect(_on_theme_item_selected)
	_rerun_verify_btn.pressed.connect(func() -> void: rerun_verification_requested.emit())
	_gameplay_mode_btn.pressed.connect(func() -> void: toggle_gameplay_cursor_requested.emit())
	_wait_override_btn.pressed.connect(func() -> void: toggle_wait_override_requested.emit())
	_software_mode_btn.pressed.connect(func() -> void: toggle_software_mode_requested.emit())
	_recoil_pulse_btn.pressed.connect(func() -> void: trigger_recoil_pulse_requested.emit())
	_trail_vfx_btn.pressed.connect(func() -> void: toggle_trail_vfx_requested.emit())
	_click_vfx_btn.pressed.connect(func() -> void: toggle_click_vfx_requested.emit())
	_confined_btn.pressed.connect(func() -> void: toggle_confinement_requested.emit())


func _on_theme_item_selected(index: int) -> void:
	var preset_id: int = _theme_option_btn.get_item_id(index)
	theme_preset_selected.emit(preset_id)

#endregion


#region 暴露给 Presenter 绑定光标语义的控件访问器

func get_grab_card_btn() -> Button:
	return _grab_card_btn


func get_help_tip_btn() -> Button:
	return _help_tip_btn


func get_target_interact_btn() -> Button:
	return _target_interact_btn


func get_target_attack_btn() -> Button:
	return _target_attack_btn


func get_target_crosshair_btn() -> Button:
	return _target_crosshair_btn


func get_target_zoom_in_btn() -> Button:
	return _target_zoom_in_btn


func get_target_zoom_out_btn() -> Button:
	return _target_zoom_out_btn

#endregion


#region 视图渲染接口

## 根据最新 [CursorTestState] 刷新顶部诊断栏与各开关按钮文案。
func render_state(state: CursorTestState) -> void:
	_status_pill_label.text = state.get_status_bar_text()

	var option_idx: int = _theme_option_btn.get_item_index(state.theme_preset)
	if option_idx >= 0 and _theme_option_btn.selected != option_idx:
		_theme_option_btn.select(option_idx)

	var gp_name: String = String(CursorShapeType.to_string_name(state.gameplay_cursor_shape))
	_gameplay_mode_btn.text = "L2 局内基准：%s" % gp_name

	_wait_override_btn.text = (
		"L5 强锁沙漏：开启中 (点击解除)"
		if state.is_wait_override_active
		else "L5 强锁覆盖：压入 WAIT 沙漏"
	)
	_software_mode_btn.text = (
		"渲染驱动：画布软件光标"
		if state.using_software_cursor
		else "渲染驱动：OS 硬件光标"
	)
	_trail_vfx_btn.text = "星尘拖尾：%s" % ("开启" if state.trail_vfx_enabled else "关闭")
	_click_vfx_btn.text = "点击波纹：%s" % ("开启" if state.click_vfx_enabled else "关闭")
	_confined_btn.text = "双屏锁边：%s" % ("开启" if state.confined_enabled else "关闭")


## 重新渲染完整日志列表。
func render_all_logs(lines: PackedStringArray) -> void:
	_log_output.clear()
	for line: String in lines:
		_log_output.append_text(line + "\n")


## 增量追加单行 BBCode 日志。
func append_log_line(bbcode_line: String) -> void:
	_log_output.append_text(bbcode_line + "\n")

#endregion
