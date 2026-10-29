extends SceneTree
## Godot 声明式场景树结构与布局静态/动态审计器 (Headless Scene Auditor)
##
## 执行项：
## 1. PackedScene 加载与无错实例化校验；
## 2. 单文件本地拥有节点数预算检查（剔除子预制体内部节点，防止巨石 .tscn）；
## 3. 等待 2 帧布局解算后，检测可见交互控件 0x0 尺寸塌陷与视口越界溢出；
## 4. 扫描同单元目录 .gd 脚本，拦截违规静态布局容器 `.new()` 与深层 `$A/B/C` 硬编码路径。

const FORBIDDEN_LAYOUT_NEW := [
	"VBoxContainer.new(",
	"HBoxContainer.new(",
	"PanelContainer.new(",
	"MarginContainer.new(",
	"GridContainer.new(",
	"ScrollContainer.new(",
	"CenterContainer.new(",
	"SplitContainer.new(",
	"HSplitContainer.new(",
	"VSplitContainer.new(",
	"TabContainer.new(",
]

var _target_scenes: Array[String] = []
var _max_local_nodes: int = 40


func _initialize() -> void:
	if root != null:
		root.size = Vector2i(1920, 1080)
		var app_node := root.get_node_or_null("App")
		if app_node != null:
			app_node.set("_boot_done", true)

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			_target_scenes.append(_normalize_res(arg.trim_prefix("--scene=")))
		elif arg.begins_with("--dir="):
			_collect_tscn(_normalize_res(arg.trim_prefix("--dir=")), _target_scenes)
		elif arg.begins_with("--max-nodes="):
			_max_local_nodes = maxi(10, int(arg.trim_prefix("--max-nodes=")))

	if _target_scenes.is_empty():
		printerr("[SCENE_AUDIT_FAIL] Provide --scene=res://...tscn or --dir=res://...")
		quit(1)
		return

	_run_audit.call_deferred()


func _run_audit() -> void:
	var reports: Array[Dictionary] = []
	var has_errors := false

	for spath in _target_scenes:
		var rep := await _audit_single_scene(spath)
		reports.append(rep)
		if not (rep.get("errors", []) as Array).is_empty():
			has_errors = true

	var summary := {
		"status": "FAIL" if has_errors else "PASS",
		"audited_count": reports.size(),
		"reports": reports,
	}
	print(JSON.stringify(summary, "  "))
	quit(1 if has_errors else 0)


func _audit_single_scene(scene_path: String) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []

	if not ResourceLoader.exists(scene_path):
		errors.append("Scene file does not exist: %s" % scene_path)
		return {"scene": scene_path, "errors": errors, "warnings": warnings}

	var packed := ResourceLoader.load(scene_path, "PackedScene") as PackedScene
	if packed == null:
		errors.append("Failed to load PackedScene: %s" % scene_path)
		return {"scene": scene_path, "errors": errors, "warnings": warnings}

	var state: SceneState = packed.get_state()
	var local_node_count: int = state.get_node_count() if state != null else 0
	var sub_instance_count: int = 0
	if state != null:
		for i in range(state.get_node_count()):
			if state.get_node_instance(i) != null:
				sub_instance_count += 1

	if local_node_count > _max_local_nodes:
		warnings.append(
			"Local node count (%d) exceeds prefab budget (%d); consider decomposing repeated sections into child component .tscn"
			% [local_node_count, _max_local_nodes]
		)

	var inst := packed.instantiate()
	if inst == null:
		errors.append("PackedScene.instantiate() returned null")
		return {"scene": scene_path, "errors": errors, "warnings": warnings}

	var host := SubViewport.new()
	host.size = Vector2i(1920, 1080)
	host.render_target_update_mode = SubViewport.UPDATE_ONCE
	root.add_child(host)
	host.add_child(inst)

	await process_frame
	await process_frame

	var is_stage_scene: bool = (
		scene_path.contains("/scene/")
		or scene_path.ends_with("_scene.tscn")
		or scene_path.ends_with("_test.tscn")
	)

	if inst is Control:
		_audit_control_subtree(inst, inst as Control, is_stage_scene, false, errors, warnings)

	_audit_unit_scripts(scene_path.get_base_dir(), errors, warnings)

	host.remove_child(inst)
	inst.free()
	root.remove_child(host)
	host.free()

	return {
		"scene": scene_path,
		"local_nodes": local_node_count,
		"sub_prefabs": sub_instance_count,
		"errors": errors,
		"warnings": warnings,
	}


func _audit_control_subtree(
	scene_root: Node,
	ctrl: Control,
	check_viewport_bounds: bool,
	inside_scroll: bool,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	if not ctrl.is_visible_in_tree():
		return

	var rel_path := "." if ctrl == scene_root else str(scene_root.get_path_to(ctrl))
	var is_interactive: bool = (
		ctrl is BaseButton
		or ctrl is LineEdit
		or ctrl is TextEdit
		or ctrl is Range
		or ctrl is TabBar
	)
	if is_interactive and (ctrl.size.x <= 1.0 or ctrl.size.y <= 1.0):
		errors.append("Interactive Control '%s' (%s) collapsed to size %s" % [rel_path, ctrl.get_class(), str(ctrl.size)])

	if check_viewport_bounds and not inside_scroll:
		var grect := ctrl.get_global_rect()
		if grect.size.x > 0.0 and grect.size.y > 0.0:
			if grect.position.x < -6.0 or grect.position.y < -6.0 or grect.end.x > 1926.0 or grect.end.y > 1086.0:
				warnings.append("Control '%s' global rect %s overflows 1920x1080 viewport" % [rel_path, str(grect)])

	var next_scroll: bool = inside_scroll or (ctrl is ScrollContainer)
	for ch in ctrl.get_children():
		if ch is Control:
			_audit_control_subtree(scene_root, ch as Control, check_viewport_bounds, next_scroll, errors, warnings)


func _audit_unit_scripts(unit_dir: String, errors: Array[String], warnings: Array[String]) -> void:
	var dir := DirAccess.open(unit_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if not dir.current_is_dir() and entry.ends_with(".gd"):
			var gd_path := unit_dir.path_join(entry)
			var src := FileAccess.get_file_as_string(gd_path)
			var lines := src.split("\n")
			for i in range(lines.size()):
				var stripped := lines[i].strip_edges()
				if stripped.begins_with("#"):
					continue
				for token in FORBIDDEN_LAYOUT_NEW:
					if stripped.contains(token):
						errors.append(
							"%s:%d Imperative layout construction '%s' forbidden in declarative view unit; move container into .tscn"
							% [gd_path, i + 1, token.trim_suffix("(")]
						)
				if stripped.contains("get_node(\"") and stripped.count("/") >= 2 and not stripped.contains("%"):
					warnings.append(
						"%s:%d Deep hardcoded get_node path detected; prefer %%UniqueName or @export"
						% [gd_path, i + 1]
					)
		entry = dir.get_next()
	dir.list_dir_end()


func _collect_tscn(dir_path: String, out_list: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if not entry.begins_with("."):
			var full := dir_path.path_join(entry)
			if dir.current_is_dir():
				_collect_tscn(full, out_list)
			elif entry.ends_with(".tscn"):
				out_list.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _normalize_res(p: String) -> String:
	var s := p.strip_edges().replace("\\", "/")
	if not s.begins_with("res://"):
		s = "res://" + s.trim_prefix("/")
	return s
