@tool
extends RefCounted

## 把当前正在编的场景或脚本，在 FileSystem 里选中。
## 脚本屏优先脚本；其它屏优先场景，没有场景再回落到脚本。

#region State
var _screen: String = ""
#endregion


#region Public API
## 记下当前主屏名称（2D / 3D / Script），[method locate] 用它决定跟场景还是跟脚本。
func set_screen(screen_name: String) -> void:
	_screen = screen_name


## 解析当前文件路径并在 FileSystem 中选中。没有可定位的文件则什么都不做。
func locate() -> void:
	# 按主屏排出候选，返回第一个能在 FileSystem 里打开的路径。
	var path := resolve()
	if path.is_empty():
		return
	# 在 FileSystem 中选中路径。
	EditorInterface.get_file_system_dock().navigate_to_path(path)


## 是否为定位快捷键 Ctrl/Cmd+Shift+L。
func is_shortcut(event: InputEvent) -> bool:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return false
	var key := event as InputEventKey
	var cmd := key.ctrl_pressed or key.meta_pressed
	# 判断是否为定位快捷键 Ctrl/Cmd+Shift+L。
	return cmd and key.shift_pressed and not key.alt_pressed and key.keycode == KEY_L


## 脚本屏：脚本 → 场景。其它屏：场景 → 脚本。命中即返回。
func resolve() -> String:
	if _screen == "Script":
		var script := _script_path()
		return script if not script.is_empty() else _scene_path()
	var scene := _scene_path()
	return scene if not scene.is_empty() else _script_path()
#endregion


#region Internal
## 获取当前编辑的场景路径。
func _scene_path() -> String:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return ""
	return root.scene_file_path


## 获取当前编辑的脚本路径，返回冒号前面的场景文件路径。
func _script_path() -> String:
	var script := EditorInterface.get_script_editor().get_current_script()
	if script == null:
		return ""
	# 内置脚本是 `scene.tscn::xxx`，FileSystem 只认冒号前面。
	return script.resource_path.get_slice("::", 0)
#endregion
