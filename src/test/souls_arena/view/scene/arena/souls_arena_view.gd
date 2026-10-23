class_name SoulsArenaView
extends BaseView

## 3D 魂系演练场主视图协调层（位于 src/test/souls_arena/view/scene/arena/，遵循 `BaseView` 规范）。[br]
##
## [b]核心设计理念（模块化子场景解构）：[/b][br]
## 1. [b]主画面极致纯净[/b]：由独立子场景 [SoulsCombatHudBar] 承载顶部 Boss 血条、左下角玩家状态条与右上角操作栏，无右下角案例按钮；[br]
## 2. [b]教学与蓝图彻底拆分[/b]：按 `H` 键打开 [SoulsKeybindHelpDialog]（3D 键位教学与机制指南），按 `B / Tab` 键打开 [SoulsBlueprintDialog]（实时 AST 蓝图与 6 项内核自检日志）。


#region 信号定义

signal toggle_lock_on_requested()
signal toggle_keybind_help_requested(open: bool)
signal toggle_blueprint_requested(open: bool)
signal reset_arena_requested()
signal rerun_verification_requested()

#endregion


#region 子场景组件引用

@onready var _combat_hud: SoulsCombatHudBar = %CombatHudBar as SoulsCombatHudBar
@onready var _keybind_help_dialog: SoulsKeybindHelpDialog = %KeybindHelpDialog as SoulsKeybindHelpDialog
@onready var _blueprint_dialog: SoulsBlueprintDialog = %BlueprintDialog as SoulsBlueprintDialog

#endregion


#region 生命周期

func _ready() -> void:
	super._ready()
	_bind_component_signals()


func _bind_component_signals() -> void:
	if _combat_hud != null:
		_combat_hud.toggle_lock_on_requested.connect(func() -> void: toggle_lock_on_requested.emit())
		_combat_hud.open_keybind_help_requested.connect(func() -> void: toggle_keybind_help_requested.emit(true))
		_combat_hud.open_blueprint_requested.connect(func() -> void: toggle_blueprint_requested.emit(true))
		_combat_hud.reset_duel_requested.connect(func() -> void: reset_arena_requested.emit())

	if _keybind_help_dialog != null:
		_keybind_help_dialog.close_requested.connect(func() -> void: toggle_keybind_help_requested.emit(false))

	if _blueprint_dialog != null:
		_blueprint_dialog.close_requested.connect(func() -> void: toggle_blueprint_requested.emit(false))
		_blueprint_dialog.rerun_verification_requested.connect(func() -> void: rerun_verification_requested.emit())

#endregion


#region 蓝图绑定与视图渲染接口

## 绑定 Boss 的 BTGraphDef 与玩家的 FsmGraphDef 至蓝图弹窗。
func bind_ast_graphs(
	bt_graph: BTGraphDef,
	bt_blackboard: BTBlackboard,
	fsm_graph: FsmGraphDef
) -> void:
	if _blueprint_dialog != null:
		_blueprint_dialog.bind_ast_graphs(bt_graph, bt_blackboard, fsm_graph)


## 根据最新 [SoulsArenaState] 刷新核心 HUD 与两个独立弹窗。
func render_state(state: SoulsArenaState) -> void:
	if state == null:
		return
	if _combat_hud != null:
		_combat_hud.refresh_from_state(state)
	if _keybind_help_dialog != null:
		_keybind_help_dialog.visible = state.is_keybind_help_open
	if _blueprint_dialog != null:
		_blueprint_dialog.visible = state.is_blueprint_open
		if state.is_blueprint_open:
			_blueprint_dialog.refresh_from_state(state)


## 在屏幕中央弹出魂系风格大字号战斗反馈横幅。
func show_combat_banner(bbcode_text: String, duration: float = 1.9) -> void:
	if _combat_hud != null:
		_combat_hud.show_combat_banner(bbcode_text, duration)


## 重新渲染完整日志列表。
func render_all_logs(lines: PackedStringArray) -> void:
	if _blueprint_dialog != null:
		_blueprint_dialog.render_all_logs(lines)


## 增量追加单行 BBCode 日志。
func append_log_line(bbcode_line: String) -> void:
	if _blueprint_dialog != null:
		_blueprint_dialog.append_log_line(bbcode_line)

#endregion
