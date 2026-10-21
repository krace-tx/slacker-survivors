class_name RuntimeState
extends RefCounted

## FrameworkRuntime 生命周期状态枚举与转换辅助。

enum Value {
	UNINITIALIZED,          ## 尚未初始化
	INITIALIZING,           ## 正在按拓扑顺序装配模块
	READY,                  ## 全部核心模块已就绪
	INITIALIZATION_FAILED,  ## 某模块装配失败
	ROLLING_BACK,           ## 正在逆序回滚已创建模块
	SHUTTING_DOWN,          ## 正在按逆序执行优雅关闭
	STOPPED,                ## 已完全停止并释放
}


## 将状态枚举值转换为可读字符串名称。
static func to_name(state: Value) -> String:
	var keys := Value.keys()
	var idx := int(state)
	if idx >= 0 and idx < keys.size():
		return keys[idx]
	return "UNKNOWN"
