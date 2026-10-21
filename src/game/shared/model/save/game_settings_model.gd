class_name GameSettingsModel
extends BaseParams

## 游戏全局偏好设置存档模型（位于 src/game/shared/model/save/）。[br]
##
## [b]核心职责（遵循 `*Model` 领域后缀规范）：[/b][br]
## 1. 承载跨模块共享的【音频总线与静音】、【窗口模式与帧率】、【画质预设与底层视口渲染管线】及【多语言/触感/输入映射】全量通用配置；[br]
## 2. 严格保持纯数据实体属性（继承 [BaseParams]，不直接调用 [code]App.*[/code] 或执行磁盘 I/O）；[br]
## 3. 内置 [method sanitize] 边界自愈钳制与 [method apply_quality_preset_values] 预设档位展开逻辑。

signal data_changed()

#region Constants
const _STORAGE_DISK_PATH: String = "user://saves/game_settings.json"
const _STORAGE_SCHEMA_VERSION: int = 1
const _DEFAULT_LOCALE: String = "zh-CN"
#endregion

#region 1. Audio Preferences
## 主音量线性标量 `[0.0, 1.0]`
var master_volume: float = 1.0
## 背景音乐线性标量 `[0.0, 1.0]`
var bgm_volume: float = 0.8
## 音效线性标量 `[0.0, 1.0]`
var sfx_volume: float = 1.0
## 主音量静音开关（静音时不破坏 master_volume 滑块记忆值）
var master_muted: bool = false
## 背景音乐总开关
var music_enabled: bool = true
## 音效总开关
var sfx_enabled: bool = true
## 切后台或窗口失焦时是否自动静音暂停音频
var mute_in_background: bool = true
#endregion

#region 2. Window & Display Preferences
## 窗口显示模式（对应 [enum BaseDisplaySystem.WindowMode]：0=窗口化, 1=无边框窗口, 2=无边框全屏, 3=独占全屏）
var window_mode: int = BaseDisplaySystem.WindowMode.WINDOWED
## 窗口分辨率宽度（0 表示保持工程默认或当前显示器自适应）
var resolution_width: int = 0
## 窗口分辨率高度（0 表示保持工程默认或当前显示器自适应）
var resolution_height: int = 0
## 垂直同步开关
var vsync_enabled: bool = true
## 最大帧率上限（0 表示不限制，常见档位：30 / 60 / 120 / 144 / 240）
var max_fps: int = 0
#endregion

#region 3. Graphics Quality Preset & Viewport Rendering Pipeline
## 全局画质预设档位（对应 [enum GameEnums.QualityPreset]：0=LOW, 1=MEDIUM, 2=HIGH, 3=ULTRA, 4=CUSTOM）
var quality_preset: int = GameEnums.QualityPreset.HIGH
## 2D 多重采样抗锯齿等级（对应 [enum Viewport.MSAA]：0=Disabled, 1=2X, 2=4X, 3=8X）
var msaa_2d: int = Viewport.MSAA_2X
## 3D 多重采样抗锯齿等级（对应 [enum Viewport.MSAA]：0=Disabled, 1=2X, 2=4X, 3=8X）
var msaa_3d: int = Viewport.MSAA_2X
## 屏幕空间后处理抗锯齿（对应 [enum Viewport.ScreenSpaceAA]：0=Disabled, 1=FXAA, 2=SMAA）
var screen_space_aa: int = Viewport.SCREEN_SPACE_AA_FXAA
## 3D 渲染分辨率缩放倍率 `[0.5, 2.0]`（默认 1.0）
var render_scale: float = 1.0
## 2D 画布默认纹理过滤模式（对应 [enum Viewport.DefaultCanvasItemTextureFilter]：1=Linear, 0=Nearest）
var canvas_texture_filter: int = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
#endregion

