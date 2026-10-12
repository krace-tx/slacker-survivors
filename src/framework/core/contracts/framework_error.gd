class_name FrameworkError
extends RefCounted

## 标准化不可变错误抽象。
## 错误码格式统一遵循 "{Module}.{Reason}"，例如 "Scene.NotFound"、"Persist.IOError"。

var code: String:
	get:
		return _code

var message: String:
	get:
		return _message

var _code: String
var _message: String


func _init(p_code: String = "Core.Unknown", p_message: String = "") -> void:
	_code = p_code
	_message = p_message


static func make(code: String, message: String = "") -> FrameworkError:
	return FrameworkError.new(code, message)


func _to_string() -> String:
	return "[%s] %s" % [code, message] if not message.is_empty() else "[%s]" % code
