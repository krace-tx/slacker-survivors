class_name CancellationToken
extends RefCounted

## 异步任务取消令牌（Cancellation Token）。[br]
##
## 用于向正在执行的异步操作传递协作式取消信号，支持：[br]
## - 主动轮询检查（[method is_cancelled] / [method check]）；[br]
## - 响应式信号订阅（[signal cancelled]）；[br]
## - 记录取消原因（[method get_reason]）。[br]
## 纯 RefCounted 实现，不依赖具体业务模块。

## 当令牌被触发取消时广播（仅触发一次）。
signal cancelled(reason: String)

#region State
var _cancelled: bool = false
var _reason: String = ""
#endregion

#region Public API
## 当前令牌是否已被取消。
func is_cancelled() -> bool:
	return _cancelled


## 获取取消原因字符串（未取消时为空字符串）。
func get_reason() -> String:
	return _reason


## 触发取消（幂等操作：重复调用不会重复触发信号或覆盖首次原因）。
func cancel(reason: String = "Operation cancelled.") -> void:
	if _cancelled:
		return
	_cancelled = true
	_reason = reason if not reason.is_empty() else "Operation cancelled."
	cancelled.emit(_reason)


## 检查令牌状态：若已取消则返回标准化 `Async.Cancelled` 错误结果，否则返回 `Result.ok()`。
func check() -> Result:
	if _cancelled:
		return Result.err_code(
			"Async.Cancelled",
			_reason,
		)
	return Result.ok()
#endregion
