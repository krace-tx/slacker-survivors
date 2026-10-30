class_name SlimeBtSquad
extends RefCounted

## 【标准范例 ②】基于 [BTGraphDef] `.tres` 蓝图编译享元行为树（1 棵 [BTTree] 同时驱动多实体）。[br]
##
## [b]架构示范：[/b][br]
## 1. **Flyweight 享元复用**：[BTGraphDef] 仅编译生成唯一一棵无状态 [BTTree]，同时驱动 `Alpha` 与 `Bravo` 两只史莱姆；[br]
## 2. **零样板条件节点**：黑板比较（`hp_ratio <= 0.3`、`enemy_dist <= 160`）、`Cooldown(3.0s)` 与 `Wait(0.6s)` 均由框架内置驱动，本类仅实现 3 个叶动作函数；[br]
## 3. **可视化一键跳回**：在 Mermaid 画布点击叶节点并点「跳转代码」，编辑器直接定位至下方 `register_action` 对应行。


#region Signals & Constants

signal action_executed(unit_tag: String, summary: String)

const _KEY_UNIT_TAG: StringName = &"unit_tag"
const _KEY_HP_RATIO: StringName = &"hp_ratio"
const _KEY_ENEMY_DIST: StringName = &"enemy_dist"

#endregion


#region Public Readout & Private State

var alpha_summary: String = "待命"
var bravo_summary: String = "待命"

var _shared_tree: BTTree = null
var _alpha_ctx: BTContext = null
var _bravo_ctx: BTContext = null
var _alpha_debug_id: int = 0
var _bravo_debug_id: int = 0

#endregion


#region Lifecycle & Setup

## 编译 [param blueprint] 为共享 [BTTree]，创建双实体 [BTContext] 并挂载至 [GraphDebugBridge]。
func setup(host_owner: Object, blueprint: BTGraphDef) -> Result:
	if blueprint == null:
		return Result.err_code("MermaidTest.NullBtBlueprint", "Slime BT blueprint is null.")

	var graph_ast: BTGraphDef = blueprint.duplicate(true) as BTGraphDef
	var compiler := BTCompiler.new()

	# 1. 注册叶节点动作算子（自动捕获当前源码行号供 Mermaid 画布一键跳转）
	compiler.register_action(&"flee_recover", _action_flee_recover)
	compiler.register_action(&"dash_strike", _action_dash_strike)
	compiler.register_action(&"patrol_wander", _action_patrol_wander)

	# 2. 编译为无状态享元 BTTree
	var compile_res: FlowGraphResult = compiler.compile(graph_ast)
	if compile_res.is_err():
		return Result.err_code(compile_res.error_code(), compile_res.error_message())
	_shared_tree = compile_res.value as BTTree

	# 3. 为每只怪物创建独立黑板上下文，共享同一棵 _shared_tree
	_alpha_ctx = BTContext.new(host_owner, {
		"unit_tag": "A",
		"hp_ratio": 0.85,
		"enemy_dist": 115.0,
	})
	_bravo_ctx = BTContext.new(host_owner, {
		"unit_tag": "B",
		"hp_ratio": 0.22,
		"enemy_dist": 240.0,
	})

	_alpha_debug_id = GraphDebugBridge.register_bt(_shared_tree, _alpha_ctx, host_owner, "史莱姆A_近战态")
	_bravo_debug_id = GraphDebugBridge.register_bt(_shared_tree, _bravo_ctx, host_owner, "史莱姆B_残血态")
	return Result.ok(self)


## 每帧使用同一棵享元 [BTTree] 依次驱动两个独立实体上下文。
func tick(delta: float) -> void:
	if _shared_tree == null:
		return
	if _alpha_ctx != null:
		_shared_tree.tick(_alpha_ctx, delta)
	if _bravo_ctx != null:
		_shared_tree.tick(_bravo_ctx, delta)


## 释放运行期调试句柄与行为树闭包引用。
func dispose() -> void:
	GraphDebugBridge.unregister(_alpha_debug_id)
	GraphDebugBridge.unregister(_bravo_debug_id)
	_alpha_debug_id = 0
	_bravo_debug_id = 0
	if _shared_tree != null:
		_shared_tree.clear()
		_shared_tree = null
	_alpha_ctx = null
	_bravo_ctx = null

#endregion


#region Domain Controls & Queries

