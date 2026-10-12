@tool
extends RefCounted

## 2D / 3D / 脚本顶栏的定位按钮。点了只发 [signal locate_pressed]。
## 脚本编辑器没有官方 CONTAINER，顶栏要下一帧再找。

const EditorUtils = preload("../core/editor_utils.gd")

signal locate_pressed

#region State
var _plugin: EditorPlugin
var _canvas: Control
var _spatial: Control
var _script: Control
#endregion


#region Public API
## 把按钮挂到 2D / 3D 官方菜单槽；脚本顶栏延后挂。
func mount(plugin: EditorPlugin) -> void:
	_plugin = plugin
	_canvas = _make_toolbar()
	_spatial = _make_toolbar()
	plugin.add_control_to_container(EditorPlugin.CONTAINER_CANVAS_EDITOR_MENU, _canvas)
	plugin.add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _spatial)
	call_deferred("_mount_script")


## 从各槽位卸下按钮。脚本栏是 add_child，不能走 remove_control_from_container。
func unmount() -> void:
	if _plugin:
		if is_instance_valid(_canvas):
			_plugin.remove_control_from_container(EditorPlugin.CONTAINER_CANVAS_EDITOR_MENU, _canvas)
			_canvas.queue_free()
		if is_instance_valid(_spatial):
			_plugin.remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _spatial)
			_spatial.queue_free()
	if is_instance_valid(_script):
		_script.queue_free()
	_plugin = null
	_canvas = null
	_spatial = null
	_script = null
#endregion


#region Internal
func _mount_script() -> void:
	if _plugin == null:
		return
	var menu := EditorUtils.find_script_menu()
	if menu == null:
		return
	_script = _make_toolbar()
	menu.add_child(_script)


func _make_toolbar() -> Control:
	var bar := HBoxContainer.new()
	var button := EditorUtils.make_flat_button(
		"Filesystem",
		"FS",
		"Locate in FileSystem (Ctrl/Cmd+Shift+L)",
	)
	button.pressed.connect(_on_locate_pressed)
	bar.add_child(button)
	return bar


func _on_locate_pressed() -> void:
	locate_pressed.emit()
#endregion
