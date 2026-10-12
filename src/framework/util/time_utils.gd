class_name TimeUtils
extends RefCounted

## 时间格式化，以及绑定节点生命周期的安全等待。
##
## [method now_string] 走系统墙钟（日志在校时前就要能用）；游戏权威时间是 [TimeService]。
## [method wait_safe] 在 await 恢复后校验节点仍存活，避免 Use-After-Free。

#region Constants & Enums
const _SECONDS_PER_MINUTE: int = 60
const _SECONDS_PER_HOUR: int = 3600
const _MS_PER_SECOND: int = 1000
#endregion

#region Public API
## 当前本地墙钟，格式 [code]YYYY-MM-DD HH:MM:SS.mmm[/code]。
static func now_string() -> String:
	var datetime := Time.get_datetime_string_from_system(false, true)
	var ms := int(Time.get_unix_time_from_system() * _MS_PER_SECOND) % _MS_PER_SECOND
	return "%s.%03d" % [datetime, ms]


## 秒数 → [code]MM:SS[/code]（例如 03:05）。
static func format_mm_ss(total_seconds: int) -> String:
	@warning_ignore("integer_division")
	var minutes := total_seconds / _SECONDS_PER_MINUTE
	var seconds := total_seconds % _SECONDS_PER_MINUTE
	return "%02d:%02d" % [minutes, seconds]


## 秒数 → [code]HH:MM:SS[/code]（例如 01:25:09）。
static func format_hh_mm_ss(total_seconds: int) -> String:
	@warning_ignore("integer_division")
	var hours := total_seconds / _SECONDS_PER_HOUR
	var remainder := total_seconds % _SECONDS_PER_HOUR
	@warning_ignore("integer_division")
	var minutes := remainder / _SECONDS_PER_MINUTE
	var seconds := remainder % _SECONDS_PER_MINUTE
	return "%02d:%02d:%02d" % [hours, minutes, seconds]


## 挂起 [param seconds] 秒；恢复后若 [param node] 已销毁则失败，调用方必须停下来。[br]
##
## [codeblock]
## var wait_res := await TimeUtils.wait_safe(self, 2.0)
## if wait_res.is_err():
##     return
## _fire_projectile()
## [/codeblock]
static func wait_safe(node: Node, seconds: float) -> Result:
	return await AsyncUtils.wait_safe(node, seconds)
#endregion
