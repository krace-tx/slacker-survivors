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

	# 3. ui.set_theme_override
	registry.register_command(
		"ui.set_theme_override",
		"Set Control theme override (constant, color, font_size, or stylebox from res:// / StyleBoxFlat dict)",
		{
			"node_path": {"type": "string", "required": true, "description": "Target Control node path"},
			"override_type": {"type": "string", "required": true, "description": "Override category: constant | color | font_size | stylebox"},
			"name": {"type": "string", "required": true, "description": "Theme item name (e.g. separation, margin_left, font_color, panel)"},
			"value": {"type": "any", "required": true, "description": "Override value (int, #hex/{r,g,b,a}, res://...tres, or StyleBoxFlat dict)"},
		},
		_set_theme_override
	)
	registry.register_alias("set_theme_override", "ui.set_theme_override")


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


func _set_theme_override(p: Dictionary) -> Variant:
	var node := ctx.resolve_node(p.node_path)
	if node == null:
		return RpcError.not_found("Node not found: %s" % p.node_path)
	if not node is Control:
		return RpcError.invalid_params("Node '%s' is not a Control node" % p.node_path)

	var category: String = str(p.override_type).to_lower().strip_edges()
	var item_name: String = str(p.name).strip_edges()
	var raw_val: Variant = p.value

	var prop_path := ""
	var parsed: Variant = null

	match category:
		"constant", "constants":
			prop_path = "theme_override_constants/%s" % item_name
			parsed = int(raw_val)
		"font_size", "font_sizes":
			prop_path = "theme_override_font_sizes/%s" % item_name
			parsed = int(raw_val)
		"color", "colors":
			prop_path = "theme_override_colors/%s" % item_name
			parsed = _parse_color(raw_val)
		"stylebox", "styles":
			prop_path = "theme_override_styles/%s" % item_name
			parsed = _parse_stylebox(raw_val)
			if parsed == null and raw_val != null:
				return RpcError.invalid_params("Invalid stylebox value for '%s'" % item_name)
		_:
			return RpcError.invalid_params("Unknown override_type '%s'. Expected constant, color, font_size, or stylebox" % category)

	ctx.set_property_undoable(node, prop_path, parsed, "MCP: Theme %s/%s" % [category, item_name])
	return {
		"node_path": p.node_path,
		"property": prop_path
	}


func _parse_color(val: Variant) -> Color:
	if val is Color:
		return val
	if typeof(val) == TYPE_STRING:
		var s := String(val).strip_edges()
		if Color.html_is_valid(s):
			return Color.html(s)
		var parsed := ctx.parse_property_value(s)
		if parsed is Color:
			return parsed
	elif typeof(val) == TYPE_DICTIONARY:
		var parsed_d := ctx.parse_property_value(val)
		if parsed_d is Color:
			return parsed_d
	return Color.WHITE


func _parse_stylebox(val: Variant) -> StyleBox:
	if val == null:
		return null
	if val is StyleBox:
		return val
	if typeof(val) == TYPE_STRING:
		var spath := String(val).strip_edges()
		if spath.is_empty():
			return null
		if spath == "empty":
			return StyleBoxEmpty.new()
		if not spath.begins_with("res://"):
			spath = "res://" + spath
		return ResourceLoader.load(spath) as StyleBox
	if typeof(val) == TYPE_DICTIONARY:
		var d: Dictionary = val
		var sb_type: String = str(d.get("type", "StyleBoxFlat")).strip_edges()
		if sb_type == "StyleBoxEmpty":
			return StyleBoxEmpty.new()
		var sb := StyleBoxFlat.new()
		if d.has("bg_color"):
			sb.bg_color = _parse_color(d["bg_color"])
		if d.has("border_color"):
			sb.border_color = _parse_color(d["border_color"])
		if d.has("border_width"):
			sb.set_border_width_all(int(d["border_width"]))
		if d.has("corner_radius"):
			sb.set_corner_radius_all(int(d["corner_radius"]))
		if d.has("content_margin"):
			var cm: Variant = d["content_margin"]
			if typeof(cm) == TYPE_ARRAY and (cm as Array).size() == 4:
				var arr: Array = cm
				sb.content_margin_left = float(arr[0])
				sb.content_margin_top = float(arr[1])
				sb.content_margin_right = float(arr[2])
				sb.content_margin_bottom = float(arr[3])
			else:
				sb.set_content_margin_all(float(cm))
		for k in d.keys():
			var ks := String(k)
			if ks in ["type", "bg_color", "border_color", "border_width", "corner_radius", "content_margin"]:
				continue
			if ks.ends_with("_color"):
				sb.set(ks, _parse_color(d[k]))
			else:
				sb.set(ks, ctx.parse_property_value_for(sb, ks, d[k]))
		return sb
	return null
