class_name GameSettingsModel
extends BaseParams

## 游戏全局偏好设置模型 (Shared Domain Model)。[br]
##
## 职责：[br]
## 1. 承载跨模块共享的音量、静音开关、触感震动与多语言区域配置；[br]
## 2. 继承 [BaseParams]，自动具备 [method BaseParams.to_dict] 与 [method BaseParams.from_dict] 反射序列化能力；[br]
## 3. 与 [code]App.storage[/code] 中的 [constant GameConstants.KEY_GAME_SETTINGS] 持久层直接映射。

signal data_changed()

## 主音量 (0.0 ~ 1.0)
var master_volume: float = 1.0
## 背景音乐音量 (0.0 ~ 1.0)
var bgm_volume: float = 0.8
## 音效音量 (0.0 ~ 1.0)
var sfx_volume: float = 1.0
## 背景音乐总开关
var music_enabled: bool = true
## 音效总开关
var sfx_enabled: bool = true
## 触感震动开关
var haptic_enabled: bool = true
## 语言区域标识
var locale: String = "zh_CN"
## 手柄摇杆死区 (0.05 ~ 0.90)
var joy_deadzone: float = 0.20
## 自定义键位增量映射补丁字典（由 App.input.export_bindings() 导出）
var input_bindings: Dictionary = {}


## 触发设置变更通知
func notify_changed() -> void:
	data_changed.emit()
