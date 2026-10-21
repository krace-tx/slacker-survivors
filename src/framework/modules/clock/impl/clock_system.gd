class_name ClockSystem
extends BaseClockSystem

## 权威时钟系统实现。
##
## 严格区分三类时钟语义：
## 1. 单调时钟 ([method monotonic_msec] / [method monotonic_usec])：计算耗时、超时与重试间隔；
## 2. 墙上时钟 ([method system_unix_msec])：本地日期显示与日志时间戳；
## 3. 服务端校准时钟 ([method estimated_server_time_ms] / [method now_msec] / [method now])：每日重置、活动期限等跨端时间判断。
## （游戏内模拟时间流逝、暂停与倍速由 Game 层独立控制，不混入本系统；无状态时间格式化由 [TimeUtils] 负责。）

#region Module Dependency Manifest
const MODULE_ID: StringName = &"clock"
const REQUIRED_MODULES: Array[StringName] = []
const OPTIONAL_MODULES: Array[StringName] = []
#endregion

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
		return system_unix_msec()
	# ticks 从引擎启动起单调递增，改系统时钟不会让它回跳。
	return _sync_server_msec + (Time.get_ticks_msec() - _sync_tick_msec)


## 获取本地单调时钟（毫秒）。
func monotonic_msec() -> int:
	return Time.get_ticks_msec()


## 获取本地单调时钟（微秒）。
func monotonic_usec() -> int:
	return Time.get_ticks_usec()


## 获取本地操作系统墙上时钟 Unix 毫秒时间戳。
func system_unix_msec() -> int:
	return int(Time.get_unix_time_from_system() * _MS_PER_SECOND)


## 获取经服务端校准后的估算权威 Unix 毫秒时间戳。
func estimated_server_time_ms() -> int:
	return now_msec()


## 用服务器 unix 毫秒校时。之后 [method now] 与设备时钟解耦。
func sync(server_unix_msec: int) -> Result:
	if server_unix_msec <= 0:
		return Result.err_code("Clock.InvalidServerTime", "Sync failed: server time is invalid.")
	_sync_server_msec = server_unix_msec
	_sync_tick_msec = Time.get_ticks_msec()
	_synced = true
	return Result.ok()


## 是否已校时。false 时 [method now] 来自系统时钟，不可信。
func is_trusted() -> bool:
	return _synced
#endregion
