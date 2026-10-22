class_name ControlSettingsData
extends BaseParams

## 操作、输入与物理震动设置子数据块（位于 src/game/shared/model/data/）。[br]
##
## [b]核心职责：[/b][br]
## 1. 承载物理触感震动总开关与强度、手柄摇杆死区、鼠标/视角灵敏度、移动端虚拟摇杆模式；[br]
## 2. 内聚定义移动端虚拟摇杆模式枚举 [enum VirtualJoystickMode]；[br]
## 3. 持有自定义键位增量映射补丁字典（对接 [method BaseInputSystem.export_bindings] 与 [method BaseInputSystem.import_bindings]）。


#region 枚举定义

## 移动端虚拟摇杆模式枚举
enum VirtualJoystickMode {
	FIXED = 0,    ## 固定位置摇杆
	FOLLOW = 1,   ## 跟随手指移动摇杆
	FLOATING = 2, ## 落点自由浮动摇杆
}

#endregion


#region 成员属性

## 物理触感震动（手柄马达 / 移动设备振动）总开关
var haptic_enabled: bool = true

## 物理震动强度系数 `[0.0, 1.0]`（默认 1.0）
var haptic_strength: float = 1.0

## 手柄摇杆死区 `[0.05, 0.90]`
var joy_deadzone: float = 0.20

## 鼠标/视角旋转灵敏度倍率 `[0.10, 3.00]`（默认 1.0）
var mouse_sensitivity: float = 1.0

## 移动端虚拟摇杆模式（对应 [enum VirtualJoystickMode]：0=固定, 1=跟随, 2=浮动）
var virtual_joystick_mode: int = VirtualJoystickMode.FIXED

## 自定义键位增量映射补丁字典（由 [method BaseInputSystem.export_bindings] 导出）
var input_bindings: Dictionary = {}

#endregion


#region 公开方法

## 对操作与震动参数执行合法范围钳制自愈，返回自身支持链式调用。
func sanitize() -> ControlSettingsData:
	haptic_strength = clampf(haptic_strength, 0.0, 1.0)
	joy_deadzone = clampf(joy_deadzone, 0.05, 0.90)
	mouse_sensitivity = clampf(mouse_sensitivity, 0.10, 3.00)
	virtual_joystick_mode = clampi(
		virtual_joystick_mode,
		VirtualJoystickMode.FIXED,
		VirtualJoystickMode.FLOATING
	)
	return self


## 重置当前操作数据块为出厂默认值。
func reset() -> void:
	var defaults := ControlSettingsData.new()
	from_dict(defaults.to_dict())

#endregion
