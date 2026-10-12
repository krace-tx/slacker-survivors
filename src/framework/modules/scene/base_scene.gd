class_name BaseScene
extends Node

## 顶层场景门面基类。
## 规范定义 4 大场景生命周期钩子：_on_enter / _on_exit / _on_pause / _on_resume。


#region Lifecycle
func _enter_tree() -> void:
	if Bus != null:
		Bus.app_paused.connect(_on_pause)
		Bus.app_resumed.connect(_on_resume)


func _exit_tree() -> void:
	if Bus != null:
		if Bus.app_paused.is_connected(_on_pause):
			Bus.app_paused.disconnect(_on_pause)
		if Bus.app_resumed.is_connected(_on_resume):
			Bus.app_resumed.disconnect(_on_resume)
#endregion


#region Scene Hooks
## 1. 进入：新实例入树成为栈顶时调用。[param _params] 来自 replace / push。
func _on_enter(_params: Dictionary = {}) -> void:
	pass


## 2. 退出：场景即将销毁退栈时调用。
func _on_exit() -> void:
	pass


## 3. 暂停：被新场景 push 压住或应用切后台 (Bus.app_paused) 时调用。
func _on_pause() -> void:
	pass


## 4. 恢复：上层场景 pop 离开或应用切回前台 (Bus.app_resumed) 时调用。[param _params] 来自那次 pop 或跳转。
func _on_resume(_params: Dictionary = {}) -> void:
	pass
#endregion
