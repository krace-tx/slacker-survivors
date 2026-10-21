class_name HapticIntensity
extends RefCounted

## 触觉反馈强度与抢占优先级枚举（Haptic Intensity & Preemption Priority）。[br]
##
## 调用形如 [code]HapticIntensity.LIGHT[/code]、[code]HapticIntensity.MEDIUM[/code]、[code]HapticIntensity.HEAVY[/code]。[br]
## 数值越大代表冲击感越强、抢占优先级越高（低优先级请求不会打断正在播放的高优先级震动序列）。

enum {
	LIGHT = 1,  ## 轻触级：按钮点击、拾取经验球、高频微反馈（手机短促点触 / 手柄纯高频小马达）
	MEDIUM = 2, ## 中击级：精英击杀、技能升级、普通受击（手机中等脉冲 / 手柄高频主导+中度低频）
	HEAVY = 3,  ## 重击级：玩家受重创、Boss 登场、宝箱暴击（手机快慢双脉冲 / 手柄低频大马达满载双波轰鸣）
	CUSTOM = 2, ## 自定义序列默认优先级（与 MEDIUM 同级）
}


## 将强度枚举值转换为可读名称。
static func to_name(intensity: int) -> String:
	match intensity:
		LIGHT:
			return "LIGHT"
		MEDIUM:
			return "MEDIUM"
		HEAVY:
			return "HEAVY"
		_:
			return "CUSTOM"
