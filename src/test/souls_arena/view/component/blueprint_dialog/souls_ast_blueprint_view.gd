class_name SoulsAstBlueprintView
extends VBoxContainer

## 享元行为树与有限状态机 AST 蓝图实时监视组件（位于 src/test/souls_arena/view/component/blueprint_dialog/，遵循 MSVP 的 `Component` 规范）。[br]
##
## [b]核心职责：[/b][br]
## 1. 节点层级直接构建于 [`souls_ast_blueprint_view.tscn`](file:///d:/code/GodotProject/slacker-survivors/src/test/souls_arena/view/component/blueprint_dialog/souls_ast_blueprint_view.tscn)，零脚本 `.new()` 动态拼装；[br]
## 2. 解析 `BTGraphDef` 与 `FsmGraphDef`，实时高亮激活节点与 `BTBlackboard` 遥测数据。


#region 场景唯一节点绑定与缓存

@onready var _tree_rt: RichTextLabel = %TreeRichText as RichTextLabel
@onready var _blackboard_rt: RichTextLabel = %BlackboardRichText as RichTextLabel

var _bt_graph: BTGraphDef = null
var _bt_blackboard: BTBlackboard = null
var _fsm_graph: FsmGraphDef = null

var _last_bt_leaf: StringName = &""
var _last_fsm_state: StringName = &""

#endregion


#region 外部绑定与刷新接口

func bind_ast_graphs(
	bt_graph: BTGraphDef,
	bt_blackboard: BTBlackboard,
	fsm_graph: FsmGraphDef
) -> void:
	_bt_graph = bt_graph
	_bt_blackboard = bt_blackboard
	_fsm_graph = fsm_graph
	_render_ast_trees(_last_fsm_state, _last_bt_leaf)


func update_live_state(player_fsm_state: StringName, boss_bt_leaf: StringName) -> void:
	if (
		_last_fsm_state != player_fsm_state
		or _last_bt_leaf != boss_bt_leaf
		or (_tree_rt != null and _tree_rt.text.is_empty())
	):
		_last_fsm_state = player_fsm_state
		_last_bt_leaf = boss_bt_leaf
		_render_ast_trees(player_fsm_state, boss_bt_leaf)

	if _blackboard_rt != null:
		var dist_val: float = 0.0
		var staggered_val: bool = false
		if _bt_blackboard != null:
			dist_val = _bt_blackboard.get_float(&"distance_to_player", 0.0)
			staggered_val = _bt_blackboard.get_bool(&"is_staggered", false)
		_blackboard_rt.text = "\n".join([
			"[b][color=#ffd875]黑板遥测 (BTBlackboard)[/color][/b]",
			"  Boss 叶节点: [color=#52ff9a]%s[/color]    玩家状态: [color=#7ce8ff]%s[/color]" % [
				String(boss_bt_leaf),
				SoulsArenaState.get_fsm_state_cn_name(player_fsm_state),
			],
			"  间距: [color=#9df08e]%.2fm[/color]    破防可处决: %s" % [
				dist_val,
				"是" if staggered_val else "否",
			],
		])

#endregion


#region 递归渲染 AST 语法树

func _render_ast_trees(active_fsm_state: StringName, active_bt_leaf: StringName) -> void:
	if _tree_rt == null:
		return
	var lines: Array[String] = []

	lines.append("[b][color=#ffd875][BTGraphDef] Boss 行为树[/color][/b]")
	if _bt_graph != null and _bt_graph.root != null:
		_append_bt_node_lines(_bt_graph.root, 0, active_bt_leaf, lines)
	else:
		lines.append("  [color=#8892a4](未绑定)[/color]")

	lines.append("")
	lines.append("[b][color=#7ce8ff][FsmGraphDef] 角色状态机[/color][/b]")
	if _fsm_graph != null:
		var state_tags: PackedStringArray = PackedStringArray()
		for st_def: FsmStateDef in _fsm_graph.states:
			if st_def == null:
				continue
			if st_def.state_id == active_fsm_state:
				state_tags.append("[b][color=#52ff9a][%s][/color][/b]" % String(st_def.state_id))
			else:
				state_tags.append("[color=#7e92b2]%s[/color]" % String(st_def.state_id))
		lines.append("  " + " · ".join(state_tags))
	else:
		lines.append("  [color=#8892a4](未绑定)[/color]")

	_tree_rt.text = "\n".join(lines)


func _append_bt_node_lines(
	node_def: BTNodeDef,
	depth: int,
	active_leaf: StringName,
	out_lines: Array[String]
) -> void:
	if node_def == null:
		return
	var indent := "  ".repeat(depth)
	var prefix := "└─ " if depth > 0 else ""
	var n_type: String = String(node_def.node_type)
	var action_key: String = str(node_def.params.get("action_key", ""))
	var is_active: bool = (not action_key.is_empty()) and (StringName(action_key) == active_leaf)

	var type_color := "#8cb4ff"
	if n_type in ["Selector", "Sequence", "Parallel"]:
		type_color = "#ffd875"
	elif n_type in ["Condition", "Cooldown", "Inverter"]:
		type_color = "#c59bff"
	elif n_type == "Action":
		type_color = "#7ce8ff"

	if is_active:
		out_lines.append(
			"%s%s[b][color=#52ff9a]> [%s] %s[/color][/b]" % [
				indent,
				prefix,
				n_type,
				node_def.title,
			]
		)
	else:
		out_lines.append(
			"%s%s[color=%s][%s][/color] %s" % [
				indent,
				prefix,
				type_color,
				n_type,
				node_def.title,
			]
		)

	for child_var: Variant in node_def.children:
		var child_def := child_var as BTNodeDef
		if child_def != null:
			_append_bt_node_lines(child_def, depth + 1, active_leaf, out_lines)

#endregion
