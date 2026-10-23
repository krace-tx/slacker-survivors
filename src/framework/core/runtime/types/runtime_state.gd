class_name RuntimeState
extends RefCounted

## FrameworkRuntime 生命周期状态枚举与状态机流转契约。

enum Value {
	UNINITIALIZED,          ## 尚未初始化
	INITIALIZING,           ## 正在按拓扑顺序装配模块
	READY,                  ## 全部核心模块已就绪
	INITIALIZATION_FAILED,  ## 某模块装配失败
	ROLLING_BACK,           ## 正在逆序回滚已创建模块
	SHUTTING_DOWN,          ## 正在按逆序执行优雅关闭
	STOPPED,                ## 已完全停止并释放
}

## 合法状态流转邻接表
const VALID_TRANSITIONS: Dictionary = {
	Value.UNINITIALIZED: [
		Value.INITIALIZING,
		Value.INITIALIZATION_FAILED,
		Value.STOPPED,
	],
	Value.INITIALIZING: [
		Value.READY,
		Value.INITIALIZATION_FAILED,
		Value.SHUTTING_DOWN,
	],
	Value.READY: [
		Value.SHUTTING_DOWN,
	],
	Value.INITIALIZATION_FAILED: [
		Value.ROLLING_BACK,
		Value.STOPPED,
	],
	Value.ROLLING_BACK: [
		Value.STOPPED,
	],
	Value.SHUTTING_DOWN: [
		Value.STOPPED,
	],
	Value.STOPPED: [
		Value.INITIALIZING,
	],
}


## 将状态枚举值转换为可读字符串名称。
static func to_name(state: Value) -> String:
	var keys := Value.keys()
	var idx := int(state)
	if idx >= 0 and idx < keys.size():
		return keys[idx]
	return "UNKNOWN"


## 校验从 [param from_state] 到 [param to_state] 的状态流转是否合法。
static func can_transition(from_state: Value, to_state: Value) -> bool:
	if from_state == to_state:
		return true
	var allowed: Array = VALID_TRANSITIONS.get(from_state, [])
	return allowed.has(to_state)


## 当前状态是否处于不可重入的异步过渡态（正在启动、正在回滚或正在停机）。
static func is_busy(state: Value) -> bool:
	return (
		state == Value.INITIALIZING
		or state == Value.ROLLING_BACK
		or state == Value.SHUTTING_DOWN
	)


## 当前状态是否已处于静止终态（未初始化或已完全停止）。
static func is_stopped_or_uninitialized(state: Value) -> bool:
	return state == Value.STOPPED or state == Value.UNINITIALIZED

