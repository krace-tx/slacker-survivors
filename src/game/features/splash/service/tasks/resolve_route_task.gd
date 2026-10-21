class_name ResolveRouteTask
extends BootTask

## 启动任务 5：终局首屏路由裁决器 (CRITICAL)。[br]
## 综合评估外部强制直达路由、未完结战局重连快照、新玩家首次引导状态，决定启动完成后的目标场景。


func get_task_id() -> StringName:
	return &"resolve_route"


func get_task_title() -> String:
	return "裁决首屏目标场景路由"


func get_weight() -> float:
	return 15.0


func get_failure_policy() -> FailurePolicy:
	return FailurePolicy.CRITICAL


func execute(context: SplashBootContext) -> Result:
	if context == null:
		return Result.err_code("Splash.ContextMissing", "SplashBootContext is null during route resolution.")

	# 优先级 1：开发者调试或 DeepLink 显式指定的覆盖场景
	if not context.override_target_scene.is_empty():
		context.target_scene_path = context.override_target_scene
		context.target_scene_params = context.override_target_params
		return Result.ok()

	# 优先级 2：检测到未完结的局内战斗存档且战斗场景已就绪时，优先路由至战斗恢复
	if context.has_unfinished_run and ResourceLoader.exists(GameConstants.SCENE_BATTLE):
		context.target_scene_path = GameConstants.SCENE_BATTLE
		return Result.ok()

	# 优先级 3：默认路由至游戏主大厅场景
	context.target_scene_path = GameConstants.SCENE_LOBBY
	return Result.ok()
