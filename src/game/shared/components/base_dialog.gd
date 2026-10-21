class_name BaseDialog
extends Control

## 模态弹窗业务基类。
## 位于业务共享组件层 (src/game/shared/components/)。
## 提供打开/关闭生命周期钩子、弹性补间动画、入参获取以及点击背景遮罩自闭能力。

signal opened
signal closed

#region Exports
@export_group("Modal Behavior")
## 点击半透明背景遮罩是否自动关闭
@export var close_on_backdrop: bool = true
## 收到物理返回键 / ESC 时是否优先拦截并关闭自身
@export var close_on_back: bool = true
## 是否启用弹窗入场和退场默认补间动画
@export var enable_animation: bool = true
## 动画作用的目标节点（为空时默认为自身）
@export var animation_target_path: NodePath = ""
#endregion

#region State
var _params: Dictionary = {}
var _is_closing: bool = false
#endregion

#region Public API
## 打开弹窗（由 DialogManager 或调用端驱动）
func open(params: Dictionary = {}) -> void:
	_params = params
	_is_closing = false
	visible = true

	_on_open(_params)

	if enable_animation:
		_play_enter_animation()
	else:
		opened.emit()


## 关闭弹窗
func close() -> void:
	if _is_closing:
		return
	_is_closing = true

	_on_close()

	if enable_animation:
		_play_exit_animation()
	else:
		_finish_close()


## 获取入参字典
func get_params() -> Dictionary:
	return _params
#endregion

#region Lifecycle Hooks (Subclass Overrides)
## 弹窗打开时回调（入场动画前，用于绑定数据、填充文本）
func _on_open(_data: Dictionary) -> void:
	pass


## 弹窗关闭时回调（退场动画前，用于注销监听、保存临时态）
func _on_close() -> void:
	pass
#endregion

#region Animation & Internal
func _get_anim_node() -> Control:
	if not animation_target_path.is_empty():
		var node := get_node_or_null(animation_target_path) as Control
		if node != null:
			return node
	return self


func _play_enter_animation() -> void:
	var target := _get_anim_node()
	target.pivot_offset = target.size * 0.5
	target.scale = Vector2(0.8, 0.8)
	target.modulate.a = 0.0

	var tween := create_tween().set_parallel(true)
	tween.tween_property(target, "scale", Vector2.ONE, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(target, "modulate:a", 1.0, 0.15) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(func(): opened.emit())


func _play_exit_animation() -> void:
	var target := _get_anim_node()
	target.pivot_offset = target.size * 0.5

	var tween := create_tween().set_parallel(true)
	tween.tween_property(target, "scale", Vector2(0.85, 0.85), 0.15) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(target, "modulate:a", 0.0, 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(_finish_close)


func _finish_close() -> void:
	closed.emit()
	DialogManager.close(self)
#endregion
