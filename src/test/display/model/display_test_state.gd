class_name DisplayTestState
extends RefCounted

## 显示与画质测试运行时状态模型
##
## 维护当前屏幕、分辨率、帧率及画质档位的响应式快照，驱动大厅与设置页 UI 刷新。


#region 信号定义

signal state_changed()

#endregion


#region 状态字段

## 是否开启切屏 15 秒确认倒计时保护
var require_confirm_dialog: bool = true

## 最近一次变更摘要
var last_change_text: String = "就绪"

## 是否处于编辑器内嵌游戏窗口模式
var is_embedded_in_editor: bool = false

## 当前窗口模式
var window_mode: int = BaseDisplaySystem.WindowMode.WINDOWED

## 当前配置分辨率
var resolution: Vector2i = Vector2i(1920, 1080)

## 当前实际窗口物理像素尺寸
var actual_window_size: Vector2i = Vector2i(1920, 1080)

## 当前显示器物理分辨率与刷新率
var screen_size: Vector2i = Vector2i(1920, 1080)
var screen_dpi: int = 96
var screen_refresh_rate: float = 60.0

## 当前可选安全分辨率列表
var available_resolutions: Array[Vector2i] = []

## 垂直同步与目标帧率
var vsync_enabled: bool = true
var max_fps: int = 0

## 安全区缩放比例与设计宽高比锁定
var safe_area_scale: float = 1.0
var lock_design_aspect: bool = false

## 画质档位与细分项
var quality_preset: int = GraphicsSettingsData.QualityPreset.HIGH
var msaa_level: int = Viewport.MSAA_2X
var screen_space_aa: int = Viewport.SCREEN_SPACE_AA_FXAA
var render_scale: float = 1.0

#endregion


#region 公开方法

## 同步底层 DisplaySystem 与 GameSettingsModel 快照并触发通知
func sync_from(display: BaseDisplaySystem, model: GameSettingsModel) -> void:
	is_embedded_in_editor = Engine.is_embedded_in_editor()
	var d: DisplaySettingsData = model.display
	var g: GraphicsSettingsData = model.graphics

	window_mode = d.window_mode
	actual_window_size = display.get_resolution()
	if d.resolution_width > 0 and d.resolution_height > 0:
		resolution = Vector2i(d.resolution_width, d.resolution_height)
	else:
		resolution = actual_window_size

	screen_size = display.get_screen_size()
	screen_dpi = display.get_screen_dpi()
	screen_refresh_rate = display.get_screen_refresh_rate()
	available_resolutions = display.get_available_resolutions()

	vsync_enabled = d.vsync_enabled
	max_fps = d.max_fps
	safe_area_scale = d.safe_area_scale
	lock_design_aspect = d.lock_design_aspect
	quality_preset = g.quality_preset
	msaa_level = g.msaa_2d
	screen_space_aa = g.screen_space_aa
	render_scale = g.render_scale
	state_changed.emit()


## 生成单行极简状态概览文本（如：窗口模式 · 1920×1080 · 高画质 · 无限制）
func get_summary_line() -> String:
	var mode_str: String = DisplayEnterParams.format_window_mode(window_mode)
	var res_str: String = "%d × %d" % [actual_window_size.x, actual_window_size.y]
	var preset_str: String = "%s画质" % DisplayEnterParams.format_quality_preset(quality_preset)
	var fps_str: String = DisplayEnterParams.format_fps(max_fps)
	return "%s  ·  %s  ·  %s  ·  %s" % [mode_str, res_str, preset_str, fps_str]

#endregion
