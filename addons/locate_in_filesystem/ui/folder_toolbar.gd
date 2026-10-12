@tool
extends RefCounted

## FileSystem Sort 按钮旁边：整枝展开/收起。
## 点击交给 FolderService；图标只跟 [signal FolderService.toggled] 走。

const EditorUtils = preload("../core/editor_utils.gd")
const FolderService = preload("../core/folder_service.gd")

#region State
var _folders: FolderService
var _button: Button
#endregion


#region Public API
## 文件坞这一帧可能还没建好 Sort，下一帧再插到它右边。
func mount(folders: FolderService) -> void:
	_folders = folders
	_folders.toggled.connect(_on_folder_toggled)
	call_deferred("_mount_button")


func unmount() -> void:
	if _folders and _folders.toggled.is_connected(_on_folder_toggled):
		_folders.toggled.disconnect(_on_folder_toggled)
	if is_instance_valid(_button):
		_button.queue_free()
	_button = null
	_folders = null
#endregion


#region Internal
func _mount_button() -> void:
	var sort := EditorUtils.find_sort_files_button()
	if sort == null:
		return
	_button = EditorUtils.make_flat_button(
		"ExpandTree",
		"+",
		"Expand all folders under the selection",
	)
	_button.pressed.connect(_folders.toggle)
	var bar := sort.get_parent()
	bar.add_child(_button)
	bar.move_child(_button, sort.get_index() + 1)


## collapsed=true 显示展开图标，表示下一步是展开。
func _on_folder_toggled(collapsed: bool) -> void:
	if not is_instance_valid(_button):
		return
	var icon_name := "ExpandTree" if collapsed else "CollapseTree"
	var icon := EditorUtils.get_icon(icon_name)
	if icon:
		_button.icon = icon
		_button.text = ""
	else:
		_button.text = "+" if collapsed else "−"
	_button.tooltip_text = (
		"Expand all folders under the selection" if collapsed
		else "Collapse all folders under the selection"
	)
#endregion
