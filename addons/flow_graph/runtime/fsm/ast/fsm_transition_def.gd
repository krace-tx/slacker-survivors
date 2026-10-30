@tool
class_name FsmTransitionDef
extends Resource

## 状态机有向转换边的抽象语法树描述子（FSM Transition AST Edge Definition）。[br]
##
## 支持「脉冲事件触发 (`trigger_event`)」、「条件谓词/表达式 (`condition_key` / `bb_expr`)」与「驻留时长 (`min_state_time`)」组合语义。

#region Constants & Exports
## 通配任意来源状态的特殊标识（如 `ANY -> dead`）。
const ANY_STATE: StringName = &"*"

## 起始状态 ID（传 `&"*"` 表示从任意状态均可触发）。
@export var from_state: StringName = &""

## 目标状态 ID。
@export var to_state: StringName = &""

## 条件函数标识或布尔表达式（支持 `!` 前缀取反及 `&& / ||` 组合）。
@export var condition_key: StringName = &""

## 可选：触发该转换所需的帧内脉冲事件名（由 [method StateMachine.fire_event] 发射）。
@export var trigger_event: StringName = &""

## 可选：黑板轻量布尔比较表达式（如 `"hp_ratio <= 0.3 && !shielded"`）。
@export var bb_expr: String = ""

## 触发该转换所需在当前状态至少停留的秒数（`<= 0.0` 表示立即评估，无需等待）。
@export var min_state_time: float = 0.0

## 多条边同时满足时的裁决优先级（数值越大越优先）。
@export var priority: int = 0

## 可视化蓝图连线上的可读说明文字。
@export var description: String = ""
#endregion


#region Factory & Serialization
static func create(
	p_from: StringName,
	p_to: StringName,
	p_condition_key: StringName = &"",
	p_priority: int = 0,
	p_min_state_time: float = 0.0,
	p_description: String = "",
	p_trigger_event: StringName = &"",
	p_bb_expr: String = ""
) -> FsmTransitionDef:
	var def := FsmTransitionDef.new()
	def.from_state = p_from
	def.to_state = p_to
	def.condition_key = p_condition_key
	def.priority = p_priority
	def.min_state_time = p_min_state_time
	def.description = p_description
	def.trigger_event = p_trigger_event
	def.bb_expr = p_bb_expr
	return def


func to_dict() -> Dictionary:
	return {
		"from_state": String(from_state),
		"to_state": String(to_state),
		"condition_key": String(condition_key),
		"trigger_event": String(trigger_event),
		"bb_expr": bb_expr,
		"min_state_time": min_state_time,
		"priority": priority,
		"description": description,
	}


static func from_dict(data: Dictionary) -> FsmTransitionDef:
	return FsmTransitionDef.create(
		StringName(str(data.get("from_state", ""))),
		StringName(str(data.get("to_state", ""))),
		StringName(str(data.get("condition_key", ""))),
		int(data.get("priority", 0)),
		float(data.get("min_state_time", 0.0)),
		str(data.get("description", "")),
		StringName(str(data.get("trigger_event", ""))),
		str(data.get("bb_expr", ""))
	)
#endregion
