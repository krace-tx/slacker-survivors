@tool
extends RefCounted

## 标准 JSON-RPC 2.0 错误封装模型

enum Code {
	PARSE_ERROR = -32700,
	INVALID_REQUEST = -32600,
	METHOD_NOT_FOUND = -32601,
	INVALID_PARAMS = -32602,
	INTERNAL_ERROR = -32603,
	NOT_FOUND = -32001,
	EXECUTION_ERROR = -32002,
}

var code: int
var message: String
var data: Variant = null


func _init(p_code: int, p_message: String, p_data: Variant = null) -> void:
	code = p_code
	message = p_message
	data = p_data


static func parse_error(detail: String = "Parse error") -> RefCounted:
	return new(Code.PARSE_ERROR, detail)


static func invalid_request(detail: String = "Invalid Request") -> RefCounted:
	return new(Code.INVALID_REQUEST, detail)


static func method_not_found(method_name: String) -> RefCounted:
	return new(Code.METHOD_NOT_FOUND, "Method not found: %s" % method_name)


static func invalid_params(detail: String) -> RefCounted:
	return new(Code.INVALID_PARAMS, detail)


static func internal_error(detail: String) -> RefCounted:
	return new(Code.INTERNAL_ERROR, detail)


static func not_found(detail: String) -> RefCounted:
	return new(Code.NOT_FOUND, detail)


static func execution_error(detail: String) -> RefCounted:
	return new(Code.EXECUTION_ERROR, detail)


func to_dict() -> Dictionary:
	var out := {
		"code": code,
		"message": message,
	}
	if data != null:
		out["data"] = data
	return out


func to_json_rpc(id: Variant) -> Dictionary:
	return {
		"jsonrpc": "2.0",
		"id": id,
		"error": to_dict(),
	}


func to_legacy(command_id: String) -> Dictionary:
	var out := {
		"status": "error",
		"message": message,
	}
	if not command_id.is_empty():
		out["commandId"] = command_id
	return out
