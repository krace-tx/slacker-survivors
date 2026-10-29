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

	# 6. node.instantiate_scene
	registry.register_command(
		"node.instantiate_scene",
		"Instantiate an existing .tscn or .glb PackedScene prefab as a child node",
		{
			"parent_path": {"type": "string", "default": "/root", "description": "Parent node path"},
			"scene_path": {"type": "string", "required": true, "description": "PackedScene resource path (e.g. res://.../slot_card.tscn)"},
			"node_name": {"type": "string", "default": "", "description": "Optional explicit name for the instanced node"},
		},
		_instantiate_scene
	)
	registry.register_alias("instantiate_scene", "node.instantiate_scene")

	# 7. node.set_unique_name
	registry.register_command(
		"node.set_unique_name",
		"Enable or disable scene-unique name (%NodeName) on a node",
		{
			"node_path": {"type": "string", "required": true, "description": "Target node path"},
			"enabled": {"type": "bool", "default": true, "description": "Whether unique_name_in_owner is enabled"},
		},
		_set_unique_name
	)
	registry.register_alias("set_unique_name", "node.set_unique_name")

	# 8. node.move
	registry.register_command(
		"node.move",
		"Reorder child index or reparent a node within the edited scene tree",
		{
			"node_path": {"type": "string", "required": true, "description": "Target node path"},
			"new_parent_path": {"type": "string", "default": "", "description": "Optional new parent node path"},
			"index": {"type": "int", "default": -1, "description": "Target child index (-1 keeps or appends at end)"},
		},
		_move_node
	)
	registry.register_alias("move_node", "node.move")

	# 9. node.get_tree
	registry.register_command(
		"node.get_tree",
		"Get recursive scene tree hierarchy snapshot with script, prefab, and layout info",
		{
			"root_path": {"type": "string", "default": "/root", "description": "Subtree root path"},
			"max_depth": {"type": "int", "default": 8, "description": "Maximum recursion depth"},
		},
		_get_scene_tree
	)
	registry.register_alias("get_scene_tree", "node.get_tree")


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
	var parsed_val = ctx.parse_property_value_for(node, prop_name, p.value)

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


func _instantiate_scene(p: Dictionary) -> Variant:
	var root := ctx.get_scene_root()
	if root == null:
		return RpcError.execution_error("No scene is currently being edited")

	var parent := ctx.resolve_node(p.parent_path)
	if parent == null:
		return RpcError.not_found("Parent node not found: %s" % p.parent_path)

	var scene_path: String = str(p.scene_path).strip_edges()
	if not scene_path.begins_with("res://"):
		scene_path = "res://" + scene_path
	if not ResourceLoader.exists(scene_path):
		return RpcError.not_found("PackedScene not found: %s" % scene_path)

	var packed := ResourceLoader.load(scene_path, "PackedScene") as PackedScene
	if packed == null:
		return RpcError.invalid_params("Resource is not a valid PackedScene: %s" % scene_path)

	var inst := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	if inst == null:
		return RpcError.execution_error("Failed to instantiate PackedScene: %s" % scene_path)

	var explicit_name: String = str(p.get("node_name", "")).strip_edges()
	if not explicit_name.is_empty():
		inst.name = explicit_name

	ctx.add_child_undoable(parent, inst, "MCP: Instantiate %s" % inst.name)

	return {
		"node_path": str(root.get_path_to(inst)),
		"node_name": inst.name,
		"node_type": inst.get_class(),
		"scene_path": scene_path
	}


func _set_unique_name(p: Dictionary) -> Variant:
	var root := ctx.get_scene_root()
	if root == null:
		return RpcError.execution_error("No scene is currently being edited")

	var node := ctx.resolve_node(p.node_path)
	if node == null:
		return RpcError.not_found("Node not found: %s" % p.node_path)
	if node == root:
		return RpcError.invalid_params("Scene root node cannot set unique_name_in_owner")

	var enabled: bool = bool(p.get("enabled", true))
	if node.owner == null:
		node.owner = root
	ctx.set_property_undoable(node, "unique_name_in_owner", enabled, "MCP: Unique Name %%%s" % node.name)
	return {
		"node_path": str(root.get_path_to(node)),
		"unique_name": "%" + node.name if enabled else "",
		"enabled": enabled
	}


