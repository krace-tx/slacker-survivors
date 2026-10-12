class_name HapticFeedback
extends BaseHapticFeedback

## 触觉振动反馈器：统一持有玩家振动总开关并裁决全部振动请求。
## 全项目"要不要振、何时振"的调度统一收敛于此，引擎调用（Input.vibrate_handheld）只在本服务内发生。
## 纯 RefCounted 实现，轻量、无需常驻场景树。

#region State
## 播放序列令牌：新的 [method pattern] 调用使旧序列在下一个时间片自停（打断上一段）。
var _token: int = 0
#endregion

#region Lifecycle
func initialize() -> Result:
	return Result.ok()


func dispose() -> void:
	_token += 1
#endregion

#region Public API
## 写入玩家振动总开关。[br]
## 由设置管理器在设置变更与启动恢复（apply_all）时调用。
func set_enabled(value: bool) -> void:
	enabled = value


## 触发一次设备振动。[br]
## [param duration_ms] 持续毫秒。默认 15。小于等于 0，或 [member enabled] 为 [code]false[/code] 时不振。
func vibrate(duration_ms: int = 15) -> void:
	pattern([duration_ms])


## 按模式振动。[br]
## [param steps] 毫秒序列，偶数下标是振动时长，奇数下标是间隔（不振）。例如 [code][100, 50, 100][/code] 为振、停、再振。[br]
## 空数组、[member enabled] 为 [code]false[/code] 时不振。再次调用会打断尚未播完的上一段。
func pattern(steps: Array[int]) -> void:
	if not enabled or steps.is_empty():
		return
	_token += 1
	_play(steps, 0, _token)
#endregion

#region Internal
func _play(steps: Array[int], index: int, token: int) -> void:
	if token != _token or not enabled or index >= steps.size():
		return
	var duration_ms: int = steps[index]
	if duration_ms > 0:
		Input.vibrate_handheld(duration_ms)
	if index + 1 >= steps.size():
		return
	var gap_ms: int = steps[index + 1]
	if gap_ms <= 0:
		_play(steps, index + 2, token)
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	tree.create_timer(gap_ms / 1000.0).timeout.connect(
		_play.bind(steps, index + 2, token),
		CONNECT_ONE_SHOT
	)
#endregion
