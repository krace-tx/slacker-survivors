class_name ConfirmDialogParams
extends BaseParams

## 15 秒切屏确认弹窗入参契约（位于 src/test/display/model/）。


#region 成员属性

## 目标窗口/分辨率变更描述文本
var target_desc: String = ""

## 自动回滚倒计时秒数（默认 15 秒）
var timeout_sec: float = 15.0

## 用户确认或超时回滚的决断回调 `func(confirmed: bool) -> void`
var on_decided: Callable = Callable()

#endregion


#region 生命周期与校验

func _init(
	p_target_desc: String = "",
	p_timeout_sec: float = 15.0,
	p_on_decided: Callable = Callable()
) -> void:
	target_desc = p_target_desc
	timeout_sec = p_timeout_sec
	on_decided = p_on_decided


func _validate() -> bool:
	return not target_desc.is_empty() and timeout_sec > 0.0

#endregion
