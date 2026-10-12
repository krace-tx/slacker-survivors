@tool
extends EditorPlugin

## Godot MCP 主插件入口 (EditorPlugin Orchestrator)
## 负责装配网络传输、编辑器上下文、指令注册表与分发路由器。

const WSTransport = preload("res://addons/godot_mcp/transport/ws_transport.gd")
const EditorContext = preload("res://addons/godot_mcp/editor/editor_context.gd")
const CommandRegistry = preload("res://addons/godot_mcp/registry/command_registry.gd")
const RPCDispatcher = preload("res://addons/godot_mcp/rpc/rpc_dispatcher.gd")

const NodeModule = preload("res://addons/godot_mcp/modules/node_module.gd")
const SceneModule = preload("res://addons/godot_mcp/modules/scene_module.gd")
const ScriptModule = preload("res://addons/godot_mcp/modules/script_module.gd")
const ProjectModule = preload("res://addons/godot_mcp/modules/project_module.gd")
const EditorModule = preload("res://addons/godot_mcp/modules/editor_module.gd")
const SignalModule = preload("res://addons/godot_mcp/modules/signal_module.gd")
const ViewportModule = preload("res://addons/godot_mcp/modules/viewport_module.gd")
const GameModule = preload("res://addons/godot_mcp/modules/game_module.gd")
const UIModule = preload("res://addons/godot_mcp/modules/ui_module.gd")

var _transport: RefCounted
var _context: RefCounted
var _registry: RefCounted
var _dispatcher: RefCounted
var _modules: Array = []


func _enter_tree() -> void:
	print("\n=== GODOT MCP INITIALIZING (MODULAR ARCHITECTURE) ===")

	_context = EditorContext.new(self)
	_registry = CommandRegistry.new()
	_transport = WSTransport.new()
	_dispatcher = RPCDispatcher.new(_registry, _transport)

	# 装配各自治业务模块
	_modules = [
		NodeModule.new(_context),
		SceneModule.new(_context),
		ScriptModule.new(_context),
		ProjectModule.new(_context),
		EditorModule.new(_context),
		SignalModule.new(_context),
		ViewportModule.new(_context),
		GameModule.new(_context),
		UIModule.new(_context),
	]
	for m in _modules:
		m.register_commands(_registry)

	# 连接传输层信号
	_transport.message_received.connect(_on_message_received)

	# 启动网络传输监听 (严格限定 127.0.0.1:9080)
	var err: Error = _transport.start(9080, "127.0.0.1")
	if err == OK:
		set_process(true)
		print("=== GODOT MCP INITIALIZED & READY ===\n")
	else:
		printerr("=== GODOT MCP START FAILED: %d ===\n" % err)


func _exit_tree() -> void:
	set_process(false)
	if _transport != null:
		_transport.stop()
	_modules.clear()
	print("=== GODOT MCP SHUTDOWN ===")


func _process(_delta: float) -> void:
	if _transport != null:
		_transport.poll()


func _on_message_received(client_id: int, message: String) -> void:
	if _dispatcher != null:
		_dispatcher.dispatch(client_id, message)
