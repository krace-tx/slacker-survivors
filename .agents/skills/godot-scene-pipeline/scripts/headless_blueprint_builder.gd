extends SceneTree
## Headless 确定性场景蓝图构建器 (Offline Fallback Builder)
##
## 当 Godot Editor 未启动（Godot MCP 9080 端口离线）时，由 `mcp_scene_cli.py apply` 自动降级调用。
## 全程调用引擎 C++ `PackedScene.pack()` 与 `ResourceSaver.save()` 原生序列化 `.tscn`，
## 与在线 Godot MCP 共享 100% 相同的 JSON Blueprint 契约，彻底杜绝脆弱的手写 `.tscn` 文本。

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


func _initialize() -> void:
	if root != null:
		var app_node := root.get_node_or_null("App")
		if app_node != null:
			app_node.set("_boot_done", true)

	var bp_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--blueprint="):
			bp_path = arg.trim_prefix("--blueprint=").strip_edges()

	if bp_path.is_empty() or not FileAccess.file_exists(bp_path):
		printerr("[BLUEPRINT_FAIL] Missing or non-existent --blueprint=<path>: %s" % bp_path)
		quit(1)
		return

	var raw_json := FileAccess.get_file_as_string(bp_path)
	var parsed: Variant = JSON.parse_string(raw_json)
	if typeof(parsed) != TYPE_DICTIONARY:
		printerr("[BLUEPRINT_FAIL] Invalid JSON object in %s" % bp_path)
		quit(1)
		return

	var bp: Dictionary = parsed
	var err_msg := _build_and_save(bp)
	if not err_msg.is_empty():
		printerr("[BLUEPRINT_FAIL] %s" % err_msg)
		quit(1)
		return

	print("[BLUEPRINT_OK] %s" % String(bp.get("scene_path", "")))
	quit(0)


