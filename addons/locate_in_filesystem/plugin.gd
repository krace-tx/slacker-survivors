@tool
extends EditorPlugin

## 编辑器定位门面。
## 核心：把当前场景/脚本在 FileSystem 里点出来。文件夹整枝展开/收起是附带能力。

const FileService = preload("core/file_service.gd")
const FolderService = preload("core/folder_service.gd")
const FileToolbar = preload("ui/file_toolbar.gd")
const FolderToolbar = preload("ui/folder_toolbar.gd")

#region Services
var files:		FileService		## 定位当前场景/脚本
var folders:	FolderService	## 文件夹整枝展开/收起
#endregion

#region Toolbars
var _file_toolbar: FileToolbar
var _folder_toolbar: FolderToolbar
#endregion


#region Lifecycle
## 创建服务、挂工具栏、注册菜单与快捷键。
func _enter_tree() -> void:
	files = FileService.new()
	folders = FolderService.new()

	# 定位按钮挂到 2D / 3D / 脚本顶栏；折叠按钮挂到 FileSystem。
	_file_toolbar = FileToolbar.new()
	_folder_toolbar = FolderToolbar.new()
	_file_toolbar.mount(self)
	_file_toolbar.locate_pressed.connect(files.locate)
	_folder_toolbar.mount(folders)

	add_tool_menu_item("Locate in FileSystem", files.locate)
	# 脚本屏跟脚本，其它屏跟场景
	main_screen_changed.connect(files.set_screen)
	set_process_input(true)


## 卸工具栏、菜单和信号。
func _exit_tree() -> void:
	set_process_input(false)
	remove_tool_menu_item("Locate in FileSystem")
	if files and main_screen_changed.is_connected(files.set_screen):
		main_screen_changed.disconnect(files.set_screen)

	if _file_toolbar:
		_file_toolbar.unmount()
	if _folder_toolbar:
		_folder_toolbar.unmount()

	_file_toolbar = null
	_folder_toolbar = null
	files = null
	folders = null
#endregion


#region Shortcut
## Ctrl/Cmd+Shift+L：定位当前文件。
func _input(event: InputEvent) -> void:
	if files == null or not files.is_shortcut(event):
		return
	files.locate()
	get_viewport().set_input_as_handled()
#endregion
