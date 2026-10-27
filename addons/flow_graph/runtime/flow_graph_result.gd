@tool
class_name FlowGraphResult
extends RefCounted

## FlowGraph 插件独立结果契约（Zero-Dependency Compile & Validation Result）。[br]
##
## 确保 `addons/flow_graph/` 拷入任何空白 Godot 4 工程时完全零外部依赖，同时提供显式的 `is_ok()` / `is_err()` / `error_code()` / `error_message()` 强类型错误处理接口。

#region 状态字段

var value: Variant:
	get:
		return _value

var _ok: bool = false
var _value: Variant = null
var _code: String = ""
var _message: String = ""

#endregion


#region 静态构造与查询接口

static func ok(p_value: Variant = null) -> FlowGraphResult:
	var r := FlowGraphResult.new()
	r._ok = true
	r._value = p_value
	return r


static func err_code(code: String, message: String = "") -> FlowGraphResult:
	var r := FlowGraphResult.new()
	r._ok = false
	r._code = code
	r._message = message
	return r


func is_ok() -> bool:
	return _ok


func is_err() -> bool:
	return not _ok


func error_code() -> String:
	return _code if not _code.is_empty() else "FlowGraph.Unknown"


func error_message() -> String:
	return _message


func value_or(default_val: Variant) -> Variant:
	return _value if _ok else default_val


func _to_string() -> String:
	if _ok:
		return "FlowGraphResult.ok(%s)" % str(_value)
	return "FlowGraphResult.err(%s: %s)" % [_code, _message]

#endregion
