@tool
extends RefCounted

## 以选中文件夹为根整枝展开/收起。选中文件则退回父目录。
## 状态：根收起 → 展开根与已生成的子孙；有展开的子目录 → 只收子孙；否则收起根。
## FileSystem 未点开过的深层目录还没有 TreeItem，这里只能动已经实例化的节点。

const EditorUtils = preload("editor_utils.gd")

signal toggled(collapsed: bool)


#region Public API
## 以选中文件夹为根整枝展开/收起。选中文件则退回父目录。
func toggle() -> void:
	var tree := EditorUtils.find_folder_tree()
	if tree == null:
		return
	var item := tree.get_selected()
	if item == null:
		return
	if not _is_folder_item(item):
		item = item.get_parent()
		if item == null or not _is_folder_item(item):
			return

	if item.is_collapsed():
		item.set_collapsed(false)
		_set_descendants_collapsed(item, false)
		toggled.emit(false)
		return
	if _has_expanded_subfolder(item):
		_set_descendants_collapsed(item, true)
		toggled.emit(true)
		return
	item.set_collapsed(true)
	toggled.emit(true)
#endregion


#region Internal
## FileSystemDock：目录 metadata 以 `/` 结尾；Favorites 分组名固定不翻译。
func _is_folder_item(item: TreeItem) -> bool:
	var meta: Variant = item.get_metadata(0)
	if not meta is String:
		return item.get_first_child() != null
	var path := meta as String
	if path.is_empty():
		return item.get_first_child() != null
	return path == "res://" or path == "Favorites" or path.ends_with("/")


## 判断是否展开了子目录。
func _has_expanded_subfolder(item: TreeItem) -> bool:
	var child := item.get_first_child()
	while child:
		if _is_folder_item(child):
			if not child.is_collapsed():
				return true
			if _has_expanded_subfolder(child):
				return true
		child = child.get_next()
	return false


## 递归设置子目录的折叠状态。
func _set_descendants_collapsed(item: TreeItem, collapsed: bool) -> void:
	var child := item.get_first_child()
	while child:
		if _is_folder_item(child):
			child.set_collapsed(collapsed)
			_set_descendants_collapsed(child, collapsed)
		child = child.get_next()
#endregion
