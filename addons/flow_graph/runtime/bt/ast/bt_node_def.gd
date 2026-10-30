@tool
class_name BTNodeDef
extends Resource

## 行为树单个节点的抽象语法树描述子（Behavior Tree AST Node Definition）。[br]
##
## 纯数据结构（可保存为 `.tres` 或与 JSON `Dictionary` 互转），作为连接「纯代码 `BTBuilder` / 可视化蓝图画布」与「享元运行内核 `BTNode`」的中间表示（IR）。

#region Exports
## 节点在树中的唯一整数拓扑 ID。
@export var node_id: int = 0

## 节点类型标识（如 `&"Selector"`, `&"Sequence"`, `&"Parallel"`, `&"Inverter"`, `&"Cooldown"`, `&"Condition"`, `&"Action"`, `&"Wait"`）。
@export var node_type: StringName = &"Action"

## 节点在可视化蓝图上的可读标题。
@export var title: String = ""

## 节点静态参数字典（如 `{"cooldown_sec": 4.0}`、`{"key": "hp_ratio", "op": "<=", "value": 0.5}`、`{"action_key": "boss.slash"}`）。
@export var params: Dictionary = {}

## 子节点 AST 列表（元素类型为 `BTNodeDef`，使用无环类型声明避免 Godot 4 GDScript 自引用 Script 计数环）。
@export var children: Array = []

## 可视化蓝图编辑器中的节点坐标（运行时忽略）。
@export var editor_pos: Vector2 = Vector2.ZERO
#endregion

#region Transient Debug Metadata
## 仅运行期/调试期记录该节点在业务 GDScript 中构建或注册算子的脚本路径（不落盘至 `.tres`）。
var debug_source_file: String = ""
## 仅运行期/调试期记录该节点在业务 GDScript 中的行号。
var debug_source_line: int = 0
#endregion


#region Factory & Serialization
static func create(
	p_node_id: int,
	p_node_type: StringName,
	p_title: String = "",
	p_params: Dictionary = {},
	p_editor_pos: Vector2 = Vector2.ZERO
) -> BTNodeDef:
	var def := BTNodeDef.new()
	def.node_id = p_node_id
	def.node_type = p_node_type
	def.title = p_title if not p_title.is_empty() else String(p_node_type)
	def.params = p_params.duplicate(true)
	def.editor_pos = p_editor_pos
	return def


func to_dict() -> Dictionary:
	var child_dicts: Array[Dictionary] = []
	for ch_var: Variant in children:
		var ch := ch_var as BTNodeDef
		if ch != null:
			child_dicts.append(ch.to_dict())
	return {
		"node_id": node_id,
		"node_type": String(node_type),
		"title": title,
		"params": params.duplicate(true),
		"editor_pos": [editor_pos.x, editor_pos.y],
		"children": child_dicts,
	}


static func from_dict(data: Dictionary) -> BTNodeDef:
	var def := BTNodeDef.new()
	def.node_id = int(data.get("node_id", 0))
	def.node_type = StringName(str(data.get("node_type", "Action")))
	def.title = str(data.get("title", String(def.node_type)))
	var raw_params: Variant = data.get("params", {})
	if raw_params is Dictionary:
		def.params = (raw_params as Dictionary).duplicate(true)
	var raw_pos: Variant = data.get("editor_pos", [])
	if raw_pos is Array and (raw_pos as Array).size() >= 2:
		def.editor_pos = Vector2(float(raw_pos[0]), float(raw_pos[1]))
	var raw_children: Variant = data.get("children", [])
	if raw_children is Array:
		for c_item: Variant in raw_children as Array:
			if c_item is Dictionary:
				def.children.append(BTNodeDef.from_dict(c_item as Dictionary))
	return def
#endregion
