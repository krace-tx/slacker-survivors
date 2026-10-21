class_name Result
extends RefCounted

## 可失败操作的统一返回类型（对标 Unity Framework 的 Result / Result<T>）。
## 强制调用方显式处理成功与失败分支，避免错误被静默吞没。

#region Exports & State
var _ok: bool = false
var value: Variant:
	get:
		return _value
var error: Variant:
	get:
		return _error

var _value: Variant = null   ## 成功时的负载；失败时为 null
var _error: Variant = null   ## 失败时的原因（兼容字符串或驱动字典）；成功时为 null
#endregion

#region Public API - Constructors
## 构造一个成功结果，可携带负载 [param p_value]。
static func ok(p_value: Variant = null) -> Result:
	var r := Result.new()
	r._ok = true
	r._value = p_value
	return r


## 构造一个失败结果。
## 若传入 [FrameworkError]，直接作为 error。
## 若同时提供 [param p_error] (作为 code) 和 [param p_message]，构造 [FrameworkError]。
## 若只传入字符串或驱动字典，保持现有兼容行为。
static func err(p_error: Variant = "", p_message: String = "") -> Result:
	var r := Result.new()
	r._ok = false
	if p_error is FrameworkError:
		r._error = p_error
	elif not p_message.is_empty() and p_error is String:
		r._error = FrameworkError.new(p_error, p_message)
	else:
		r._error = p_error
	return r


## 按强类型错误码构造失败结果：{Module}.{Reason}。
static func err_code(code: String, message: String = "") -> Result:
	var r := Result.new()
	r._ok = false
	r._error = FrameworkError.new(code, message)
	return r


## 构造携带完整上下文、可重试标记与底层原因的标准化失败结果。
static func err_ex(
	code: String,
	message: String = "",
	context: Dictionary = {},
	retryable: bool = false,
	cause: Variant = null,
	category: StringName = &""
) -> Result:
	var r := Result.new()
	r._ok = false
	r._error = FrameworkError.new(code, message, category, retryable, cause, context)
	return r
#endregion

#region Public API - Query & Unpack
## 是否为成功结果。
func is_ok() -> bool:
	return _ok


## 是否为失败结果。
func is_err() -> bool:
	return not _ok


## 获取标准化错误码。若 error 为 FrameworkError 则返回 code，否则为 "Core.Unknown"。
func error_code() -> String:
	if error is FrameworkError:
		return (error as FrameworkError).code
	return "Core.Unknown"


## 获取错误描述信息。
func error_message() -> String:
	if error is FrameworkError:
		return (error as FrameworkError).message
	return str(error)


## 获取错误所属模块名（如 "Scene"、"Storage"）。
func error_module() -> String:
	if error is FrameworkError:
		return (error as FrameworkError).module
	return "Core"


## 该失败结果是否建议调用方重试。
func is_retryable() -> bool:
	if error is FrameworkError:
		return (error as FrameworkError).retryable
	return false


## 获取失败时附带的诊断上下文字典。
func error_context() -> Dictionary:
	if error is FrameworkError:
		return (error as FrameworkError).context
	return {}


## 成功时返回负载，失败时返回 [param default]，不触发错误。
func value_or(default: Variant) -> Variant:
	return value if _ok else default
#endregion

#region Internal
func _to_string() -> String:
	return "Result.ok(%s)" % str(value) if _ok else "Result.err(%s)" % str(error)
#endregion
