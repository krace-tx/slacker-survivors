class_name TimeUtils
extends RefCounted

## 时间计算与格式化纯函数工具类。[br]
##
## [method now_string] 走系统墙钟（日志在校时前即可调用）；游戏防作弊权威时钟请走 [code]App.clock[/code]。[br]
## 异步生命周期安全休眠与等待已统一收敛至 [TaskScope]（[method TaskScope.sleep] / [method TaskScope.wait]）。

#region Constants
const _SECONDS_PER_MINUTE: int = 60
const _SECONDS_PER_HOUR: int = 3600
const _MS_PER_SECOND: int = 1000
#endregion

#region Public API
## 当前本地墙钟字符串，格式 [code]YYYY-MM-DD HH:MM:SS.mmm[/code]。
static func now_string() -> String:
	var datetime := Time.get_datetime_string_from_system(false, true)
	var ms := int(Time.get_unix_time_from_system() * _MS_PER_SECOND) % _MS_PER_SECOND
	return "%s.%03d" % [datetime, ms]


## 秒数 → [code]MM:SS[/code]（例如 03:05）。
static func format_mm_ss(total_seconds: int) -> String:
	var safe_sec := maxi(0, total_seconds)
	@warning_ignore("integer_division")
	var minutes := safe_sec / _SECONDS_PER_MINUTE
	var seconds := safe_sec % _SECONDS_PER_MINUTE
	return "%02d:%02d" % [minutes, seconds]


## 秒数 → [code]HH:MM:SS[/code]（例如 01:25:09）。
static func format_hh_mm_ss(total_seconds: int) -> String:
	var safe_sec := maxi(0, total_seconds)
	@warning_ignore("integer_division")
	var hours := safe_sec / _SECONDS_PER_HOUR
	var remainder := safe_sec % _SECONDS_PER_HOUR
	@warning_ignore("integer_division")
	var minutes := remainder / _SECONDS_PER_MINUTE
	var seconds := remainder % _SECONDS_PER_MINUTE
	return "%02d:%02d:%02d" % [hours, minutes, seconds]
#endregion