func _build_and_save(bp: Dictionary) -> String:
	var scene_path := String(bp.get("scene_path", "")).strip_edges()
	if scene_path.is_empty():
		return "scene_path is required"
	if not scene_path.begins_with("res://"):
		scene_path = "res://" + scene_path
	if not scene_path.ends_with(".tscn"):
		scene_path += ".tscn"

	var base_scene_path := String(bp.get("base_scene_path", "")).strip_edges()
	var root_spec: Dictionary = bp.get("root", {})
	var scene_root: Node = null

	if not base_scene_path.is_empty():
		if not base_scene_path.begins_with("res://"):
			base_scene_path = "res://" + base_scene_path
		var base_packed := ResourceLoader.load(base_scene_path, "PackedScene") as PackedScene
		if base_packed == null:
			return "Base scene not found: %s" % base_scene_path
		scene_root = base_packed.instantiate(PackedScene.GEN_EDIT_STATE_MAIN_INHERITED)
	else:
		var root_type := String(root_spec.get("type", "Node")).strip_edges()
		if not ClassDB.can_instantiate(root_type):
			return "Cannot instantiate root type: %s" % root_type
		scene_root = ClassDB.instantiate(root_type) as Node

	var root_name := String(root_spec.get("name", "")).strip_edges()
	if not root_name.is_empty():
		scene_root.name = root_name

	var root_script := String(root_spec.get("script", "")).strip_edges()
	if not root_script.is_empty():
		var scr := ResourceLoader.load(root_script, "Script")
		if scr == null:
			scene_root.free()
			return "Failed to load root script: %s" % root_script
		scene_root.set_script(scr)

	var apply_err := _apply_spec(scene_root, scene_root, root_spec, true)
	if not apply_err.is_empty():
		scene_root.free()
		return apply_err

	var signals_list: Array = bp.get("signals", [])
	for sig_item in signals_list:
		if typeof(sig_item) == TYPE_DICTIONARY:
			var sd: Dictionary = sig_item
			var src := _resolve_in_tree(scene_root, String(sd.get("source", "")))
			var dst := _resolve_in_tree(scene_root, String(sd.get("target", ".")))
			if src == null or dst == null:
				scene_root.free()
				return "Signal node not found: %s -> %s" % [str(sd.get("source")), str(sd.get("target"))]
			var flags: int = Object.CONNECT_PERSIST if bool(sd.get("persist", true)) else 0
			src.connect(String(sd.get("signal", "")), Callable(dst, String(sd.get("method", ""))), flags)

	var abs_dir := ProjectSettings.globalize_path(scene_path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(abs_dir)

	var packed := PackedScene.new()
	var pack_err := packed.pack(scene_root)
	scene_root.free()
	if pack_err != OK:
		return "PackedScene.pack failed with code %d" % pack_err

	var save_err := ResourceSaver.save(packed, scene_path)
	if save_err != OK:
		return "ResourceSaver.save failed with code %d" % save_err
	return ""


func _apply_spec(scene_root: Node, current: Node, spec: Dictionary, is_root: bool) -> String:
	if not is_root:
		var scr_path := String(spec.get("script", "")).strip_edges()
		if not scr_path.is_empty():
			var scr := ResourceLoader.load(scr_path, "Script")
			if scr == null:
				return "Script not found: %s" % scr_path
			current.set_script(scr)

		if bool(spec.get("unique_name", false)):
			current.unique_name_in_owner = true

	if current is Control:
		var ctrl: Control = current as Control
		if spec.has("anchor_preset"):
			var ap: Variant = spec["anchor_preset"]
			var p_str := String(ap).to_lower() if typeof(ap) == TYPE_STRING else String((ap as Dictionary).get("preset", "full_rect")).to_lower()
			var keep_off := false if typeof(ap) == TYPE_STRING else bool((ap as Dictionary).get("keep_offsets", false))
			if PRESET_MAP.has(p_str):
				ctrl.set_anchors_preset(int(PRESET_MAP[p_str]), keep_off)

		if spec.has("size_flags") and typeof(spec["size_flags"]) == TYPE_DICTIONARY:
			var sf: Dictionary = spec["size_flags"]
			var h_str := String(sf.get("horizontal", "")).to_lower()
			var v_str := String(sf.get("vertical", "")).to_lower()
			if SIZE_FLAG_MAP.has(h_str):
				ctrl.size_flags_horizontal = int(SIZE_FLAG_MAP[h_str])
			if SIZE_FLAG_MAP.has(v_str):
				ctrl.size_flags_vertical = int(SIZE_FLAG_MAP[v_str])

		if spec.has("theme_overrides") and typeof(spec["theme_overrides"]) == TYPE_DICTIONARY:
			var to_dict: Dictionary = spec["theme_overrides"]
			for cat in to_dict.keys():
				var items: Variant = to_dict[cat]
				if typeof(items) != TYPE_DICTIONARY:
					continue
				var idict: Dictionary = items
				for iname in idict.keys():
					var raw_v: Variant = idict[iname]
					match String(cat):
						"constant", "constants":
							ctrl.set("theme_override_constants/%s" % String(iname), int(raw_v))
						"font_size", "font_sizes":
							ctrl.set("theme_override_font_sizes/%s" % String(iname), int(raw_v))
						"color", "colors":
							ctrl.set("theme_override_colors/%s" % String(iname), _to_color(raw_v))
						"stylebox", "styles":
							ctrl.set("theme_override_styles/%s" % String(iname), _to_stylebox(raw_v))

	if spec.has("properties") and typeof(spec["properties"]) == TYPE_DICTIONARY:
		var pdict: Dictionary = spec["properties"]
		for k in pdict.keys():
			var ks := String(k)
			current.set(ks, _coerce_value(current, ks, pdict[k]))

	var children: Array = spec.get("children", [])
	for c_item in children:
		if typeof(c_item) != TYPE_DICTIONARY:
			continue
		var cspec: Dictionary = c_item
		var child: Node = null
		var inst_path := String(cspec.get("instance", "")).strip_edges()
		if not inst_path.is_empty():
			var cpacked := ResourceLoader.load(inst_path, "PackedScene") as PackedScene
			if cpacked == null:
				return "Child PackedScene not found: %s" % inst_path
			child = cpacked.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		else:
			var ctype := String(cspec.get("type", "Node")).strip_edges()
			if not ClassDB.can_instantiate(ctype):
				return "Cannot instantiate child node type: %s" % ctype
			child = ClassDB.instantiate(ctype) as Node

		var cname := String(cspec.get("name", "")).strip_edges()
		if not cname.is_empty():
			child.name = cname

		current.add_child(child)
		child.owner = scene_root

		var cerr := _apply_spec(scene_root, child, cspec, false)
		if not cerr.is_empty():
			return cerr

	return ""


func _resolve_in_tree(scene_root: Node, npath: String) -> Node:
	if npath.is_empty() or npath == "." or npath == "/root":
		return scene_root
	if npath.begins_with("%"):
		var target_name := npath.substr(1)
		return _find_unique(scene_root, target_name)
	return scene_root.get_node_or_null(npath)


func _find_unique(node: Node, target_name: String) -> Node:
	if node.unique_name_in_owner and String(node.name) == target_name:
		return node
	for ch in node.get_children():
		var found := _find_unique(ch, target_name)
		if found != null:
			return found
	return null


func _coerce_value(target: Object, prop_name: String, val: Variant) -> Variant:
	var expected_type: int = TYPE_NIL
	for prop in target.get_property_list():
		if String(prop.get("name", "")) == prop_name:
			expected_type = int(prop.get("type", TYPE_NIL))
			break
	if expected_type == TYPE_OBJECT and typeof(val) == TYPE_STRING:
		var sp := String(val).strip_edges()
		return ResourceLoader.load(sp) if sp.begins_with("res://") else null
	if expected_type == TYPE_COLOR:
		return _to_color(val)
	if expected_type == TYPE_STRING_NAME and typeof(val) == TYPE_STRING:
		return StringName(val)
	if expected_type == TYPE_VECTOR2I and typeof(val) == TYPE_DICTIONARY:
		var d2i: Dictionary = val
		return Vector2i(int(d2i.get("x", 0)), int(d2i.get("y", 0)))
	if typeof(val) == TYPE_DICTIONARY:
		var d: Dictionary = val
		if d.has("$resource"):
			return ResourceLoader.load(String(d["$resource"]))
		if d.has("x") and d.has("y") and not d.has("z"):
			return Vector2(float(d["x"]), float(d["y"]))
		if d.has("x") and d.has("y") and d.has("z"):
			return Vector3(float(d["x"]), float(d["y"]), float(d["z"]))
		if d.has("r") and d.has("g") and d.has("b"):
			return Color(float(d["r"]), float(d["g"]), float(d["b"]), float(d.get("a", 1.0)))
	return val


func _to_color(val: Variant) -> Color:
	if val is Color:
		return val
	if typeof(val) == TYPE_STRING and Color.html_is_valid(String(val)):
		return Color.html(String(val))
	if typeof(val) == TYPE_DICTIONARY:
		var d: Dictionary = val
		return Color(float(d.get("r", 1.0)), float(d.get("g", 1.0)), float(d.get("b", 1.0)), float(d.get("a", 1.0)))
	return Color.WHITE


func _to_stylebox(val: Variant) -> StyleBox:
	if typeof(val) == TYPE_STRING:
		var s := String(val).strip_edges()
		if s == "empty":
			return StyleBoxEmpty.new()
		return ResourceLoader.load(s) as StyleBox if s.begins_with("res://") else null
	if typeof(val) == TYPE_DICTIONARY:
		var d: Dictionary = val
		if String(d.get("type", "StyleBoxFlat")) == "StyleBoxEmpty":
			return StyleBoxEmpty.new()
		var sb := StyleBoxFlat.new()
		if d.has("bg_color"):
			sb.bg_color = _to_color(d["bg_color"])
		if d.has("border_color"):
			sb.border_color = _to_color(d["border_color"])
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
		return sb
	return null
