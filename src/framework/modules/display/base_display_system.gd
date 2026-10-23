@abstract
class_name BaseDisplaySystem
extends Node

## 全局显示设备、视口舞台、异形屏安全区与画布分层门面契约（Display System Facade Contract）。[br]
##
## [b]核心职责（第一性原理）：[/b][br]
## 1. [b]五大标准画布分层（Canvas Layers）[/b]：统一托管 [code]BACKGROUND(10) / MAIN(20) / POPUP(30) / TOAST(40) / TOP(50)[/code]；[br]
## 2. [b]窗口显示模式状态机[/b]：统一掌管窗口化、无边框窗口、无边框全屏与独占全屏切换，切回窗口化时自动恢复边框并居中；[br]
## 3. [b]分辨率钳制与多显示器居中[/b]：设置窗口分辨率时自动钳制在当前显示器可用工作区内，杜绝标题栏或按钮飞出屏幕外；[br]
## 4. [b]宽高比与拉伸策略（Stretch Mode & Aspect）[/b]：动态配置根视口缩放模式、宽高比策略与全局缩放倍率；[br]
## 5. [b]异形屏安全区逆矩阵投影（Notch Safe Area）[/b]：基于 [method Viewport.get_final_transform] 逆矩阵精确换算逻辑画布安全区并支持锁定设计宽高比；[br]
## 6. [b]垂直同步、帧率上限与硬件诊断[/b]：提供 VSync、最大 FPS、屏幕刷新率、DPI 与高分屏缩放系数读写。[br]
##
## 业务代码统一通过 [code]App.display[/code] 访问本契约提供的方法。

#region Enums & Constants
## 全局画布渲染层级枚举
enum Layer {
	BACKGROUND = 10,  ## 背景层（全屏动态背景、视差贴图）
	MAIN = 20,        ## 场景主界面层（HUD、操作栏、血条）
	POPUP = 30,       ## 模态弹窗层（结算页、选卡升级、设置菜单）
	TOAST = 40,       ## 飘字提示层（轻量系统通知、获得道具浮窗）
	TOP = 50,         ## 系统顶层（全屏 Loading 遮罩、Debug 控制台）
}

## 标准窗口显示模式枚举
enum WindowMode {
	WINDOWED = 0,             ## 标准有边框窗口模式
	BORDERLESS_WINDOWED = 1,  ## 无边框窗口模式（非全屏尺寸）
	FULLSCREEN = 2,           ## 无边框全屏模式（推荐，切屏顺滑）
	EXCLUSIVE_FULLSCREEN = 3, ## 独占全屏模式（绕过桌面合成器，最低输入延迟）
}

## 全局默认安全区缩放比例下限与默认值（统一在 DisplaySystem 与 GameSettingsModel 中管控）
const MIN_SAFE_AREA_SCALE: float = 0.80
const MAX_SAFE_AREA_SCALE: float = 1.00
const DEFAULT_SAFE_AREA_SCALE: float = 1.00

## 常见主流分辨率梯度预设（覆盖 16:9 / 16:10 / 21:9）
const COMMON_RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(1920, 1200),
	Vector2i(2560, 1080),
	Vector2i(2560, 1440),
	Vector2i(2560, 1600),
	Vector2i(3440, 1440),
	Vector2i(3840, 2160),
]
#endregion


#region 1. Canvas Layer Management
## 获取指定层级类型的 [CanvasLayer] 容器节点。[br]
## [param layer_type] 画布层级枚举（参见 [enum Layer]）。
@abstract
func get_layer(layer_type: int) -> CanvasLayer
#endregion


#region 2. Window Mode State Machine
## 设置游戏窗口显示模式（窗口化、无边框窗口、全屏、独占全屏）。
@abstract
func set_window_mode(mode: WindowMode, screen_index: int = -1) -> Result


## 获取当前窗口的显示模式枚举。
@abstract
func get_window_mode() -> WindowMode


