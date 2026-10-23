class_name CursorTestState
extends RefCounted

## 自定义鼠标教学演练场运行时状态模型（位于 src/test/cursor/model/，遵循 `*State` 规范）。[br]
##
## [b]核心职责：[/b][br]
## 1. 维护当前选中的鼠标主题档位（系统原生 / 赛博青白 / 绯红战术自定义主题）；[br]
## 2. 实时同步 `App.cursor` 的裁决形状、按压形变、胜出层级（L1~L5）、软件/硬件模式及粒子特效开关；[br]
## 3. 维护操作与自动化测试日志队列，通过 [signal state_changed] 与 [signal log_appended] 驱动视图刷新。


#region 信号与枚举

signal state_changed()
signal log_appended(bbcode_line: String)

## 教学演示支持的三种鼠标主题预设档位
enum ThemePreset {
	OS_NATIVE = 0,        ## 系统原生鼠标 (App.cursor.set_theme(null)，无自定义贴图与粒子)
	CYBER_PROCEDURAL = 1, ## 赛博科技主题 (CursorThemeConfig.create_procedural_default())
	CRIMSON_TACTICAL = 2, ## 绯红战术主题 (教学演示：如何从零手写组装自定义 CursorThemeConfig)
}

const MAX_LOG_LINES: int = 80

#endregion


#region 状态字段

## 当前选中的鼠标主题预设档位
var theme_preset: int = ThemePreset.CYBER_PROCEDURAL

## 当前裁决生效的语义光标形状（对应 CursorShapeType.Shape）
var active_shape: int = CursorShapeType.Shape.DEFAULT

## 当前鼠标左键是否处于按压形变态
var is_pressed: bool = false

## 当前五层优先级漏斗中胜出的层级标签（如 "L1_DEFAULT" / "L4_UI_CONTROL" / "L5_OVERRIDE"）
var winning_layer: String = "L1_DEFAULT"

## 当前是否正在使用画布软件光标渲染
var using_software_cursor: bool = false

## 是否全局偏好软件光标模式
var software_preferred: bool = false

## 当前局内基准光标形状（DEFAULT 或 CROSSHAIR）
var gameplay_cursor_shape: int = CursorShapeType.Shape.DEFAULT

## 是否处于 L5 强锁覆盖（WAIT 旋转沙漏）状态
var is_wait_override_active: bool = false

## 是否开启了移动星尘拖尾粒子
var trail_vfx_enabled: bool = false

## 是否开启了左键点击水波纹爆裂粒子
var click_vfx_enabled: bool = false

## 是否开启了战斗期窗口边界锁边（MOUSE_MODE_CONFINED）
var confined_enabled: bool = false

## 当前鼠标指针是否可见（手柄模式下自动隐藏）
var cursor_visible: bool = true

## 自动化验证通过/失败计数
var passed_cases: int = 0
var failed_cases: int = 0

## 历史日志行缓存
var log_lines: PackedStringArray = PackedStringArray()

#endregion


#region 状态同步与格式化辅助

## 从 `App.cursor` 实时采集最新诊断快照并通知 Presenter。
func sync_from_cursor_system() -> void:
	if App == null or App.cursor == null:
		return
	var diag: Dictionary = App.cursor.get_diagnostics()
	active_shape = App.cursor.get_current_shape()
	is_pressed = App.cursor.is_pressed_state()
	winning_layer = str(diag.get("winning_layer", "L1_DEFAULT"))
	using_software_cursor = App.cursor.is_using_software_cursor()
	gameplay_cursor_shape = App.cursor.get_gameplay_cursor()
	trail_vfx_enabled = App.cursor.is_trail_vfx_enabled()
	click_vfx_enabled = App.cursor.is_click_vfx_enabled()
	confined_enabled = App.cursor.is_confined()
	cursor_visible = App.cursor.is_cursor_visible()
	state_changed.emit()


## 追加一条 BBCode 格式的教学/测试日志。
func append_log(bbcode_line: String) -> void:
	log_lines.append(bbcode_line)
	if log_lines.size() > MAX_LOG_LINES:
		log_lines.remove_at(0)
	log_appended.emit(bbcode_line)


## 清空日志与测试计数。
func clear_logs() -> void:
	log_lines.clear()
	passed_cases = 0
	failed_cases = 0
	state_changed.emit()


## 生成顶部单行实时诊断状态栏文本。
func get_status_bar_text() -> String:
	var theme_str: String = format_theme_preset(theme_preset)
	var shape_str: String = String(CursorShapeType.to_string_name(active_shape))
	var mode_str: String = "软件画布光标" if using_software_cursor else "OS 硬件光标"
	var trail_str: String = "开启" if trail_vfx_enabled else "关闭"
	var click_str: String = "开启" if click_vfx_enabled else "关闭"
	return "主题：[%s]  ·  生效形状：[%s%s]  ·  胜出层：[%s]  ·  渲染模式：[%s]  ·  拖尾：[%s]  ·  点击波：[%s]" % [
		theme_str,
		shape_str,
		" (按压)" if is_pressed else "",
		winning_layer,
		mode_str,
		trail_str,
		click_str,
	]


## 格式化主题预设中文名称。
static func format_theme_preset(preset: int) -> String:
	match preset:
		ThemePreset.OS_NATIVE:
			return "系统原生鼠标 (无自定义主题)"
		ThemePreset.CYBER_PROCEDURAL:
			return "赛博青白主题 (内置程序化)"
		ThemePreset.CRIMSON_TACTICAL:
			return "绯红战术主题 (自定义构建示例)"
		_:
			return "未知主题"

#endregion
