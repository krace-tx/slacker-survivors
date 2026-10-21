class_name BaseDialog
extends BaseView

## 模态弹窗业务基类（继承自 [BaseView]，位于 src/game/shared/component/dialog/）。[br]
## 复用 [BaseView] 的统一生命周期契约（[method open] / [method close] / [method _on_open] / [method _on_close]）、
## 强类型 [BaseParams] 入参持有及 [member BaseView.task_scope] 异步任务自动取消能力，
## 并扩展模态弹窗专属的进退场弹性补间动画与背景遮罩/返回键自闭控制。

#region Constants
const _ENTER_INITIAL_SCALE: Vector2 = Vector2(0.8, 0.8)
const _EXIT_TARGET_SCALE: Vector2 = Vector2(0.85, 0.85)
const _ENTER_SCALE_DURATION: float = 0.20
const _ENTER_ALPHA_DURATION: float = 0.15
const _EXIT_SCALE_DURATION: float = 0.15
const _EXIT_ALPHA_DURATION: float = 0.12
const _PROP_SCALE: NodePath = ^"scale"
const _PROP_MODULATE_ALPHA: NodePath = ^"modulate:a"
#endregion

#region Exports
@export_group("Modal Behavior")
## 点击半透明背景遮罩是否自动关闭
@export var close_on_backdrop: bool = true
## 收到物理返回键 / ESC 时是否优先拦截并关闭自身
@export var close_on_back: bool = true
## 是否启用弹窗入场和退场默认补间动画
@export var enable_animation: bool = true
## 动画作用的目标节点（为空时默认为自身）
@export var animation_target_path: NodePath = ^""
#endregion

#region State
var _is_closing: bool = false
#endregion


#region Lifecycle & Public API
func _init() -> void:
	# 模态弹窗默认居中展示，不强制拉伸为全屏安全区（全屏型弹窗可在检查器中开启）
	apply_safe_area = false


## 打开弹窗（由 [DialogManager] 或调用端驱动）
func open(params: BaseParams = null) -> void:
	_params = params
	_is_closing = false
	_is_opened = true
	visible = true

	_on_open(_params)

	if enable_animation:
		_play_enter_animation()
	else:
		opened.emit()


## 关闭弹窗（自动取消当前弹窗 task_scope 下的悬挂异步任务）
func close() -> void:
	if _is_closing:
		return
	_is_closing = true
	_is_opened = false

	if _task_scope != null:
		_task_scope.cancel_all("Dialog closed.")

	_on_close()

	if enable_animation:
		_play_exit_animation()
	else:
		_finish_close()
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
	target.scale = _ENTER_INITIAL_SCALE
	target.modulate.a = 0.0

	var tween := create_tween().set_parallel(true)
	tween.tween_property(target, _PROP_SCALE, Vector2.ONE, _ENTER_SCALE_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(target, _PROP_MODULATE_ALPHA, 1.0, _ENTER_ALPHA_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(_on_enter_animation_finished)


func _play_exit_animation() -> void:
	var target := _get_anim_node()
	target.pivot_offset = target.size * 0.5

	var tween := create_tween().set_parallel(true)
	tween.tween_property(target, _PROP_SCALE, _EXIT_TARGET_SCALE, _EXIT_SCALE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(target, _PROP_MODULATE_ALPHA, 0.0, _EXIT_ALPHA_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(_finish_close)


func _on_enter_animation_finished() -> void:
	opened.emit()


func _finish_close() -> void:
	closed.emit()
	DialogManager.close(self)
#endregion
