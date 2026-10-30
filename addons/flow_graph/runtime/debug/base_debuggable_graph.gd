@tool
class_name BaseDebuggableGraph
extends RefCounted

## 通用可调试流转图抽象基类（供未来 GOAP、效用 AI、伤害结算管线、任务 DAG 等复杂算法继承）。[br]
##
## [b]核心设计：[/b][br]
## 1. 算法子类只需发射 [signal edge_traversed] 信号并重写三个纯 `Dictionary` 协议方法，即可被 [GraphDebugBridge] 自动识别基类并接入编辑器可视化画布；[br]
## 2. 零 UI 与零插件反向依赖，正式版构建下不产生任何额外运行时负担。


#region 信号定义

## 当算法内部发生节点切换或有向边流转时发射，驱动画布实时流光动画。
signal edge_traversed(from_node_id: StringName, to_node_id: StringName, edge_label: String)

## 当静态图拓扑发生结构变化时发射，通知画布增量重建。
signal topology_changed()

#endregion


#region 子类可重写协议钩子

## 导出图拓扑字典：`{"diagram_type": "flowchart"|"stateDiagram-v2", "direction": "TD"|"LR", "initial_node_id": "", "nodes": [...], "edges": [...]}`。
func _export_graph_dict() -> Dictionary:
	return {
		"diagram_type": "flowchart",
		"direction": "LR",
		"initial_node_id": "",
		"nodes": [],
		"edges": [],
	}


## 采集当前帧状态快照：`{"active_nodes": {node_id: {"state": "RUNNING"|"SUCCESS"|"FAILURE", "badge": ""}}, "vars": {...}}`。
func _capture_frame_dict() -> Dictionary:
	return {
		"active_nodes": {},
		"vars": {},
	}


## 响应编辑器画布下发的交互式测试指令（如 `&"force_node"`、`&"set_var"`）。
func _on_debug_command(_command: StringName, _payload: Dictionary) -> bool:
	return false

#endregion
