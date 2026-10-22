class_name DisplayConfirmDialog
extends BaseDialog

## 15 秒显示设置确认弹窗组件
##
## 切屏或更改分辨率后弹出，支持倒计时自动还原、ESC 还原与确认保留。


#region 节点引用

@onready var _desc_label: Label = $CenterContainer/CardPanel/VBox/DescLabel as Label
@onready var _timeout_bar: ProgressBar = $CenterContainer/CardPanel/VBox/TimeoutBar as ProgressBar
@onready var _revert_btn: Button = $CenterContainer/CardPanel/VBox/ActionRow/RevertBtn as Button
@onready var _keep_btn: Button = $CenterContainer/CardPanel/VBox/ActionRow/KeepBtn as Button

#endregion


#region 私有变量

var _remaining_sec: float = 15.0
var _target_desc: String = ""
var _on_decided: Callable = Callable()
var _is_settled: bool = false

#endregion


#region 生命周期

func _ready() -> void:
	super._ready()
	close_on_backdrop = false
	close_on_back = false
	_keep_btn.pressed.connect(_on_keep_pressed)
	_revert_btn.pressed.connect(_on_revert_pressed)


func _on_open(params: BaseParams = null) -> void:
	_is_settled = false
	var confirm_params: ConfirmDialogParams = params as ConfirmDialogParams
	if confirm_params != null:
		_target_desc = confirm_params.target_desc
		_remaining_sec = confirm_params.timeout_sec
		_on_decided = confirm_params.on_decided
	else:
		_target_desc = "新显示设置"
		_remaining_sec = 15.0

	_timeout_bar.max_value = _remaining_sec
	_timeout_bar.value = _remaining_sec
	_update_countdown_text()
	_keep_btn.grab_focus()


func _process(delta: float) -> void:
	if _is_settled:
		return
	_remaining_sec -= delta
	if _remaining_sec <= 0.0:
		_remaining_sec = 0.0
		_settle(false)
		return
	_timeout_bar.value = _remaining_sec
	_update_countdown_text()


func _unhandled_input(event: InputEvent) -> void:
	if _is_settled:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_settle(false)

#endregion


#region 内部逻辑

func _update_countdown_text() -> void:
	var sec_int: int = ceili(_remaining_sec)
	_desc_label.text = "已应用「%s」。若画面显示正常请点击保留，否则将在 %d 秒后自动还原。" % [
		_target_desc,
		sec_int
	]
	_revert_btn.text = "还原 (%ds)" % sec_int


func _on_keep_pressed() -> void:
	_settle(true)


func _on_revert_pressed() -> void:
	_settle(false)


func _settle(keep_changes: bool) -> void:
	if _is_settled:
		return
	_is_settled = true
	var callback: Callable = _on_decided
	close()
	if callback.is_valid():
		callback.call(keep_changes)

#endregion