func _move_node(p: Dictionary) -> Variant:
	var root := ctx.get_scene_root()
	if root == null:
		return RpcError.execution_error("No scene is currently being edited")

	var node := ctx.resolve_node(p.node_path)
	if node == null:
		return RpcError.not_found("Node not found: %s" % p.node_path)
	if node == root:
		return RpcError.invalid_params("Cannot move scene root node")

	var old_parent := node.get_parent()
	var new_parent_str: String = str(p.get("new_parent_path", "")).strip_edges()
	var target_parent := old_parent if new_parent_str.is_empty() else ctx.resolve_node(new_parent_str)
	if target_parent == null:
		return RpcError.not_found("Target parent not found: %s" % new_parent_str)

	var idx: int = int(p.get("index", -1))
	var ur := ctx.get_undo_redo()
	if target_parent == old_parent:
		if idx >= 0:
			var clamped_idx: int = clampi(idx, 0, maxi(0, old_parent.get_child_count() - 1))
			var old_idx: int = node.get_index()
			if ur != null:
				ur.create_action("MCP: Move %s" % node.name)
				ur.add_do_method(old_parent, "move_child", node, clamped_idx)
				ur.add_undo_method(old_parent, "move_child", node, old_idx)
				ur.commit_action()
			else:
				old_parent.move_child(node, clamped_idx)
	else:
		node.reparent(target_parent)
		node.owner = root
		if idx >= 0:
			var clamped_idx2: int = clampi(idx, 0, maxi(0, target_parent.get_child_count() - 1))
			target_parent.move_child(node, clamped_idx2)

	ctx.mark_scene_unsaved()
	return {
		"node_path": str(root.get_path_to(node)),
		"index": node.get_index()
	}


func _get_scene_tree(p: Dictionary) -> Variant:
	var root := ctx.get_scene_root()
	if root == null:
		return RpcError.execution_error("No scene is currently being edited")

	var start := ctx.resolve_node(str(p.get("root_path", "/root")))
	if start == null:
		return RpcError.not_found("Root path not found: %s" % str(p.get("root_path", "/root")))

	var max_depth: int = maxi(0, int(p.get("max_depth", 8)))
	return _serialize_subtree(root, start, 0, max_depth)


func _serialize_subtree(scene_root: Node, node: Node, depth: int, max_depth: int) -> Dictionary:
	var scr: Script = node.get_script() as Script
	var info := {
		"name": String(node.name),
		"type": node.get_class(),
		"path": "." if node == scene_root else str(scene_root.get_path_to(node)),
		"unique_name": node.unique_name_in_owner,
		"instance_path": node.scene_file_path if node != scene_root else "",
		"script_path": scr.resource_path if scr != null else "",
	}
	if node is Control:
		var ctrl: Control = node as Control
		info["visible"] = ctrl.visible
		info["rect"] = [ctrl.position.x, ctrl.position.y, ctrl.size.x, ctrl.size.y]
	elif node is Node2D:
		var n2d: Node2D = node as Node2D
		info["visible"] = n2d.visible
		info["position"] = [n2d.position.x, n2d.position.y]
	elif node is Node3D:
		var n3d: Node3D = node as Node3D
		info["visible"] = n3d.visible
		info["position"] = [n3d.position.x, n3d.position.y, n3d.position.z]

	var children: Array[Dictionary] = []
	if depth < max_depth:
		# 对于实例化的子预制体，默认只展示其实例根节点，避免内部黑盒刷屏
		var is_sub_instance: bool = (node != scene_root and not node.scene_file_path.is_empty())
		if not is_sub_instance:
			for child in node.get_children():
				children.append(_serialize_subtree(scene_root, child, depth + 1, max_depth))
	info["children"] = children
	return info
