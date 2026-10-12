@tool
extends "res://addons/godot_mcp/modules/base_module.gd"

## 信号连接与事件流转模块 (Signal Module)
## 负责场景节点间信号的挂接、断开与连接自省，支持 CONNECT_PERSIST 序列化落盘与撤销重做。


func register_commands(registry: CommandRegistry) -> void:
	# 1. signal.connect
	registry.register_command(
		"signal.connect",
		"Connect a signal from source node to target node's method",
		{
			"source_node": {"type": "string", "required": true, "description": "Source node path"},
			"signal_name": {"type": "string", "required": true, "description": "Name of the signal to connect (e.g. pressed, timeout)"},
			"target_node": {"type": "string", "required": true, "description": "Target node path to receive the signal"},
			"method_name": {"type": "string", "required": true, "description": "Target method name on the target node"},
			"persist": {"type": "bool", "default": true, "description": "Whether to persist connection in the scene file (CONNECT_PERSIST)"},
		},
		_connect_signal
	)
	registry.register_alias("connect_signal", "signal.connect")

	# 2. signal.disconnect
	registry.register_command(
		"signal.disconnect",
		"Disconnect a signal between source node and target node",
		{
			"source_node": {"type": "string", "required": true, "description": "Source node path"},
			"signal_name": {"type": "string", "required": true, "description": "Signal name"},
			"target_node": {"type": "string", "required": true, "description": "Target node path"},
			"method_name": {"type": "string", "required": true, "description": "Target method name"},
		},
		_disconnect_signal
	)
	registry.register_alias("disconnect_signal", "signal.disconnect")

	# 3. signal.list
	registry.register_command(
		"signal.list",
		"List all available signals and connections on a node",
		{
			"node_path": {"type": "string", "required": true, "description": "Node path to inspect"},
		},
		_list_signals
	)
	registry.register_alias("list_signals", "signal.list")


func _connect_signal(p: Dictionary) -> Variant:
	var source := ctx.resolve_node(p.source_node)
	if source == null:
		return RpcError.not_found("Source node not found: %s" % p.source_node)

	var target := ctx.resolve_node(p.target_node)
	if target == null:
		return RpcError.not_found("Target node not found: %s" % p.target_node)

	var sig_name: String = p.signal_name
	if not source.has_signal(sig_name):
		return RpcError.invalid_params("Node '%s' does not have signal '%s'" % [source.name, sig_name])

	var method_name: String = p.method_name
	var target_callable := Callable(target, method_name)

	if source.is_connected(sig_name, target_callable):
		return {"message": "Signal already connected", "source": p.source_node, "signal": sig_name, "target": p.target_node, "method": method_name}

	var flags: int = Object.CONNECT_PERSIST if p.get("persist", true) else 0

	var ur := ctx.get_undo_redo()
	if ur != null:
		ur.create_action("MCP: Connect Signal %s" % sig_name)
		ur.add_do_method(source, "connect", sig_name, target_callable, flags)
		ur.add_undo_method(source, "disconnect", sig_name, target_callable)
		ur.commit_action()
	else:
		var err := source.connect(sig_name, target_callable, flags)
		if err != OK:
			return RpcError.execution_error("Failed to connect signal, error code: %d" % err)

	ctx.mark_scene_unsaved()

	return {
		"connected": true,
		"source": p.source_node,
		"signal": sig_name,
		"target": p.target_node,
		"method": method_name,
		"persisted": (flags & Object.CONNECT_PERSIST) != 0
	}


func _disconnect_signal(p: Dictionary) -> Variant:
	var source := ctx.resolve_node(p.source_node)
	if source == null:
		return RpcError.not_found("Source node not found: %s" % p.source_node)

	var target := ctx.resolve_node(p.target_node)
	if target == null:
		return RpcError.not_found("Target node not found: %s" % p.target_node)

	var sig_name: String = p.signal_name
	var method_name: String = p.method_name
	var target_callable := Callable(target, method_name)

	if not source.is_connected(sig_name, target_callable):
		return RpcError.invalid_params("Signal '%s' is not connected to '%s.%s'" % [sig_name, target.name, method_name])

	var ur := ctx.get_undo_redo()
	if ur != null:
		ur.create_action("MCP: Disconnect Signal %s" % sig_name)
		ur.add_do_method(source, "disconnect", sig_name, target_callable)
		ur.add_undo_method(source, "connect", sig_name, target_callable, Object.CONNECT_PERSIST)
		ur.commit_action()
	else:
		source.disconnect(sig_name, target_callable)

	ctx.mark_scene_unsaved()

	return {
		"disconnected": true,
		"source": p.source_node,
		"signal": sig_name,
		"target": p.target_node,
		"method": method_name
	}


func _list_signals(p: Dictionary) -> Variant:
	var node := ctx.resolve_node(p.node_path)
	if node == null:
		return RpcError.not_found("Node not found: %s" % p.node_path)

	var declared_signals: Array[Dictionary] = []
	for sig in node.get_signal_list():
		var args_list: Array[Dictionary] = []
		for arg in sig.get("args", []):
			args_list.append({
				"name": arg.get("name", ""),
				"type": type_string(arg.get("type", 0))
			})
		declared_signals.append({
			"name": sig.get("name", ""),
			"args": args_list
		})

	var outgoing_connections: Array[Dictionary] = []
	for sig in declared_signals:
		var sname: String = sig["name"]
		for conn in node.get_signal_connection_list(sname):
			var callable_obj: Callable = conn.get("callable")
			var target_obj: Object = callable_obj.get_object()
			var target_path := ""
			if target_obj is Node:
				target_path = str(target_obj.get_path())

			outgoing_connections.append({
				"signal": sname,
				"target_node": target_path,
				"method": callable_obj.get_method(),
				"flags": conn.get("flags", 0)
			})

	return {
		"node_path": p.node_path,
		"declared_signals": declared_signals,
		"outgoing_connections": outgoing_connections
	}
