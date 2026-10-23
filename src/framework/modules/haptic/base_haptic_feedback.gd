@abstract
class_name BaseHapticFeedback
extends RefCounted

## 跨平台触觉反馈门面契约（Cross-Platform Haptic Feedback Contract）。[br]
##
## 本抽象基类作为业务层触发物理与跨模态触觉反馈的唯一规范入口，核心职责：[br]
## 1. **三端差异化物理适配（统一语义输入，分端硬件翻译）**：[br]
##    - **手机端（Mobile）**：克制时长 + 振幅分级 + 短脉冲序列，清脆不麻手；[br]
##    - **手柄端（Gamepad）**：高低频双马达（Weak 高频小转子 + Strong 低频大配重）独立配比 + 最小起振时长补偿（克服转子物理惯性）；[br]
##    - **电脑键鼠端（PC Keyboard/Mouse）**：闲置 USB 手柄防空震静默隔离 + 发射 [signal haptic_pulsed] 信号供镜头震屏/UI 视觉冲击桥接。[br]
## 2. **优先级防打断与高频节流（Priority & Throttle Guard）**：[br]
##    - 高优先级震动（如 [constant HapticIntensity.HEAVY] 受重创）执行期间，绝不会被高频低优震动（如拾取经验球）打断；[br]
##    - 内置最小节流时间窗，防止幸存者同屏怪潮高频触发导致马达过载与计时器泛滥。[br]
## 3. **统一开关与后台急停**：管理玩家振动总开关 [member enabled]，切后台或关闭开关时自动急停全部马达。[br]
##
## 业务代码应统一通过 [code]App.haptic[/code] 访问本契约提供的方法。


## 当任意一段有效触觉脉冲被触发时广播（可供 PC 键鼠端或全平台相机组件按需订阅，将 MEDIUM/HEAVY 触觉转化为微小视觉震屏冲量）。[br]
## [param intensity] 触觉强度等级（参见 [HapticIntensity]）。[br]
## [param amplitude] 归一化强度振幅（[code]0.0 ~ 1.0[/code]）。[br]
## [param duration_ms] 当前脉冲步长毫秒数。
@warning_ignore("unused_signal")
signal haptic_pulsed(intensity: int, amplitude: float, duration_ms: int)


#region Constants
## 预设轻触序列（兼容常量）：12ms 清脆点触
const LIGHT: Array[int] = [12]

## 预设中击序列（兼容常量）：28ms 中等冲击
const MEDIUM: Array[int] = [28]

## 预设重击序列（兼容常量）：40ms 强冲击 -> 35ms 停顿 -> 60ms 余震
const HEAVY: Array[int] = [40, 35, 60]
#endregion


## 玩家全局振动总开关（由设置菜单切换并持久化同步）。
var enabled: bool = true


#region 1. Switch & Lifecycle Control
## 更新玩家振动总开关状态（关闭时立即终止正在执行的震动序列与手柄马达）。[br]
##
## [param value] 是否允许触发震动反馈。
@abstract
func set_enabled(value: bool) -> void


## 立即停止当前正在执行的任何震动序列与所有已连接手柄的物理马达。
@abstract
func stop() -> void
#endregion


#region 2. Semantic Tier APIs (三端自适应语义接口 · 推荐优先使用)
## 触发【轻触级（LIGHT）】反馈（适用：按钮点击、拾取经验宝石、高频轻反馈）。[br]
## - 手机：12ms 低振幅（0.35）清脆点触；[br]
## - 手柄：40ms 纯高频小马达（Weak 0.35 / Strong 0.0）；[br]
## - 键鼠：物理静默，发射 LIGHT 级 [signal haptic_pulsed]。
@abstract
func light() -> void


## 触发【中击级（MEDIUM）】反馈（适用：精英怪击杀、技能进化、普通受击）。[br]
## - 手机：28ms 中高振幅（0.70）短脉冲；[br]
## - 手柄：75ms 高频主导 + 中度低频双马达（Weak 0.70 / Strong 0.45）；[br]
## - 键鼠：物理静默，发射 MEDIUM 级 [signal haptic_pulsed]。
@abstract
func medium() -> void


## 触发【重击级（HEAVY）】反馈（适用：玩家受重创、Boss 登场/砸地、宝箱暴击）。[br]
## - 手机：[code][40ms, 35ms, 60ms][/code] 高振幅快慢双脉冲；[br]
## - 手柄：[code][110ms, 40ms, 130ms][/code] 低频大马达满载双波轰鸣；[br]
## - 键鼠：物理静默，发射 HEAVY 级 [signal haptic_pulsed]。[br]
## 执行期间不会被 [method light] 或 [method medium] 打断。
@abstract
func heavy() -> void
#endregion


#region 3. Custom Parameterized APIs (自定义时序与双马达精控接口)
## 触发单次自定义时长与振幅的触觉振动。[br]
##
## [param duration_ms] 震动持续时长（毫秒，默认 15ms）。若使用默认参数调用，等效于 [method light]。[br]
## [param amplitude] 振幅强度（[code]0.0 ~ 1.0[/code]，传负数表示按 [param priority] 自动匹配默认振幅）。[br]
## [param priority] 抢占优先级（取值 [HapticIntensity]，默认 [constant HapticIntensity.LIGHT]）。
@abstract
func vibrate(
	duration_ms: int = 15,
	amplitude: float = -1.0,
	priority: int = HapticIntensity.LIGHT
) -> void


## 按照自定义间隔序列执行节奏型振动。[br]
##
## [param steps] 毫秒序列数组。偶数下标表示振动时长，奇数下标表示静止间隔（如 [code][40, 35, 60][/code]）。[br]
## [param amplitude] 脉冲振幅（[code]0.0 ~ 1.0[/code]，传负数表示按 [param priority] 自动匹配）。[br]
## [param priority] 抢占优先级（取值 [HapticIntensity]，默认 [constant HapticIntensity.MEDIUM]）。
@abstract
func pattern(
	steps: Array[int],
	amplitude: float = -1.0,
	priority: int = HapticIntensity.MEDIUM
) -> void


## 显式驱动手柄高低频双马达（同时在移动端按综合强度折算为手持震动）。[br]
##
## [param weak_magnitude] 右握把高频小马达强度（[code]0.0 ~ 1.0[/code]，清脆细节感）。[br]
## [param strong_magnitude] 左握把低频大配重马达强度（[code]0.0 ~ 1.0[/code]，厚重轰鸣感）。[br]
## [param duration_ms] 持续时长（毫秒，手柄端自动保底不少于 35ms 起振阈值）。[br]
## [param priority] 抢占优先级（默认 [constant HapticIntensity.CUSTOM]）。
@abstract
func rumble_joypad(
	weak_magnitude: float,
	strong_magnitude: float,
	duration_ms: int,
	priority: int = HapticIntensity.CUSTOM
) -> void
#endregion
