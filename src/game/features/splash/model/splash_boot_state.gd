class_name SplashBootState
extends BaseParams

## 闪屏业务启动运行时动态状态模型（位于 src/game/features/splash/model/）。[br]
##
## [b]核心职责（遵循 `*State` 领域后缀规范）：[/b][br]
## 承载业务启动管线执行过程中的实时进度、当前任务文案与异常诊断状态，
## 状态变更时发射 [signal state_changed] 驱动 [SplashPresenter] 刷新视图。

signal state_changed()

enum Phase {
	IDLE = 0,
	RUNNING = 1,
	FAILED = 2,
	COMPLETED = 3,
}

#region Runtime State Fields
## 当前管线运行阶段
var phase: Phase = Phase.IDLE
## 归一化目标进度比值 `[0.0, 1.0]`
var progress_ratio: float = 0.0
## 当前正在执行的任务 ID
var current_task_id: StringName = &""
## 当前展示的状态提示文案
var status_text: String = "正在准备游戏数据..."
## 失败挂起时的任务 ID
var failed_task_id: StringName = &""
## 失败挂起时的错误码
var error_code: String = ""
## 失败挂起时的错误描述
var error_message: String = ""
#endregion


#region Public Mutators
## 标记管线进入运行状态
func mark_running(task_id: StringName, title: String, ratio: float) -> void:
	phase = Phase.RUNNING
	current_task_id = task_id
	status_text = title
	progress_ratio = clampf(ratio, 0.0, 1.0)
	failed_task_id = &""
	error_code = ""
	error_message = ""
	state_changed.emit()


## 更新当前任务完成后的进度比值
func update_progress(ratio: float, text: String = "") -> void:
	progress_ratio = clampf(ratio, 0.0, 1.0)
	if not text.is_empty():
		status_text = text
	state_changed.emit()


## 标记管线因 CRITICAL 任务失败而挂起
func mark_failed(task_id: StringName, code: String, message: String) -> void:
	phase = Phase.FAILED
	failed_task_id = task_id
	error_code = code
	error_message = message
	status_text = "启动异常 [%s]: %s" % [code, message]
	state_changed.emit()


## 标记管线全部完成
func mark_completed(total_ms: int, target_scene: String) -> void:
	phase = Phase.COMPLETED
	progress_ratio = 1.0
	current_task_id = &""
	if target_scene.is_empty():
		status_text = "启动就绪 (%d ms)" % total_ms
	elif not ResourceLoader.exists(target_scene):
		status_text = "启动就绪 (%d ms) · 待接入场景: %s" % [total_ms, target_scene.get_file()]
	else:
		status_text = "启动就绪"
	state_changed.emit()
#endregion
