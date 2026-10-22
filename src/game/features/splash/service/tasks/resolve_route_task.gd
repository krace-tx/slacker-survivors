class_name ResolveRouteTask
extends BootTask

## 启动任务 5：终局首屏路由裁决器 (`CRITICAL`)。[br]
## 评估外部强制直达路由（如开发测试覆盖或 DeepLink）与默认首屏目标场景，决定启动完成后的跳转目标。

const _TASK_ID: StringName = &"resolve_route"
const _TASK_TITLE: String = "准备就绪"
const _TASK_WEIGHT: float = 15.0
const _ERR_CONTEXT_MISSING: String = "Splash.ContextMissing"

var _default_target_scene: String = ""


func _init(default_target_scene: String = "") -> void:
	_default_target_scene = default_target_scene


func get_task_id() -> StringName:
	return _TASK_ID


func get_task_title() -> String:
	return _TASK_TITLE


func get_weight() -> float:
	return _TASK_WEIGHT


func get_failure_policy() -> FailurePolicy:
	return FailurePolicy.CRITICAL


func execute(context: SplashBootContext) -> Result:
	if context == null:
		return Result.err_code(_ERR_CONTEXT_MISSING, "SplashBootContext is null during route resolution.")

	# 优先级 1：开发者调试或 DeepLink 显式指定的覆盖场景
	if not context.override_target_scene.is_empty():
		context.target_scene_path = context.override_target_scene
		context.target_scene_params = context.override_target_params
		return Result.ok()

	# 优先级 2：构造时指定的默认首屏目标场景
	context.target_scene_path = _default_target_scene
	return Result.ok()