#region 4. Locale, Haptic & Input Preferences
## 语言区域标识（BCP-47 标签，如 `"zh-CN"` / `"en-US"`）
var locale: String = _DEFAULT_LOCALE
## 物理触感震动（手柄马达 / 移动设备振动）开关
var haptic_enabled: bool = true
## 手柄摇杆死区 `[0.05, 0.90]`
var joy_deadzone: float = 0.20
## 自定义键位增量映射补丁字典（由 [method BaseInputSystem.export_bindings] 导出）
var input_bindings: Dictionary = {}
#endregion


#region Public API
## 创建全局偏好设置标准存储配置项
static func storage_item() -> StorageItem:
	return StorageItem.new(
		GameConstants.KEY_GAME_SETTINGS,
		_STORAGE_DISK_PATH,
		_STORAGE_SCHEMA_VERSION,
		-1.0
	)


## 对所有配置字段执行合法范围钳制自愈（防止外部篡改 JSON 导致引擎异常），返回自身以支持链式调用。
func sanitize() -> GameSettingsModel:
	master_volume = clampf(master_volume, 0.0, 1.0)
	bgm_volume = clampf(bgm_volume, 0.0, 1.0)
	sfx_volume = clampf(sfx_volume, 0.0, 1.0)

	window_mode = clampi(
		window_mode,
		BaseDisplaySystem.WindowMode.WINDOWED,
		BaseDisplaySystem.WindowMode.EXCLUSIVE_FULLSCREEN
	)
	resolution_width = maxi(0, resolution_width)
	resolution_height = maxi(0, resolution_height)
	max_fps = maxi(0, max_fps)

	quality_preset = clampi(
		quality_preset,
		GameEnums.QualityPreset.LOW,
		GameEnums.QualityPreset.CUSTOM
	)
	msaa_2d = clampi(msaa_2d, Viewport.MSAA_DISABLED, Viewport.MSAA_8X)
	msaa_3d = clampi(msaa_3d, Viewport.MSAA_DISABLED, Viewport.MSAA_8X)
	screen_space_aa = clampi(
		screen_space_aa,
		Viewport.SCREEN_SPACE_AA_DISABLED,
		Viewport.SCREEN_SPACE_AA_MAX - 1
	)
	render_scale = clampf(render_scale, 0.5, 2.0)
	canvas_texture_filter = clampi(
		canvas_texture_filter,
		Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST,
		Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_MAX - 1
	)

	joy_deadzone = clampf(joy_deadzone, 0.05, 0.90)
	if locale.is_empty():
		locale = _DEFAULT_LOCALE
	return self


## 根据给定的画质预设档位（[enum GameEnums.QualityPreset]）一键展开底层视口渲染参数。
func apply_quality_preset_values(preset: int) -> void:
	match preset:
		GameEnums.QualityPreset.LOW:
			quality_preset = GameEnums.QualityPreset.LOW
			render_scale = 0.75
			msaa_2d = Viewport.MSAA_DISABLED
			msaa_3d = Viewport.MSAA_DISABLED
			screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		GameEnums.QualityPreset.MEDIUM:
			quality_preset = GameEnums.QualityPreset.MEDIUM
			render_scale = 1.0
			msaa_2d = Viewport.MSAA_DISABLED
			msaa_3d = Viewport.MSAA_DISABLED
			screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		GameEnums.QualityPreset.HIGH:
			quality_preset = GameEnums.QualityPreset.HIGH
			render_scale = 1.0
			msaa_2d = Viewport.MSAA_2X
			msaa_3d = Viewport.MSAA_2X
			screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		GameEnums.QualityPreset.ULTRA:
			quality_preset = GameEnums.QualityPreset.ULTRA
			render_scale = 1.0
			msaa_2d = Viewport.MSAA_4X
			msaa_3d = Viewport.MSAA_4X
			screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
		_:
			quality_preset = GameEnums.QualityPreset.CUSTOM


## 触发设置数据变更通知
func notify_changed() -> void:
	data_changed.emit()
#endregion
