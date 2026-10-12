class_name BaseBootStep
extends RefCounted

## 业务启动微任务抽象基类 (Boot Step)。[br]
## 将业务启动阶段拆解为高内聚、单一职责的微步骤（配置、存档、设置、状态）。


## 获取步骤名称与描述
func get_step_name() -> String:
	return "BaseStep"


## 执行具体的业务步骤逻辑
## [param context] 启动上下文对象
## @return 返回 Result 封装
func execute(_context: BootContext) -> Result:
	return Result.ok()
