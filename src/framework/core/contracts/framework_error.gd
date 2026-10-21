class_name FrameworkError
extends RefCounted

## 标准化不可变错误抽象。
## 错误码格式统一遵循 "{Module}.{Reason}"，例如 "Scene.NotFound"、"Storage.IOError"。
## 支持附加错误分类 (category)、可重试标记 (retryable)、底层原因 (cause) 与诊断上下文 (context)。

#region Categories
const CATEGORY_GENERAL: StringName = &"general"
const CATEGORY_PARAM: StringName = &"param"
const CATEGORY_IO: StringName = &"io"
const CATEGORY_TIMEOUT: StringName = &"timeout"
const CATEGORY_CANCELLED: StringName = &"cancelled"
const CATEGORY_VALIDATION: StringName = &"validation"
const CATEGORY_MIGRATION: StringName = &"migration"
const CATEGORY_NOT_FOUND: StringName = &"not_found"
const CATEGORY_STATE: StringName = &"state"
#endregion

#region Properties
var code: String:
	get:
		return _code

var message: String:
	get:
		return _message

var module: String:
	get:
		return _module

var category: StringName:
	get:
		return _category

var retryable: bool:
	get:
		return _retryable

var cause: Variant:
	get:
		return _cause

var context: Dictionary:
	get:
		return _context

var _code: String
var _message: String
var _module: String
var _category: StringName
var _retryable: bool
var _cause: Variant
var _context: Dictionary
#endregion


func _init(
	p_code: String = "Core.Unknown",
	p_message: String = "",
	p_category: StringName = CATEGORY_GENERAL,
	p_retryable: bool = false,
	p_cause: Variant = null,
	p_context: Dictionary = {}
) -> void:
	_code = p_code if not p_code.is_empty() else "Core.Unknown"
	_message = p_message
	_module = _code.get_slice(".", 0) if _code.contains(".") else "Core"
	_category = p_category if not p_category.is_empty() else _infer_category(_code)
	_retryable = p_retryable
	_cause = p_cause
	_context = p_context.duplicate() if not p_context.is_empty() else {}


static func make(
	code: String,
	message: String = "",
	category: StringName = CATEGORY_GENERAL,
	retryable: bool = false,
	cause: Variant = null,
	context: Dictionary = {}
) -> FrameworkError:
	return FrameworkError.new(code, message, category, retryable, cause, context)


## 返回附带额外诊断上下文的新错误副本（保持不可变语义）。
func with_context(extra_context: Dictionary) -> FrameworkError:
	var merged := _context.duplicate()
	merged.merge(extra_context, true)
	return FrameworkError.new(_code, _message, _category, _retryable, _cause, merged)


## 返回附带底层原因的新错误副本（保持不可变语义）。
func with_cause(p_cause: Variant) -> FrameworkError:
	return FrameworkError.new(_code, _message, _category, _retryable, p_cause, _context)


## 返回更新了可重试属性与分类的新错误副本（保持不可变语义）。
func with_retryable(p_retryable: bool, p_category: StringName = &"") -> FrameworkError:
	var cat := p_category if not p_category.is_empty() else _category
	return FrameworkError.new(_code, _message, cat, p_retryable, _cause, _context)


## 导出结构化字典，供日志与诊断系统采集。
func to_dict() -> Dictionary:
	var out := {
		"code": _code,
		"message": _message,
		"module": _module,
		"category": String(_category),
		"retryable": _retryable,
	}
	if _cause != null:
		out["cause"] = str(_cause)
	if not _context.is_empty():
		out["context"] = _context.duplicate()
	return out


func _to_string() -> String:
	var base := "[%s] %s" % [_code, _message] if not _message.is_empty() else "[%s]" % _code
	if not _context.is_empty():
		base += " ctx=%s" % JSON.stringify(_context)
	return base


static func _infer_category(p_code: String) -> StringName:
	var lower := p_code.to_lower()
	if lower.contains("timeout"):
		return CATEGORY_TIMEOUT
	if lower.contains("cancel"):
		return CATEGORY_CANCELLED
	if lower.contains("notfound") or lower.contains("not_found") or lower.contains("missing"):
		return CATEGORY_NOT_FOUND
	if lower.contains("migrat") or lower.contains("version"):
		return CATEGORY_MIGRATION
	if lower.contains("io") or lower.contains("disk") or lower.contains("file"):
		return CATEGORY_IO
	if lower.contains("invalid") or lower.contains("empty") or lower.contains("param"):
		return CATEGORY_PARAM
	return CATEGORY_GENERAL