## 当前是否处于全屏或独占全屏状态。
@abstract
func is_fullscreen() -> bool


## 一键切换全屏 / 窗口模式（默认在 [constant WindowMode.FULLSCREEN] 与 [constant WindowMode.WINDOWED] 间切换）。
@abstract
func toggle_fullscreen(use_exclusive: bool = false) -> Result
#endregion


#region 3. Resolution, Multi-Monitor & Clamping
## 设置窗口物理像素分辨率（窗口化模式下自动将宽高钳制在显示器可用工作区内并居中）。
@abstract
func set_resolution(
	size: Vector2i,
	center_on_screen: bool = true,
	clamp_to_usable_screen: bool = true
) -> Result


## 获取当前窗口的物理像素尺寸。
@abstract
func get_resolution() -> Vector2i


## 获取指定显示器的原生制造分辨率（[code]screen_index = -1[/code] 表示当前窗口所在显示器）。
@abstract
func get_screen_size(screen_index: int = -1) -> Vector2i


## 获取指定显示器扣除任务栏/系统菜单栏后的可用工作区矩形。
@abstract
func get_usable_screen_rect(screen_index: int = -1) -> Rect2i


## 将当前窗口精确居中于目标显示器的可用工作区内。
@abstract
func center_window(screen_index: int = -1) -> void


## 获取适配当前物理显示器上限的可选分辨率列表（按像素面积升序排列，自动包含显示器原生分辨率）。
@abstract
func get_available_resolutions(
	presets: Array[Vector2i] = COMMON_RESOLUTIONS,
	screen_index: int = -1
) -> Array[Vector2i]
#endregion


#region 4. Aspect Ratio, Stretch Mode & Content Scale
## 动态配置根窗口的内容拉伸模式、宽高比策略、基准设计分辨率及整体缩放系数。
@abstract
func configure_stretch(
	stretch_mode: Window.ContentScaleMode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS,
	stretch_aspect: Window.ContentScaleAspect = Window.CONTENT_SCALE_ASPECT_EXPAND,
	base_size: Vector2i = Vector2i.ZERO,
	scale_factor: float = 1.0
) -> Result


## 获取项目配置的基准设计分辨率（读取自 [code]display/window/size/viewport_width & height[/code]）。
@abstract
func get_design_size() -> Vector2


## 获取项目基准设计宽高比（宽 / 高，如 1920x1080 为 1.7778）。
@abstract
func get_design_aspect() -> float


## 获取当前物理窗口的实际宽高比（宽 / 高）。
@abstract
func get_window_aspect() -> float
#endregion


#region 5. Display Safe Area & Aspect-Ratio Guard
## 全局安全区默认配置（比例或宽高比锁定）发生变更时发射
@warning_ignore("unused_signal")
signal safe_area_changed()

## 设置全局默认安全区缩放比例（[code]0.80 ~ 1.00[/code]，默认 [code]1.0[/code] 表示 100% 贴合安全区，[code]0.90[/code] 表示四周向内留白 10%）。
@abstract
func set_safe_area_scale(scale_ratio: float) -> void


## 获取当前全局默认安全区缩放比例。
@abstract
func get_safe_area_scale() -> float


## 设置全局默认是否在安全区内锁定项目基准设计宽高比（超宽屏/异形屏下居中内接 UI 安全框）。
@abstract
func set_lock_design_aspect(locked: bool) -> void


## 获取当前全局默认是否锁定设计宽高比。
@abstract
func is_lock_design_aspect() -> bool


## 获取逻辑视口坐标系（Canvas Space）下的异形屏安全区矩形 [Rect2]。
@abstract
func get_safe_area_rect(viewport: Viewport = null) -> Rect2


## 获取逻辑视口坐标系下的异形屏四周安全区内边距字典 [code]{"left", "top", "right", "bottom"}[/code]。
@abstract
func get_safe_area_margins(
	viewport: Viewport = null,
	lock_design_aspect: bool = false
) -> Dictionary


