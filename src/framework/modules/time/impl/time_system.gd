class_name TimeSystem
extends BaseTimeSystem

## 权威时间系统。
##
## 每日重置、广告冷却、活动倒计时用 [method now]，不要读系统时钟（改设备时间是常见作弊）。
## 已校时：服务器时间 + 本地单调 tick。未校时：退化为系统时钟，[method is_trusted] 为 false。
## 业务层自己取服务器 unix 毫秒，再交给 [method sync]。

#region Constants & Enums
const _MS_PER_SECOND: int = 1000
#endregion

#region State
var _synced: bool = false
var _sync_server_msec: int = 0
var _sync_tick_msec: int = 0
#endregion

#region Lifecycle
func initialize() -> Result:
	return Result.ok()
#endregion

#region Public API
## 当前 unix 时间（秒）。未校时时来自系统时钟，不可信。
func now() -> int:
	@warning_ignore("integer_division")
	return now_msec() / _MS_PER_SECOND


## 当前 unix 时间（毫秒）。
func now_msec() -> int:
	if not _synced:
		return int(Time.get_unix_time_from_system() * _MS_PER_SECOND)
	# ticks 从引擎启动起单调递增，改系统时钟不会让它回跳。
	return _sync_server_msec + (Time.get_ticks_msec() - _sync_tick_msec)


## 用服务器 unix 毫秒校时。之后 [method now] 与设备时钟解耦。
func sync(server_unix_msec: int) -> Result:
	if server_unix_msec <= 0:
		return Result.err("Sync failed: server time is invalid.")
	_sync_server_msec = server_unix_msec
	_sync_tick_msec = Time.get_ticks_msec()
	_synced = true
	return Result.ok()


## 是否已校时。false 时 [method now] 来自系统时钟，不可信。
func is_trusted() -> bool:
	return _synced
#endregion
