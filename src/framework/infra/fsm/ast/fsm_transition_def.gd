class_name FsmTransitionDef
extends Resource

## 状态机有向转换边的抽象语法树描述子（FSM Transition AST Edge Definition）。[br]
##
## 支持「条件谓词触发 (`condition_key`)」与「驻留时长自动触发 (`min_state_time`)」双重转换语义。

#region Constants & Exports
## 通配任意来源状态的特殊标识（如 `ANY -> dead`）。
const ANY_STATE: StringName = &"*"

## 起始状态 ID（传 `&"*"` 表示从任意状态均可触发）。
@export var from_state: StringName = &""

## 目标状态 ID。
@export var to_state: StringName = &""

## 条件函数在注册表中的标识（为空表示无额外条件，仅校验 `min_state_time`）。
@export var condition_key: StringName = &""

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
	p_description: String = ""
) -> FsmTransitionDef:
	var def := FsmTransitionDef.new()
	def.from_state = p_from
	def.to_state = p_to
	def.condition_key = p_condition_key
	def.priority = p_priority
	def.min_state_time = p_min_state_time
	def.description = p_description
	return def


func to_dict() -> Dictionary:
	return {
		"from_state": String(from_state),
		"to_state": String(to_state),
		"condition_key": String(condition_key),
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
		str(data.get("description", ""))
	)
#endregion
