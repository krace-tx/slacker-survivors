@tool
extends "res://addons/godot_mcp/modules/base_module.gd"

## UI 快捷布局与容器编排模块 (UI Module)
## 针对 Control 节点提供锚点预设 (Anchor Presets) 与尺寸标志 (Size Flags) 的快捷配置，全面接入撤销重做。

const PRESET_MAP := {
	"top_left": Control.PRESET_TOP_LEFT,
	"top_right": Control.PRESET_TOP_RIGHT,
	"bottom_left": Control.PRESET_BOTTOM_LEFT,
	"bottom_right": Control.PRESET_BOTTOM_RIGHT,
	"center_left": Control.PRESET_CENTER_LEFT,
	"center_top": Control.PRESET_CENTER_TOP,
	"center_right": Control.PRESET_CENTER_RIGHT,
	"center_bottom": Control.PRESET_CENTER_BOTTOM,
	"center": Control.PRESET_CENTER,
	"left_wide": Control.PRESET_LEFT_WIDE,
	"top_wide": Control.PRESET_TOP_WIDE,
	"right_wide": Control.PRESET_RIGHT_WIDE,
	"bottom_wide": Control.PRESET_BOTTOM_WIDE,
	"vcenter_wide": Control.PRESET_VCENTER_WIDE,
	"hcenter_wide": Control.PRESET_HCENTER_WIDE,
	"full_rect": Control.PRESET_FULL_RECT,
}

const SIZE_FLAG_MAP := {
	"shrink_begin": Control.SIZE_SHRINK_BEGIN,
	"fill": Control.SIZE_FILL,
	"expand": Control.SIZE_EXPAND,
	"expand_fill": Control.SIZE_EXPAND_FILL,
	"shrink_center": Control.SIZE_SHRINK_CENTER,
	"shrink_end": Control.SIZE_SHRINK_END,
}


func register_commands(registry: CommandRegistry) -> void:
	# 1. ui.set_anchor_preset
	registry.register_command(
		"ui.set_anchor_preset",
		"Set Control node anchor layout preset (e.g. full_rect, center, top_wide)",
		{
			"node_path": {"type": "string", "required": true, "description": "Target Control node path"},
			"preset": {"type": "string", "required": true, "description": "Preset name (full_rect, center, top_wide, bottom_wide, top_left, etc.)"},
			"keep_offsets": {"type": "bool", "default": false, "description": "Whether to preserve current offsets"},
		},
		_set_anchor_preset
	)
	registry.register_alias("set_anchor_preset", "ui.set_anchor_preset")

	# 2. ui.set_size_flags
	registry.register_command(
		"ui.set_size_flags",
		"Set container size flags for Control node (horizontal/vertical)",
		{
			"node_path": {"type": "string", "required": true, "description": "Target Control node path"},
			"horizontal": {"type": "string", "default": "", "description": "Horizontal flag (fill, expand, expand_fill, shrink_center)"},
			"vertical": {"type": "string", "default": "", "description": "Vertical flag (fill, expand, expand_fill, shrink_center)"},
		},
		_set_size_flags
	)
	registry.register_alias("set_size_flags", "ui.set_size_flags")


func _set_anchor_preset(p: Dictionary) -> Variant:
	var node := ctx.resolve_node(p.node_path)
	if node == null:
		return RpcError.not_found("Node not found: %s" % p.node_path)

	if not node is Control:
		return RpcError.invalid_params("Node '%s' is not a Control node" % p.node_path)

	var control: Control = node
	var preset_str: String = str(p.preset).to_lower().strip_edges()
	var preset_val = PRESET_MAP.get(preset_str)
	if preset_val == null and preset_str.is_valid_int():
		preset_val = preset_str.to_int()

	if preset_val == null or preset_val < 0 or preset_val > Control.PRESET_FULL_RECT:
		return RpcError.invalid_params("Unknown anchor preset: '%s'. Valid options: %s" % [p.preset, str(PRESET_MAP.keys())])

	var keep_offsets: bool = p.get("keep_offsets", false)

	var ur := ctx.get_undo_redo()
	if ur != null:
		ur.create_action("MCP: Set Anchor Preset %s" % preset_str)
		ur.add_do_method(control, "set_anchors_preset", preset_val, keep_offsets)
		ur.add_undo_property(control, "anchor_left", control.anchor_left)
		ur.add_undo_property(control, "anchor_top", control.anchor_top)
		ur.add_undo_property(control, "anchor_right", control.anchor_right)
		ur.add_undo_property(control, "anchor_bottom", control.anchor_bottom)
		ur.add_undo_property(control, "offset_left", control.offset_left)
		ur.add_undo_property(control, "offset_top", control.offset_top)
		ur.add_undo_property(control, "offset_right", control.offset_right)
		ur.add_undo_property(control, "offset_bottom", control.offset_bottom)
		ur.commit_action()
	else:
		control.set_anchors_preset(preset_val, keep_offsets)

	ctx.mark_scene_unsaved()

	return {
		"node_path": p.node_path,
		"preset": preset_str,
		"applied_preset_id": preset_val
	}


func _set_size_flags(p: Dictionary) -> Variant:
	var node := ctx.resolve_node(p.node_path)
	if node == null:
		return RpcError.not_found("Node not found: %s" % p.node_path)

	if not node is Control:
		return RpcError.invalid_params("Node '%s' is not a Control node" % p.node_path)

	var control: Control = node
	var h_str: String = p.get("horizontal", "").to_lower().strip_edges()
	var v_str: String = p.get("vertical", "").to_lower().strip_edges()

	var ur := ctx.get_undo_redo()
	if ur != null:
		ur.create_action("MCP: Set Size Flags for %s" % control.name)
		if not h_str.is_empty() and SIZE_FLAG_MAP.has(h_str):
			ur.add_do_property(control, "size_flags_horizontal", SIZE_FLAG_MAP[h_str])
			ur.add_undo_property(control, "size_flags_horizontal", control.size_flags_horizontal)
		if not v_str.is_empty() and SIZE_FLAG_MAP.has(v_str):
			ur.add_do_property(control, "size_flags_vertical", SIZE_FLAG_MAP[v_str])
			ur.add_undo_property(control, "size_flags_vertical", control.size_flags_vertical)
		ur.commit_action()
	else:
		if not h_str.is_empty() and SIZE_FLAG_MAP.has(h_str):
			control.size_flags_horizontal = SIZE_FLAG_MAP[h_str]
		if not v_str.is_empty() and SIZE_FLAG_MAP.has(v_str):
			control.size_flags_vertical = SIZE_FLAG_MAP[v_str]

	ctx.mark_scene_unsaved()

	return {
		"node_path": p.node_path,
		"horizontal": h_str,
		"vertical": v_str
	}
