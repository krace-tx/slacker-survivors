@tool
extends RefCounted

## 指令统一注册表 (Command Registry)
## 集中管理系统内暴露的所有可调指令规范，并提供自省发现能力 (rpc.discover)。

const CommandSpec = preload("res://addons/godot_mcp/registry/command_spec.gd")

var _specs: Dictionary = {}  # name -> CommandSpec
var _primary_names: Array[String] = []  # 记录主方法名，避免 rpc.discover 产生别名重复


func register(spec: RefCounted) -> void:
	_specs[spec.name] = spec
	if not _primary_names.has(spec.name):
		_primary_names.append(spec.name)


func register_command(name: String, description: String, parameters: Dictionary, handler: Callable) -> RefCounted:
	var spec := CommandSpec.new(name, description, parameters, handler)
	register(spec)
	return spec


func register_alias(alias_name: String, target_command_name: String) -> void:
	if _specs.has(target_command_name):
		_specs[alias_name] = _specs[target_command_name]


func find(name: String) -> RefCounted:
	return _specs.get(name, null)


func has_command(name: String) -> bool:
	return _specs.has(name)


## rpc.discover 实现：供外部客户端自省全部可用工具清单与 Schema
func discover() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for name in _primary_names:
		var spec: CommandSpec = _specs.get(name)
		if spec != null:
			out.append(spec.to_schema())
	return out
