@tool
extends "res://addons/godot_mcp/modules/base_module.gd"

## 场景节点操作模块 (Node Module)
## 涵盖节点增删改查，全部支持编辑器撤销/重做 (Ctrl+Z) 记录。


func register_commands(registry: CommandRegistry) -> void:
	# 1. node.create
	registry.register_command(
		"node.create",
		"Create a new node in the currently edited scene tree",
		{
			"parent_path": {"type": "string", "default": "/root", "description": "Parent node path (e.g. /root, /root/Main)"},
			"node_type": {"type": "string", "required": true, "description": "Node class name (e.g. Sprite2D, Node2D, Label)"},
			"node_name": {"type": "string", "default": "NewNode", "description": "Name for the new node"},
		},
		_create_node
	)
	registry.register_alias("create_node", "node.create")

	# 2. node.delete
	registry.register_command(
		"node.delete",
		"Delete a node from the scene tree",
		{
			"node_path": {"type": "string", "required": true, "description": "Path to the node to delete"},
		},
		_delete_node
	)
	registry.register_alias("delete_node", "node.delete")

	# 3. node.update_property
	registry.register_command(
		"node.update_property",
		"Update a property of a node in the scene tree",
		{
			"node_path": {"type": "string", "required": true, "description": "Path to the target node"},
			"property": {"type": "string", "required": true, "description": "Property name (e.g. position, text, modulate)"},
			"value": {"type": "any", "required": true, "description": "New property value"},
		},
		_update_property
	)
	registry.register_alias("update_node_property", "node.update_property")

	# 4. node.get_properties
	registry.register_command(
		"node.get_properties",
		"Get all exported and script properties of a node",
		{
			"node_path": {"type": "string", "required": true, "description": "Path to the target node"},
		},
		_get_properties
	)
	registry.register_alias("get_node_properties", "node.get_properties")

	# 5. node.list
	registry.register_command(
		"node.list",
		"List child nodes under a parent node in the scene tree",
		{
			"parent_path": {"type": "string", "default": "/root", "description": "Parent node path"},
		},
		_list_nodes
	)
	registry.register_alias("list_nodes", "node.list")


func _create_node(p: Dictionary) -> Variant:
	var root := ctx.get_scene_root()
	if root == null:
		return RpcError.execution_error("No scene is currently being edited")

	var parent := ctx.resolve_node(p.parent_path)
	if parent == null:
		return RpcError.not_found("Parent node not found: %s" % p.parent_path)

	var node_type: String = p.node_type
	if not ClassDB.can_instantiate(node_type):
		return RpcError.invalid_params("Cannot instantiate node of type: %s" % node_type)

	var node: Node = ClassDB.instantiate(node_type)
	if node == null:
		return RpcError.execution_error("Failed to create node of type: %s" % node_type)

	node.name = p.node_name
	ctx.add_child_undoable(parent, node, "MCP: Create %s" % node.name)

	return {
		"node_path": str(root.get_path_to(node)),
		"node_name": node.name,
		"node_type": node_type
	}


func _delete_node(p: Dictionary) -> Variant:
	var root := ctx.get_scene_root()
	if root == null:
		return RpcError.execution_error("No scene is currently being edited")

	var node := ctx.resolve_node(p.node_path)
	if node == null:
		return RpcError.not_found("Node not found: %s" % p.node_path)

	if node == root:
		return RpcError.execution_error("Cannot delete the root node of the scene")

	ctx.remove_node_undoable(node, "MCP: Delete %s" % node.name)
	return {"deleted_path": p.node_path}


func _update_property(p: Dictionary) -> Variant:
	var node := ctx.resolve_node(p.node_path)
	if node == null:
		return RpcError.not_found("Node not found: %s" % p.node_path)

	var prop_name: String = p.property
	var parsed_val = ctx.parse_property_value(p.value)

	ctx.set_property_undoable(node, prop_name, parsed_val, "MCP: Set %s.%s" % [node.name, prop_name])
	return {
		"node_path": p.node_path,
		"property": prop_name,
		"value": parsed_val
	}


func _get_properties(p: Dictionary) -> Variant:
	var node := ctx.resolve_node(p.node_path)
	if node == null:
		return RpcError.not_found("Node not found: %s" % p.node_path)

	var properties := {}
	for prop in node.get_property_list():
		var name: String = prop.name
		# 过滤内置无用内部标识
		if name.begins_with("metadata/") or name.begins_with("_"):
			continue
		properties[name] = node.get(name)

	return {
		"node_path": p.node_path,
		"node_type": node.get_class(),
		"properties": properties
	}


func _list_nodes(p: Dictionary) -> Variant:
	var parent := ctx.resolve_node(p.parent_path)
	if parent == null:
		return RpcError.not_found("Parent node not found: %s" % p.parent_path)

	var children_list: Array[Dictionary] = []
	for child in parent.get_children():
		children_list.append({
			"name": child.name,
			"type": child.get_class(),
			"path": str(parent.get_path_to(child))
		})

	return {
		"parent_path": p.parent_path,
		"children": children_list
	}