func get_shared_tree() -> BTTree:
	return _shared_tree


func get_alpha_context() -> BTContext:
	return _alpha_ctx


func get_bravo_context() -> BTContext:
	return _bravo_ctx


func damage_alpha(ratio_delta: float = 0.35) -> float:
	if _alpha_ctx == null:
		return 0.0
	var next_hp: float = snappedf(maxf(0.10, _alpha_ctx.blackboard.get_float(_KEY_HP_RATIO, 0.85) - ratio_delta), 0.01)
	_alpha_ctx.blackboard.set_var(_KEY_HP_RATIO, next_hp)
	return next_hp


func heal_alpha_full() -> float:
	if _alpha_ctx == null:
		return 0.0
	_alpha_ctx.blackboard.set_var(_KEY_HP_RATIO, 0.90)
	return 0.90


func toggle_alpha_distance() -> float:
	if _alpha_ctx == null:
		return 0.0
	var cur_d: float = _alpha_ctx.blackboard.get_float(_KEY_ENEMY_DIST, 115.0)
	var next_d: float = 250.0 if cur_d <= 160.0 else 115.0
	_alpha_ctx.blackboard.set_var(_KEY_ENEMY_DIST, next_d)
	return next_d


func toggle_bravo_profile() -> bool:
	if _bravo_ctx == null:
		return false
	var is_low_hp: bool = _bravo_ctx.blackboard.get_float(_KEY_HP_RATIO, 0.22) <= 0.30
	if is_low_hp:
		_bravo_ctx.blackboard.set_var(_KEY_HP_RATIO, 0.95)
		_bravo_ctx.blackboard.set_var(_KEY_ENEMY_DIST, 120.0)
		return true
	_bravo_ctx.blackboard.set_var(_KEY_HP_RATIO, 0.22)
	_bravo_ctx.blackboard.set_var(_KEY_ENEMY_DIST, 240.0)
	return false


## 重置双实体黑板至标准教学初始档案（供重新运行契约自检时恢复确定性基线）。
func reset_to_default_profiles() -> void:
	if _shared_tree != null:
		if _alpha_ctx != null:
			_shared_tree.abort(_alpha_ctx)
		if _bravo_ctx != null:
			_shared_tree.abort(_bravo_ctx)
	if _alpha_ctx != null:
		_alpha_ctx.clear_debug_force_node()
		_alpha_ctx.blackboard.set_var(_KEY_HP_RATIO, 0.85)
		_alpha_ctx.blackboard.set_var(_KEY_ENEMY_DIST, 115.0)
	if _bravo_ctx != null:
		_bravo_ctx.clear_debug_force_node()
		_bravo_ctx.blackboard.set_var(_KEY_HP_RATIO, 0.22)
		_bravo_ctx.blackboard.set_var(_KEY_ENEMY_DIST, 240.0)

#endregion


#region Atomic Leaf Actions

func _action_flee_recover(ctx: BTContext) -> BTStatus.Status:
	var hp: float = ctx.blackboard.get_float(_KEY_HP_RATIO, 0.2)
	_set_unit_summary(ctx, "残血逃跑喘息中 (HP=%d%% <= 30%%)" % roundi(hp * 100.0))
	return BTStatus.Status.RUNNING


func _action_dash_strike(ctx: BTContext) -> BTStatus.Status:
	var tag: String = str(ctx.blackboard.get_var(_KEY_UNIT_TAG, "A"))
	var dist: float = ctx.blackboard.get_float(_KEY_ENEMY_DIST, 115.0)
	var msg: String = "扑击冲刺! (敌距=%.0fm -> 进入 0.6s 收招与 3.0s 冷却)" % dist
	_set_unit_summary(ctx, msg)
	action_executed.emit(tag, msg)
	return BTStatus.Status.SUCCESS


func _action_patrol_wander(ctx: BTContext) -> BTStatus.Status:
	var dist: float = ctx.blackboard.get_float(_KEY_ENEMY_DIST, 200.0)
	_set_unit_summary(ctx, "原地游荡索敌 (敌距=%.0fm 或冲刺冷却中)" % dist)
	return BTStatus.Status.RUNNING


func _set_unit_summary(ctx: BTContext, text: String) -> void:
	if str(ctx.blackboard.get_var(_KEY_UNIT_TAG, "A")) == "A":
		alpha_summary = text
	else:
		bravo_summary = text

#endregion
