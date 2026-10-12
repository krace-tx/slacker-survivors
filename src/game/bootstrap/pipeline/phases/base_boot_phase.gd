class_name BaseBootPhase
extends RefCounted

## 启动阶段抽象基类。[br]
## 每一个启动阶段负责特定范畴的装配与加载任务，并向外广播细粒度步骤与内部进度。

signal step_changed(step_name: String, step_progress: float)


## 获取当前阶段枚举或 ID
func get_phase_id() -> int:
	return 0


## 获取当前阶段可读名称
func get_phase_name() -> String:
	return "BasePhase"


## 执行当前启动阶段。子类必须实现具体的异步加载逻辑。
## [param context] 启动上下文，可用于跨阶段读取或写入共享状态
## @return 返回 Result 封装，若失败则中断启动流水线。
func execute(_context: BootContext) -> Result:
	return Result.ok()
