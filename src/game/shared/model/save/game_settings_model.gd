class_name GameSettingsModel
extends BaseParams

## 游戏全局偏好设置存档模型（位于 src/game/shared/model/save/）。[br]
##
## [b]核心设计（五大领域分组聚合根）：[/b][br]
## 1. 采用独立拆分的 [BaseParams] 子数据块（`*Data`）将全局设置正交划分为五大领域分组：[br]
##    - [member display]（[DisplaySettingsData]）：显示器、窗口模式、分辨率、帧率上限、后台降帧、安全区与亮度；[br]
##    - [member graphics]（[GraphicsSettingsData]）：画质档位预设、渲染倍率、MSAA、FXAA/SMAA、纹理过滤、特效密度与阴影；[br]
##    - [member audio]（[AudioSettingsData]）：主音量/音乐/音效/语音/环境音五通道音量、正交静音开关与后台失焦静音；[br]
##    - [member control]（[ControlSettingsData]）：物理触感震动开关/强度、手柄摇杆死区、鼠标灵敏度、虚拟摇杆模式与自定义改键映射；[br]
##    - [member general]（[GeneralSettingsData]）：多语言区域标识（支持首次启动自动匹配系统语言）；[br]
## 2. 依托 [BaseParams] 递归模具推导，自动序列化为结构清晰的分组 JSON，并支持按分组独立 `reset()` / `clone()` / `sanitize()`。


#region 信号与常量

signal data_changed()

const STORAGE_KEY: StringName = &"game_settings"
const _STORAGE_DISK_PATH: String = "user://saves/game_settings.json"
const _STORAGE_SCHEMA_VERSION: int = 2
const DEFAULT_LOCALE: String = GeneralSettingsData.DEFAULT_LOCALE

#endregion


#region 聚合根五大分组属性

## 显示与窗口设置数据块
var display: DisplaySettingsData = DisplaySettingsData.new()

## 画质与视口渲染设置数据块
var graphics: GraphicsSettingsData = GraphicsSettingsData.new()

## 音频与静音设置数据块
var audio: AudioSettingsData = AudioSettingsData.new()

## 操作、输入与震动设置数据块
var control: ControlSettingsData = ControlSettingsData.new()

## 语言与通用设置数据块
var general: GeneralSettingsData = GeneralSettingsData.new()

#endregion


#region 公开方法

## 创建全局偏好设置标准存储配置项
static func storage_item() -> StorageItem:
	return StorageItem.new(
		STORAGE_KEY,
		_STORAGE_DISK_PATH,
		_STORAGE_SCHEMA_VERSION,
		-1.0
	)


## 对五大分组执行合法范围钳制自愈（防止外部篡改 JSON 或子组为空导致异常），返回自身支持链式调用。
func sanitize() -> GameSettingsModel:
	if display == null:
		display = DisplaySettingsData.new()
	if graphics == null:
		graphics = GraphicsSettingsData.new()
	if audio == null:
		audio = AudioSettingsData.new()
	if control == null:
		control = ControlSettingsData.new()
	if general == null:
		general = GeneralSettingsData.new()

	display.sanitize()
	graphics.sanitize()
	audio.sanitize()
	control.sanitize()
	general.sanitize()
	return self


## 根据给定的画质预设档位一键展开底层视口渲染参数。
func apply_quality_preset_values(preset: int) -> void:
	if graphics == null:
		graphics = GraphicsSettingsData.new()
	graphics.apply_preset(preset)


## 触发设置数据变更通知
func notify_changed() -> void:
	data_changed.emit()

#endregion
