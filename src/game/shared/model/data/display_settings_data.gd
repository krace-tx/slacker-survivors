class_name DisplaySettingsData
extends BaseParams

## 显示与窗口设置子数据块（位于 src/game/shared/model/data/）。[br]
##
## [b]核心职责：[/b][br]
## 1. 承载显示器索引、窗口模式、物理分辨率、垂直同步、前台/后台帧率上限、安全区比例、设计宽高比锁定与画面亮度；[br]
## 2. 作为 [GameSettingsModel] 的内嵌子结构（`*Data`），支持独立 `sanitize()`、`reset()` 与 `clone()` 切屏事务快照。


#region 成员属性

## 目标显示器索引（0 表示主显示器）
var screen_index: int = 0

## 窗口显示模式（对应 [enum BaseDisplaySystem.WindowMode]：0=窗口化, 1=无边框窗口, 2=无边框全屏, 3=独占全屏）
var window_mode: int = BaseDisplaySystem.WindowMode.WINDOWED

## 窗口分辨率宽度（0 表示保持工程默认或当前显示器自适应）
var resolution_width: int = 0

## 窗口分辨率高度（0 表示保持工程默认或当前显示器自适应）
var resolution_height: int = 0

## 垂直同步开关
var vsync_enabled: bool = true

## 前台最大帧率上限（0 表示不限制，常见档位：30 / 60 / 120 / 144 / 240）
var max_fps: int = 0

## 窗口切后台/失焦时的省电帧率上限（0 表示不降帧，默认 30 FPS）
var background_max_fps: int = 30

## 全局 HUD 边界安全区缩放比例 `[0.80, 1.00]`（默认 1.0 表示 100% 贴合安全区）
var safe_area_scale: float = BaseDisplaySystem.DEFAULT_SAFE_AREA_SCALE

## 是否在异形屏/超宽屏下锁定项目基准设计宽高比（居中内接）
var lock_design_aspect: bool = false

## 全局画面亮度/Gamma 系数 `[0.50, 1.50]`（默认 1.0）
var brightness: float = 1.0

#endregion


#region 公开方法

## 对显示与窗口参数执行合法范围钳制自愈，返回自身支持链式调用。
func sanitize() -> DisplaySettingsData:
	screen_index = maxi(0, screen_index)
	window_mode = clampi(
		window_mode,
		BaseDisplaySystem.WindowMode.WINDOWED,
		BaseDisplaySystem.WindowMode.EXCLUSIVE_FULLSCREEN
	)
	resolution_width = maxi(0, resolution_width)
	resolution_height = maxi(0, resolution_height)
	max_fps = maxi(0, max_fps)
	background_max_fps = maxi(0, background_max_fps)
	safe_area_scale = clampf(
		safe_area_scale,
		BaseDisplaySystem.MIN_SAFE_AREA_SCALE,
		BaseDisplaySystem.MAX_SAFE_AREA_SCALE
	)
	brightness = clampf(brightness, 0.50, 1.50)
	return self


## 重置当前显示数据块为出厂默认值。
func reset() -> void:
	var defaults := DisplaySettingsData.new()
	from_dict(defaults.to_dict())

#endregion
