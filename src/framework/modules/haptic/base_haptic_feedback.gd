@abstract
class_name BaseHapticFeedback
extends Subsystem

## 触觉振动反馈门面契约（Haptic Feedback Contract）。[br]
##
## 本抽象基类作为业务层触发移动设备马达物理震动的唯一规范入口，核心职责：[br]
## - 统一开关裁决：管理玩家振动总开关 [member enabled]，关闭时请求直接短路，不打扰玩家；[br]
## - 预设节奏模式：内置轻微触觉与连续强调震动；[br]
## - 自动打断：新的振动序列自动打断正在执行的上一段未完成振动，防止马达过热或延时混乱；[br]
## - 纯 RefCounted 实现，轻量、无需常驻场景树。[br]
##
## 业务代码应统一通过 [code]App.haptic[/code] 访问本契约提供的方法。


#region Constants
## 按钮点击反馈：超短轻微振动（15ms）
const LIGHT: Array[int] = [15]

## 受到重创或抽卡暴击：连续两下重震（振 100ms、停 50ms、再振 100ms）
const HEAVY: Array[int] = [100, 50, 100]
#endregion


## 玩家全局振动总开关（由设置菜单切换并持久化同步）。
var enabled: bool = true


## 返回该子系统的全局唯一注册标识符。
func get_id() -> String:
	return "haptic"


#region Public Haptic APIs
## 更新玩家振动总开关状态。[br]
##
## [param value] 是否允许触发震动反馈。
@abstract
func set_enabled(value: bool) -> void


## 触发单次短触觉振动。[br]
##
## [param duration_ms] 震动持续时长（毫秒，默认 15ms）。若小于等于 0 或总开关关闭则安全短路。
@abstract
func vibrate(duration_ms: int = 15) -> void


## 按照自定义间隔序列执行节奏型振动。[br]
##
## [param steps] 毫秒序列数组。偶数下标表示振动时长，奇数下标表示静止间隔。[br]
## 例如 [code][100, 50, 100][/code] 表示：振 100ms $\rightarrow$ 停 50ms $\rightarrow$ 振 100ms。[br]
## 再次调用会立刻打断并覆盖尚未播完的上一段振动。
@abstract
func pattern(steps: Array[int]) -> void
#endregion
