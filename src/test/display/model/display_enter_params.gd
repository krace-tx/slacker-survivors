class_name DisplayEnterParams
extends BaseParams

## 显示与画质测试模块路由入参契约与格式化工具（位于 src/test/display/model/）。


#region 成员变量

## 来源页面标识
var from_page: String = "lobby"

## 提示消息
var notice_text: String = ""

#endregion


#region 生命周期

func _init(p_from_page: String = "lobby", p_notice: String = "") -> void:
	from_page = p_from_page
	notice_text = p_notice

#endregion


#region 文本格式化工具

## 获取窗口模式中文名
static func format_window_mode(mode: int) -> String:
	match mode:
		BaseDisplaySystem.WindowMode.WINDOWED:
			return "窗口模式"
		BaseDisplaySystem.WindowMode.BORDERLESS_WINDOWED:
			return "无边框窗口"
		BaseDisplaySystem.WindowMode.FULLSCREEN:
			return "无边框全屏"
		BaseDisplaySystem.WindowMode.EXCLUSIVE_FULLSCREEN:
			return "独占全屏"
		_:
			return "未知"


## 获取垂直同步中文名
static func format_vsync(vsync_enabled: bool) -> String:
	return "开启" if vsync_enabled else "关闭"


## 获取画质预设中文名
static func format_quality_preset(preset: int) -> String:
	match preset:
		GraphicsSettingsData.QualityPreset.LOW:
			return "低"
		GraphicsSettingsData.QualityPreset.MEDIUM:
			return "中"
		GraphicsSettingsData.QualityPreset.HIGH:
			return "高"
		GraphicsSettingsData.QualityPreset.ULTRA:
			return "极高"
		GraphicsSettingsData.QualityPreset.CUSTOM:
			return "自定义"
		_:
			return "未知"


## 获取帧率上限文本
static func format_fps(fps: int) -> String:
	return "无限制" if fps <= 0 else "%d FPS" % fps

#endregion
