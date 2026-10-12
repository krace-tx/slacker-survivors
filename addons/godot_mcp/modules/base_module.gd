@tool
extends RefCounted

## 指令模块基类 (Base Command Module)
## 仅关注业务逻辑，通过 EditorContext 访问引擎与编辑器状态，完全解耦网络传输层。

const EditorContext = preload("res://addons/godot_mcp/editor/editor_context.gd")
const CommandRegistry = preload("res://addons/godot_mcp/registry/command_registry.gd")
const RpcError = preload("res://addons/godot_mcp/rpc/rpc_error.gd")

var ctx: EditorContext


func _init(p_ctx: EditorContext) -> void:
	ctx = p_ctx


## 子类重写以注册领域指令
func register_commands(_registry: CommandRegistry) -> void:
	pass
