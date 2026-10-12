@tool
extends RefCounted

## 统一分发路由器 (RPC Dispatcher)
## 解析输入报文，双模支持标准 JSON-RPC 2.0 及历史 Legacy 命令格式。
## 参数自动校验、异步协程 (await) 处理，以及统一响应回包。

const RpcError = preload("res://addons/godot_mcp/rpc/rpc_error.gd")
const CommandRegistry = preload("res://addons/godot_mcp/registry/command_registry.gd")

var _registry: CommandRegistry
var _transport: RefCounted  # WSTransport


func _init(registry: CommandRegistry, transport: RefCounted) -> void:
	_registry = registry
	_transport = transport


func dispatch(client_id: int, text: String) -> void:
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		_send_raw(client_id, RpcError.parse_error("Failed to parse JSON: %s" % json.get_error_message()).to_json_rpc(null))
		return

	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		_send_raw(client_id, RpcError.invalid_request("Payload must be a JSON object").to_json_rpc(null))
		return

	var req: Dictionary = data

	# 1. 协议检测：判断是否为标准 JSON-RPC 2.0
	if req.has("method"):
		_handle_json_rpc(client_id, req)
	# 2. 协议检测：判断是否为 Legacy 指令格式 {"type": ..., "params": ..., "commandId": ...}
	elif req.has("type"):
		_handle_legacy(client_id, req)
	else:
		_send_raw(client_id, RpcError.invalid_request("Missing 'method' or 'type' field").to_json_rpc(req.get("id")))


func _handle_json_rpc(client_id: int, req: Dictionary) -> void:
	var method_name: String = req.get("method", "")
	var id: Variant = req.get("id", null)
	var raw_params: Dictionary = req.get("params", {})

	# 内置快捷支持 rpc.discover
	if method_name == "rpc.discover":
		var discovery := _registry.discover()
		_send_raw(client_id, {"jsonrpc": "2.0", "id": id, "result": discovery})
		return

	var spec = _registry.find(method_name)
	if spec == null:
		_send_raw(client_id, RpcError.method_not_found(method_name).to_json_rpc(id))
		return

	var validated = spec.validate(raw_params)
	if validated is RpcError:
		_send_raw(client_id, validated.to_json_rpc(id))
		return

	var result = await _call_handler(spec.handler, validated)

	if result is RpcError:
		_send_raw(client_id, result.to_json_rpc(id))
	else:
		_send_raw(client_id, {"jsonrpc": "2.0", "id": id, "result": result if result != null else {}})


func _handle_legacy(client_id: int, req: Dictionary) -> void:
	var cmd_type: String = req.get("type", "")
	var cmd_id: String = req.get("commandId", "")
	var raw_params: Dictionary = req.get("params", {})

	if cmd_type == "discover" or cmd_type == "rpc.discover":
		var discovery := _registry.discover()
		_send_raw(client_id, {"status": "success", "result": {"commands": discovery}, "commandId": cmd_id})
		return

	var spec = _registry.find(cmd_type)
	if spec == null:
		_send_raw(client_id, RpcError.method_not_found(cmd_type).to_legacy(cmd_id))
		return

	var validated = spec.validate(raw_params)
	if validated is RpcError:
		_send_raw(client_id, validated.to_legacy(cmd_id))
		return

	var result = await _call_handler(spec.handler, validated)

	if result is RpcError:
		_send_raw(client_id, result.to_legacy(cmd_id))
	else:
		var response := {
			"status": "success",
			"result": result if result != null else {}
		}
		if not cmd_id.is_empty():
			response["commandId"] = cmd_id
		_send_raw(client_id, response)


func _call_handler(handler: Callable, params: Dictionary) -> Variant:
	if not handler.is_valid():
		return RpcError.internal_error("Handler is invalid")
	return await handler.call(params)


func _send_raw(client_id: int, dict: Dictionary) -> void:
	var text := JSON.stringify(dict)
	_transport.send_text(client_id, text)
