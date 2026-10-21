@tool
extends VBoxContainer

## Editor bottom panel for Scene Define Generator.
## Pure English, native Godot Editor theme icons, single clean Tree layout.

signal scan_requested
signal inject_requested
signal open_script_requested
signal scene_activated(scene_path: String)

#region State
var _status_label: Label = null
var _scan_btn: Button = null
var _inject_btn: Button = null
var _open_script_btn: Button = null
var _auto_sync_check: CheckButton = null
var _tree: Tree = null
#endregion


#region Lifecycle & Public View API
func _ready() -> void:
	custom_minimum_size = Vector2(0, 220)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)

	_build_toolbar()
	_build_tree()
	scan_requested.emit()


func is_auto_inject_enabled() -> bool:
	return _auto_sync_check != null and _auto_sync_check.button_pressed


func render_snapshot(snapshot: Dictionary) -> void:
	if _tree == null:
		return

	var scenes: Dictionary = snapshot.get("scenes", {})
	var dialogs: Dictionary = snapshot.get("dialogs", {})
	var components: Dictionary = snapshot.get("components", {})
	var in_sync: bool = bool(snapshot.get("is_in_sync", false))

	_populate_tree(scenes, dialogs, components)

	if _status_label != null:
		var total := scenes.size() + dialogs.size() + components.size()
		if in_sync:
			_status_label.text = "Synced (%d entries)" % total
			_status_label.modulate = Color(0.55, 0.90, 0.60)
		else:
			_status_label.text = "Out of sync - click Inject to update"
			_status_label.modulate = Color(1.0, 0.82, 0.38)


func show_inject_feedback(result: Dictionary) -> void:
	if _status_label == null:
		return
	var changed := bool(result.get("changed", false))
	var time_str := Time.get_time_string_from_system()
	if changed:
		_status_label.text = "Injected at %s" % time_str
	else:
		_status_label.text = "Already up to date (%s)" % time_str
	_status_label.modulate = Color(0.55, 0.90, 0.60)
#endregion


#region Internal UI Construction
func _build_toolbar() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	add_child(bar)

	_scan_btn = Button.new()
	_scan_btn.text = "Scan"
	_scan_btn.tooltip_text = "Rescan res://src/game/ for route scenes"
	_scan_btn.icon = _editor_icon(&"Reload")
	_scan_btn.pressed.connect(func(): scan_requested.emit())
	bar.add_child(_scan_btn)

	_inject_btn = Button.new()
	_inject_btn.text = "Inject"
	_inject_btn.tooltip_text = "Write constants to res://src/game/shared/define/generated/game_scenes.gd"
	_inject_btn.icon = _editor_icon(&"Save")
	_inject_btn.pressed.connect(func(): inject_requested.emit())
	bar.add_child(_inject_btn)

	_open_script_btn = Button.new()
	_open_script_btn.text = "Open Script"
	_open_script_btn.tooltip_text = "Open generated game_scenes.gd in Script Editor"
	_open_script_btn.icon = _editor_icon(&"Script")
	_open_script_btn.pressed.connect(func(): open_script_requested.emit())
	bar.add_child(_open_script_btn)

	bar.add_child(VSeparator.new())

	_auto_sync_check = CheckButton.new()
	_auto_sync_check.text = "Auto-Inject"
	_auto_sync_check.button_pressed = false
	_auto_sync_check.tooltip_text = "Automatically inject when .tscn files change"
	bar.add_child(_auto_sync_check)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(_status_label)


func _build_tree() -> void:
	_tree = Tree.new()
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.columns = 3
	_tree.set_column_titles_visible(true)
	_tree.set_column_title(0, "Constant")
	_tree.set_column_title(1, "Resource Path")
	_tree.set_column_title(2, "Status")
	_tree.set_column_title_alignment(0, HORIZONTAL_ALIGNMENT_LEFT)
	_tree.set_column_title_alignment(1, HORIZONTAL_ALIGNMENT_LEFT)
	_tree.set_column_title_alignment(2, HORIZONTAL_ALIGNMENT_LEFT)
	_tree.set_column_expand(0, false)
	_tree.set_column_custom_minimum_width(0, 280)
	_tree.set_column_expand(1, true)
	_tree.set_column_custom_minimum_width(1, 320)
	_tree.set_column_expand(2, false)
	_tree.set_column_custom_minimum_width(2, 120)
	_tree.hide_root = true
	_tree.item_activated.connect(_on_tree_item_activated)
	add_child(_tree)


func _populate_tree(scenes: Dictionary, dialogs: Dictionary, components: Dictionary) -> void:
	_tree.clear()
	var root := _tree.create_item()

	_populate_group(root, "Scene", scenes)
	_populate_group(root, "Dialog", dialogs)
	_populate_group(root, "Component", components)


func _populate_group(root: TreeItem, group_key: String, entries: Dictionary) -> void:
	var group_item := _tree.create_item(root)
	group_item.set_text(0, "%s (%d)" % [group_key, entries.size()])
	group_item.set_icon(0, _editor_icon(&"Folder"))
	group_item.set_selectable(0, false)
	group_item.set_selectable(1, false)
	group_item.set_selectable(2, false)

	var scene_icon := _editor_icon(&"PackedScene")
	var keys: Array = entries.keys()
	keys.sort()
	for k in keys:
		var item := _tree.create_item(group_item)
		var const_expr := "GameScenes.%s.%s" % [group_key, String(k)]
		var res_path := String(entries[k])
		var exists := FileAccess.file_exists(res_path)

		item.set_text(0, const_expr)
		item.set_icon(0, scene_icon)
		item.set_text(1, res_path)
		item.set_metadata(0, res_path)
		if exists:
			item.set_text(2, "Ready")
			item.set_custom_color(2, Color(0.55, 0.90, 0.60))
		else:
			item.set_text(2, "Planned")
			item.set_custom_color(2, Color(0.90, 0.78, 0.45))


func _on_tree_item_activated() -> void:
	if _tree == null:
		return
	var selected := _tree.get_selected()
	if selected == null:
		return
	var res_path := str(selected.get_metadata(0))
	if not res_path.is_empty():
		scene_activated.emit(res_path)


func _editor_icon(icon_name: StringName) -> Texture2D:
	if Engine.is_editor_hint() and EditorInterface.get_base_control() != null:
		var base := EditorInterface.get_base_control()
		if base.has_theme_icon(icon_name, &"EditorIcons"):
			return base.get_theme_icon(icon_name, &"EditorIcons")
	return null
#endregion
