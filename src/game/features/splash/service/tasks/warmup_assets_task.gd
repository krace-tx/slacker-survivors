class_name WarmupAssetsTask
extends BootTask

## 启动任务 4：执行首屏核心公共资源并发预载与 Shader GPU 管线分帧预热 (`OPTIONAL`)。[br]
##
## [b]两阶段工业化预热流水线：[/b][br]
## 1. [b]阶段一（多线程磁盘 I/O 预载）[/b]：合并显式路径与 [ShaderWarmupConfig] 清单路径，
##    调用 [method BaseAssetSystem.preload_batch] 瞬间打满后台多核 I/O 队列，并按配置调用 `App.asset.pin()` 锁定常驻核心材质；[br]
## 2. [b]阶段二（自适应分帧 GPU PSO 烘烤）[/b]：调用 [method ShaderWarmer.warmup_resources_async] 静态穿透提取 `.tscn` 内嵌材质，
##    在微缩暗箱中完成 `RenderingServer.frame_post_draw` 真绘制管线编译，并将 [ShaderWarmupReport] 写入 [SplashBootContext] 诊断上下文。


#region 常量与成员属性

const _TASK_ID: StringName = &"warmup_assets"
const _TASK_TITLE: String = "预热资源与着色器"
const _TASK_WEIGHT: float = 25.0
const _LOG_TAG: String = "Splash"

## 额外传入的待预载资源路径列表
var _warmup_paths: Array[String] = []

## 可选的可视化 Shader 预热清单配置表
var _warmup_config: ShaderWarmupConfig = null

#endregion


#region 生命周期与 BootTask 契约实现

## 构造首屏资源与 Shader 预热任务。[br]
## - [param warmup_paths]：显式指定的预载资源路径数组；[br]
## - [param warmup_config]：可选的 [ShaderWarmupConfig] 资源清单（支持目录扫描与 `.tscn` 内嵌材质剥离）。
func _init(
	warmup_paths: Array[String] = [],
	warmup_config: ShaderWarmupConfig = null
) -> void:
	_warmup_paths = warmup_paths.duplicate()
	_warmup_config = warmup_config


func get_task_id() -> StringName:
	return _TASK_ID


func get_task_title() -> String:
	return _TASK_TITLE


func get_weight() -> float:
	return _TASK_WEIGHT


func get_failure_policy() -> FailurePolicy:
	return FailurePolicy.OPTIONAL


## 执行「多线程磁盘预载 ➔ 自适应分帧 GPU PSO 烘烤」两阶段流水线。
func execute(context: SplashBootContext) -> Result:
	if App == null or App.asset == null:
		return Result.ok()

	# 1. 收集所有待预热的外部资源路径（去重合并显式路径与 ShaderWarmupConfig 扫描路径）
	var valid_paths: Array[String] = []
	var seen_paths: Dictionary = {}

	for path: String in _warmup_paths:
		if not path.is_empty() and ResourceLoader.exists(path) and not seen_paths.has(path):
			seen_paths[path] = true
			valid_paths.append(path)

	if _warmup_config != null:
		for cfg_path: String in _warmup_config.collect_all_paths():
			if not seen_paths.has(cfg_path):
				seen_paths[cfg_path] = true
				valid_paths.append(cfg_path)

	# 2. 阶段一：利用 App.asset 双阶段真并发将磁盘资源读入内存，并按需 Pin 住常驻着色器/材质
	var resources_to_bake: Array[Resource] = []
	if _warmup_config != null:
		for direct_res: Resource in _warmup_config.warmup_resources:
			if direct_res != null:
				resources_to_bake.append(direct_res)

	if not valid_paths.is_empty():
		var batch_res: Result = await App.asset.preload_batch(valid_paths)
		if batch_res.is_ok() and batch_res.value is Dictionary:
			var loaded_map: Dictionary = batch_res.value as Dictionary
			var should_pin: bool = _warmup_config == null or _warmup_config.pin_in_asset_cache
			for loaded_path: Variant in loaded_map:
				var res_obj: Variant = loaded_map[loaded_path]
				if res_obj is Resource:
					resources_to_bake.append(res_obj as Resource)
					if should_pin and (res_obj is Shader or res_obj is Material):
						App.asset.pin(str(loaded_path))

	# 3. 阶段二：交由 ShaderWarmer 执行零实例化 SceneState 穿透剥离与自适应分帧 GPU PSO 烘烤
	if not resources_to_bake.is_empty():
		var budget_ms: float = (
			_warmup_config.frame_budget_ms
			if _warmup_config != null
			else ShaderWarmer.DEFAULT_FRAME_BUDGET_MS
		)
		var report: ShaderWarmupReport = await ShaderWarmer.warmup_resources_async(
			App,
			resources_to_bake,
			budget_ms
		)
		if context != null:
			context.set_extra("shader_warmup_report", report.to_dict())
		if App.logger != null:
			App.logger.info(_LOG_TAG, report.get_summary_text())

	return Result.ok()

#endregion
