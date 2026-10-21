class_name SplashBootContext
extends BaseParams

## 业务启动管线共享上下文与耗时瀑布诊断报告（位于 src/game/features/splash/model/）。[br]
##
## [b]核心设计（遵循 `*Context` 领域后缀规范）：[/b][br]
## 1. [b]强类型契约持有[/b]：继承自 [BaseParams]，显式声明核心领域模型（[member game_settings]、[member player_profile]）
##    与启动状态标志（[member is_first_launch]、[member is_offline_mode]）；[br]
## 2. [b]智能路由目标承载[/b]：持有终局路由裁决结果（[member target_scene_path] 与 [member target_scene_params]）；[br]
## 3. [b]全链路瀑布耗时与降级审计[/b]：汇总各启动任务的毫秒级耗时（[member task_metrics_ms]）与可降级任务告警（[member warnings]）。

#region Core Domain Models
## 已加载并应用的全局偏好设置模型
var game_settings: GameSettingsModel = null
## 已加载或新建的玩家持久化基础档案模型
var player_profile: PlayerProfileModel = null
#endregion

#region Boot State Flags
## 是否为新玩家首次启动建档（可供上层模块判定是否触发首次引导）
var is_first_launch: bool = false
## 是否处于离线降级模式（当远端时间同步或网络会话探测不可达时自动置为 true）
var is_offline_mode: bool = false
#endregion

#region Route Resolution
## 外部指定的强制直达目标场景路径（如开发测试或 DeepLink 覆盖）
var override_target_scene: String = ""
## 外部指定的透传给最终目标场景的强类型参数
var override_target_params: BaseParams = null
## 终局路由裁决器（[ResolveRouteTask]）决定的最终跳转场景路径
var target_scene_path: String = ""
## 终局路由传递给目标场景的强类型参数包
var target_scene_params: BaseParams = null
#endregion

#region Diagnostics & Metrics
## 启动管线开始时间戳（毫秒）
var start_time_ms: int = 0
## 启动管线结束时间戳（毫秒）
var end_time_ms: int = 0
## 启动总耗时（毫秒）
var total_boot_ms: int = 0
## 各子任务毫秒耗时瀑布字典：`{ task_id: duration_ms }`
var task_metrics_ms: Dictionary = {}
## 可降级任务产生的非致命告警列表
var warnings: Array[String] = []
## 扩展自定义键值数据
var extra_data: Dictionary = {}
#endregion


#region Public API
func _init(dict: Dictionary = {}) -> void:
	start_time_ms = Time.get_ticks_msec()
	super._init(dict)


## 记录单个启动任务的执行耗时（毫秒）
func record_task_metric(task_id: StringName, duration_ms: int) -> void:
	task_metrics_ms[String(task_id)] = maxi(0, duration_ms)


## 记录一条降级告警信息
func add_warning(task_id: StringName, message: String) -> void:
	warnings.append("[%s] %s" % [String(task_id), message])


## 写入扩展自定义数据
func set_extra(key: String, value: Variant) -> void:
	extra_data[key] = value


## 读取扩展自定义数据
func get_extra(key: String, default_value: Variant = null) -> Variant:
	return extra_data.get(key, default_value)


## 标记整个启动管线完成并结算总耗时（毫秒）
func mark_finished() -> int:
	end_time_ms = Time.get_ticks_msec()
	total_boot_ms = maxi(0, end_time_ms - start_time_ms)
	return total_boot_ms


## 导出结构化启动诊断摘要字典
func get_diagnostics_summary() -> Dictionary:
	return {
		"total_boot_ms": total_boot_ms,
		"is_first_launch": is_first_launch,
		"is_offline_mode": is_offline_mode,
		"target_scene_path": target_scene_path,
		"tasks_ms": task_metrics_ms.duplicate(),
		"warnings": warnings.duplicate(),
	}
#endregion
