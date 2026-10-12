@tool
extends RefCounted

## 指令元数据与入参契约描述 (Command Specification)
## 包含指令唯一标识、文档描述、参数 Schema、处理器 Callable 以及参数校验。

const RpcError = preload("res://addons/godot_mcp/rpc/rpc_error.gd")

var name: String
var description: String
var parameters: Dictionary = {}  # 字段名 -> { "type": "string"|"int"|"float"|"bool"|"any", "required": bool, "default": Variant }
var handler: Callable


func _init(p_name: String, p_description: String, p_parameters: Dictionary, p_handler: Callable) -> void:
	name = p_name
	description = p_description
	parameters = p_parameters
	handler = p_handler


## 参数校验与默认值回填
## 返回格式化好的 Dictionary，若校验失败则返回 RpcError。
func validate(raw_params: Dictionary) -> Variant:
	var validated := {}

	for param_name in parameters.keys():
		var rule: Dictionary = parameters[param_name]
		var is_required: bool = rule.get("required", false)
		var has_default: bool = rule.has("default")

		if raw_params.has(param_name):
			var val = raw_params[param_name]
			if not _check_type(val, rule.get("type", "any")):
				return RpcError.invalid_params("Parameter '%s' expects type '%s', got '%s'" % [
					param_name, rule.get("type", "any"), type_string(typeof(val))
				])
			validated[param_name] = val
		elif is_required:
			return RpcError.invalid_params("Missing required parameter: '%s'" % param_name)
		elif has_default:
			validated[param_name] = rule["default"]

	# 保留用户传进来的但在 schema 之外的其他参数（宽松模式）
	for k in raw_params.keys():
		if not validated.has(k):
			validated[k] = raw_params[k]

	return validated


func _check_type(val: Variant, expected_type: String) -> bool:
	match expected_type.to_lower():
		"string": return typeof(val) == TYPE_STRING
		"int": return typeof(val) == TYPE_INT or (typeof(val) == TYPE_FLOAT and is_equal_approx(val, roundf(val)))
		"float", "number": return typeof(val) == TYPE_FLOAT or typeof(val) == TYPE_INT
		"bool": return typeof(val) == TYPE_BOOL
		"array": return typeof(val) == TYPE_ARRAY
		"dictionary", "object": return typeof(val) == TYPE_DICTIONARY
		"any", "": return true
		_: return true


## 导出为标准 JSON Schema，用于 rpc.discover
func to_schema() -> Dictionary:
	var properties := {}
	var required_list: Array[String] = []

	for param_name in parameters.keys():
		var rule: Dictionary = parameters[param_name]
		var prop := {
			"type": rule.get("type", "string"),
			"description": rule.get("description", param_name),
		}
		if rule.has("default"):
			prop["default"] = rule["default"]
		properties[param_name] = prop

		if rule.get("required", false):
			required_list.append(param_name)

	var schema := {
		"name": name,
		"description": description,
		"parameters": {
			"type": "object",
			"properties": properties,
		}
	}
	if not required_list.is_empty():
		schema["parameters"]["required"] = required_list

	return schema
