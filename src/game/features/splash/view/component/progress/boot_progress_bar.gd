class_name BootProgressBar
extends ProgressBar

## 具备视觉阻尼平滑插值能力的启动进度条控件（位于 src/game/features/splash/view/component/progress/）。[br]
## 挂载于 [BootProgressPanel] 预制体内部的 `ProgressBar` 节点，独立负责帧级插值动画与实时视觉比例分发。

## 当视觉插值进度发生变化时发射，供父面板同步刷新百分比数字
signal visual_ratio_changed(visual_ratio: float)

#region Constants & State
const _MIN_INTERP_SPEED: float = 2.0
const _INTERP_DAMPING_FACTOR: float = 8.0
const _PERCENT_SCALE: float = 100.0

var _target_ratio: float = 0.0
var _visual_ratio: float = 0.0
#endregion


#region Engine Lifecycle
func _process(delta: float) -> void:
	if is_equal_approx(_visual_ratio, _target_ratio):
		return
	var speed: float = maxf(
		_MIN_INTERP_SPEED,
		absf(_target_ratio - _visual_ratio) * _INTERP_DAMPING_FACTOR
	)
	_visual_ratio = move_toward(_visual_ratio, _target_ratio, speed * delta)
	value = _visual_ratio * _PERCENT_SCALE
	visual_ratio_changed.emit(_visual_ratio)
#endregion


#region Public API
## 设置目标归一化进度 `[0.0, 1.0]`，由 `_process` 平滑追赶
func set_target_ratio(target_ratio: float) -> void:
	_target_ratio = clampf(target_ratio, 0.0, 1.0)


## 立即瞬移至指定归一化进度 `[0.0, 1.0]`（无过渡延迟，用于初始化归零或 100% 完成态）
func snap_to_ratio(target_ratio: float) -> void:
	var clamped: float = clampf(target_ratio, 0.0, 1.0)
	_target_ratio = clamped
	_visual_ratio = clamped
	value = clamped * _PERCENT_SCALE
	visual_ratio_changed.emit(_visual_ratio)


## 获取当前视觉插值归一化进度 `[0.0, 1.0]`
func get_visual_ratio() -> float:
	return _visual_ratio
#endregion
