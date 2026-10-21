class_name WarmupAssetsTask
extends BootTask

## 启动任务 4：执行首屏核心公共资源与大厅预热 (OPTIONAL)。[br]
## 采用分帧平滑预热策略，避免首屏切换卡顿；若个别非关键资源预热失败，静默忽略绝不阻断进游。

var _warmup_paths: Array[String] = []


func _init(warmup_paths: Array[String] = []) -> void:
	_warmup_paths = warmup_paths.duplicate()


func get_task_id() -> StringName:
	return &"warmup_assets"


func get_task_title() -> String:
	return "预热首屏核心资源与着色器"


func get_weight() -> float:
	return 25.0


func get_failure_policy() -> FailurePolicy:
	return FailurePolicy.OPTIONAL


func execute(_context: SplashBootContext) -> Result:
	if App.asset == null:
		return Result.ok()

	var valid_paths: Array[String] = []
	for path in _warmup_paths:
		if not path.is_empty() and ResourceLoader.exists(path):
			valid_paths.append(path)

	if valid_paths.is_empty() and ResourceLoader.exists(GameConstants.SCENE_LOBBY):
		valid_paths.append(GameConstants.SCENE_LOBBY)

	if not valid_paths.is_empty():
		await App.asset.preload_batch(valid_paths)

	return Result.ok()
