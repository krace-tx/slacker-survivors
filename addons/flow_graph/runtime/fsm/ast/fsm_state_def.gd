@tool
class_name FsmStateDef
extends Resource

## 状态机单个状态节点的抽象语法树描述子（FSM State AST Node Definition）。[br]
##
## 既可用于保存 `.tres` 状态蓝图配置，也可由代码态 [StateMachine] 自动导出供可视化画布渲染。

#region Exports
## 状态唯一标识（如 `&"idle"`、`&"dodge_roll"`、`&"guard_parry"`）。
@export var state_id: StringName = &""

## 状态在可视化蓝图画布上的可读名称。
@export var title: String = ""

## 绑定到状态注册表中的动作标识（为空时默认与 `state_id` 同名）。
@export var action_key: StringName = &""

## 可选：嵌套子状态机 `.tres` 资源路径（HFSM 层次状态机自动挂载）。
@export var sub_graph_path: String = ""

## 状态静态配置参数字典（如消耗精力、无敌帧时长等）。
@export var params: Dictionary = {}

## 可视化蓝图编辑器中的节点坐标（运行时忽略）。
@export var editor_pos: Vector2 = Vector2.ZERO
#endregion

#region Transient Debug Metadata
## 仅运行期/调试期记录该状态在业务 GDScript 中注册的脚本路径（不落盘至 `.tres`）。
var debug_source_file: String = ""
## 仅运行期/调试期记录该状态在业务 GDScript 中注册的行号。
var debug_source_line: int = 0
#endregion


#region Factory & Serialization
static func create(
	p_state_id: StringName,
	p_title: String = "",
	p_editor_pos: Vector2 = Vector2.ZERO,
	p_params: Dictionary = {},
	p_sub_graph_path: String = ""
) -> FsmStateDef:
	var def := FsmStateDef.new()
	def.state_id = p_state_id
	def.title = p_title if not p_title.is_empty() else String(p_state_id)
	def.action_key = p_state_id
	def.editor_pos = p_editor_pos
	def.params = p_params.duplicate(true)
	def.sub_graph_path = p_sub_graph_path
	return def


func to_dict() -> Dictionary:
	return {
		"state_id": String(state_id),
		"title": title,
		"action_key": String(action_key),
		"sub_graph_path": sub_graph_path,
		"params": params.duplicate(true),
		"editor_pos": [editor_pos.x, editor_pos.y],
	}


static func from_dict(data: Dictionary) -> FsmStateDef:
	var def := FsmStateDef.new()
	def.state_id = StringName(str(data.get("state_id", "")))
	def.title = str(data.get("title", String(def.state_id)))
	def.action_key = StringName(str(data.get("action_key", String(def.state_id))))
	def.sub_graph_path = str(data.get("sub_graph_path", ""))
	var raw_params: Variant = data.get("params", {})
	if raw_params is Dictionary:
		def.params = (raw_params as Dictionary).duplicate(true)
	var raw_pos: Variant = data.get("editor_pos", [])
	if raw_pos is Array and (raw_pos as Array).size() >= 2:
		var pos_arr: Array = raw_pos as Array
		def.editor_pos = Vector2(float(pos_arr[0]), float(pos_arr[1]))
	return def
#endregion
