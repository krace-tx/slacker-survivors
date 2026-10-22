class_name AudioSettingsData
extends BaseParams

## 音频与声音设置子数据块（位于 src/game/shared/model/data/）。[br]
##
## [b]核心职责：[/b][br]
## 1. 承载主音量、背景音乐、音效、语音、环境音五通道线性音量标量；[br]
## 2. 维护正交隔离的静音开关（静音时不破坏音量滑块记忆值）与后台失焦自动静音开关。


#region 成员属性

## 主音量线性标量 `[0.0, 1.0]`
var master_volume: float = 1.0

## 背景音乐线性标量 `[0.0, 1.0]`
var bgm_volume: float = 0.8

## 音效线性标量 `[0.0, 1.0]`
var sfx_volume: float = 1.0

## 语音配音线性标量 `[0.0, 1.0]`
var voice_volume: float = 1.0

## 环境音线性标量 `[0.0, 1.0]`
var ambient_volume: float = 1.0

## 主音量静音开关（正交隔离：静音时不破坏 master_volume 滑块记忆值）
var master_muted: bool = false

## 背景音乐总开关
var music_enabled: bool = true

## 音效总开关
var sfx_enabled: bool = true

## 语音总开关
var voice_enabled: bool = true

## 环境音总开关
var ambient_enabled: bool = true

## 切后台或窗口失焦时是否自动静音暂停音频
var mute_in_background: bool = true

#endregion


#region 公开方法

## 对音频通道音量执行 `[0.0, 1.0]` 合法范围钳制自愈，返回自身支持链式调用。
func sanitize() -> AudioSettingsData:
	master_volume = clampf(master_volume, 0.0, 1.0)
	bgm_volume = clampf(bgm_volume, 0.0, 1.0)
	sfx_volume = clampf(sfx_volume, 0.0, 1.0)
	voice_volume = clampf(voice_volume, 0.0, 1.0)
	ambient_volume = clampf(ambient_volume, 0.0, 1.0)
	return self


## 重置当前音频数据块为出厂默认值。
func reset() -> void:
	var defaults := AudioSettingsData.new()
	from_dict(defaults.to_dict())

#endregion
