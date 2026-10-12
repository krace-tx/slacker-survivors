class_name GameService
extends RefCounted

## MSVP 架构 · 业务服务层基类 (Service)。[br]
##
## 职责：[br]
## 1. 负责纯粹的领域业务逻辑、数学运算、数值公式、玩法规则校验；[br]
## 2. 协调调用底层基础设施（通过 [code]App.storage[/code]、[code]App.net[/code] 等门面）；[br]
## 3. 驱动与修改对应模块的 [GameModel] 数据，绝对严禁直接操作 View 节点；[br]
## 4. 可失败业务统一返回 [Result] 结构，保障错误处理可预测。


## 打印模块调试日志
func log_info(module_name: String, message: String) -> void:
	if App != null and App.logger != null:
		App.logger.info(module_name, message)
	else:
		print("[%s] %s" % [module_name, message])


## 打印模块告警日志
func log_warn(module_name: String, message: String) -> void:
	if App != null and App.logger != null:
		App.logger.warn(module_name, message)
	else:
		push_warning("[%s] %s" % [module_name, message])


## 打印模块错误日志
func log_error(module_name: String, message: String) -> void:
	if App != null and App.logger != null:
		App.logger.error(module_name, message)
	else:
		push_error("[%s] %s" % [module_name, message])
