@tool
extends RefCounted

## 编辑器内部控件查找。
## 编辑器改版时优先改这里，不要散落到各个工具栏。

#region Public API
## 脚本编辑器顶栏。BFS 找带 MenuBar 的 HBox；没有再退到带 MenuButton 的。
static func find_script_menu() -> HBoxContainer:
	var script_editor := EditorInterface.get_script_editor()
	if script_editor == null:
		return null
	var with_menu := _find_first(script_editor, func(node: Node) -> bool:
		return node is HBoxContainer and _has_child_of_class(node, "MenuBar")
	) as HBoxContainer
	if with_menu:
		return with_menu
	return _find_first(script_editor, func(node: Node) -> bool:
		return node is HBoxContainer and _has_child_of_class(node, "MenuButton")
	) as HBoxContainer


## FileSystem 文件夹搜索框旁的 Sort。图标是 EditorIcons/Sort，不随语言变。
## 文件列表还有第二个 Sort，BFS 会先碰到较浅的那个（文件夹树工具栏）。
static func find_sort_files_button() -> MenuButton:
	var dock := EditorInterface.get_file_system_dock()
	if dock == null:
		return null
	var sort_icon := get_icon("Sort")
	return _find_first(dock, func(node: Node) -> bool:
		return node is MenuButton and sort_icon != null and (node as MenuButton).icon == sort_icon
	) as MenuButton


## 左侧文件夹树。首项 metadata 固定为 "Favorites"（显示文本会翻译）。
static func find_folder_tree() -> Tree:
	var dock := EditorInterface.get_file_system_dock()
	if dock == null:
		return null
	var favorites_icon := get_icon("Favorites")
	var trees: Array[Tree] = []
	_collect_by_class(dock, "Tree", trees)
	for tree in trees:
		var root := tree.get_root()
		if root == null:
			continue
		var first := root.get_first_child()
		if first == null:
			continue
		if str(first.get_metadata(0)) == "Favorites":
			return tree
		if favorites_icon and first.get_icon(0) == favorites_icon:
			return tree
	if trees.size() > 0:
		return trees[0]
	return null


static func get_icon(icon_name: String) -> Texture2D:
	var host := EditorInterface.get_base_control()
	if host == null:
		return null
	if host.has_theme_icon(icon_name, &"EditorIcons"):
		return host.get_theme_icon(icon_name, &"EditorIcons")
	return null


static func make_flat_button(icon_name: String, fallback_text: String, tooltip: String) -> Button:
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = tooltip
	var icon := get_icon(icon_name)
	if icon:
		button.icon = icon
	else:
		button.text = fallback_text
	return button
#endregion


#region Internal
## 广度优先，含 internal 子节点。浅层控件先于深层，避免取到嵌套工具栏。
static func _find_first(root: Node, matches: Callable) -> Node:
	var queue: Array[Node] = [root]
	while not queue.is_empty():
		var node: Node = queue.pop_front()
		if node != root and matches.call(node):
			return node
		for child in node.get_children(true):
			queue.append(child)
	return null


static func _collect_by_class(root: Node, class_name_str: String, out: Array) -> void:
	if root.get_class() == class_name_str:
		out.append(root)
	for child in root.get_children(true):
		_collect_by_class(child, class_name_str, out)


static func _has_child_of_class(node: Node, class_name_str: String) -> bool:
	for child in node.get_children(true):
		if child.get_class() == class_name_str:
			return true
	return false
#endregion