## 将异形屏安全区边距自动应用到目标 [Control] 节点（支持 [MarginContainer] 主题常量覆盖或普通 [Control] 锚点内缩）。
@abstract
func apply_safe_area(
	control: Control,
	lock_design_aspect: bool = false
) -> Result
#endregion


#region 6. VSync, Frame Rate Cap & Hardware Diagnostics
## 设置垂直同步模式（如 [constant DisplayServer.VSYNC_ENABLED] 或 [constant DisplayServer.VSYNC_DISABLED]）。
@abstract
func set_vsync_mode(mode: DisplayServer.VSyncMode) -> void


## 获取当前垂直同步模式。
@abstract
func get_vsync_mode() -> DisplayServer.VSyncMode


## 设置引擎最大渲染帧率上限（传 [code]0[/code] 表示不限制）。
@abstract
func set_max_fps(max_fps: int) -> void


## 获取当前引擎最大渲染帧率上限。
@abstract
func get_max_fps() -> int


## 获取指定显示器的刷新率（Hz；无法检测时返回 [code]60.0[/code]）。
@abstract
func get_screen_refresh_rate(screen_index: int = -1) -> float


## 获取指定显示器的物理 DPI。
@abstract
func get_screen_dpi(screen_index: int = -1) -> int


## 获取指定显示器的操作系统高分屏缩放系数（如 macOS Retina 或 Windows 150%/200% 缩放）。
@abstract
func get_screen_scale(screen_index: int = -1) -> float
#endregion


#region 7. Viewport Rendering Pipeline Primitives
## 设置根视口 2D 多重采样抗锯齿等级（[enum Viewport.MSAA]，如 [constant Viewport.MSAA_DISABLED] / [constant Viewport.MSAA_2X] / [constant Viewport.MSAA_4X]）。[br]
## 内置幂等短路保护：若目标等级与当前一致则不触发底层帧缓冲重建，避免切屏卡顿。
@abstract
func set_msaa_2d(mode: Viewport.MSAA) -> void


## 获取当前根视口 2D 多重采样抗锯齿等级。
@abstract
func get_msaa_2d() -> Viewport.MSAA


## 设置根视口 3D 多重采样抗锯齿等级（[enum Viewport.MSAA]）。
@abstract
func set_msaa_3d(mode: Viewport.MSAA) -> void


## 获取当前根视口 3D 多重采样抗锯齿等级。
@abstract
func get_msaa_3d() -> Viewport.MSAA


## 设置根视口后处理屏幕空间抗锯齿模式（[enum Viewport.ScreenSpaceAA]，如 [constant Viewport.SCREEN_SPACE_AA_DISABLED] / [constant Viewport.SCREEN_SPACE_AA_FXAA]）。
@abstract
func set_screen_space_aa(mode: Viewport.ScreenSpaceAA) -> void


## 获取当前根视口屏幕空间抗锯齿模式。
@abstract
func get_screen_space_aa() -> Viewport.ScreenSpaceAA


## 设置根视口 3D 渲染分辨率缩放比例（[code]0.25 ~ 2.0[/code]，默认 [code]1.0[/code]）。
@abstract
func set_scaling_3d_scale(scale: float) -> void


## 获取当前根视口 3D 渲染分辨率缩放比例。
@abstract
func get_scaling_3d_scale() -> float


## 设置根视口 2D 画布默认纹理过滤模式（[enum Viewport.DefaultCanvasItemTextureFilter]，像素风常用 Nearest，高清/骨骼动画常用 Linear）。
@abstract
func set_canvas_texture_filter(filter: Viewport.DefaultCanvasItemTextureFilter) -> void


## 获取当前根视口 2D 画布默认纹理过滤模式。
@abstract
func get_canvas_texture_filter() -> Viewport.DefaultCanvasItemTextureFilter
#endregion
