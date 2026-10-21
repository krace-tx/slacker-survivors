@abstract
class_name BootTask
extends RefCounted

## 业务启动管线任务抽象基类（位于 src/game/features/splash/service/）。[br]
##
## [b]核心设计：[/b][br]
## 1. [b]声明式权重与容灾策略[/b]：每个启动任务声明自身的进度权重（[method get_weight]）与故障处理策略（[enum FailurePolicy]）；[br]
## 2. [b]三级容灾降级机制[/b]：[br]
##    - [constant FailurePolicy.CRITICAL]：关键任务（如静态表校验、本地存档迁移保护），失败时挂起管线并开放断点重试；[br]
##    - [constant FailurePolicy.DEGRADABLE]：可降级任务（如远端权威时钟校准、云会话探测），失败时记录告警并自动切换离线模式继续启动；[br]
##    - [constant FailurePolicy.OPTIONAL]：可选优化任务（如非阻塞资源预热），失败时静默忽略，绝不阻断进游。

enum FailurePolicy {
	CRITICAL = 0,   ## 致命阻断：失败时中止启动管线，等待触发断点重试
	DEGRADABLE = 1, ## 优雅降级：失败时记录告警至 SplashBootContext.warnings 并降级继续
	OPTIONAL = 2,   ## 可选优化：失败时静默忽略并继续后续启动
}


## 获取任务唯一标识（如 &"load_config"）
@abstract
func get_task_id() -> StringName


## 获取任务展示文案（用于加载进度条状态提示）
@abstract
func get_task_title() -> String


## 获取任务在整体启动进度中的权重（默认 20.0）
func get_weight() -> float:
	return 20.0


## 获取任务失败时的容灾策略（默认 CRITICAL）
func get_failure_policy() -> FailurePolicy:
	return FailurePolicy.CRITICAL


## 执行该启动任务的具体异步逻辑
@abstract
func execute(context: SplashBootContext) -> Result
