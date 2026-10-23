class_name SoulsBlueprintDialog
extends Control

## 享元行为树 AST 蓝图与内核自检日志独立弹窗（位于 src/test/souls_arena/view/component/blueprint_dialog/，遵循 MSVP 的 `Component` 规范）。[br]
##
## [b]核心设计：[/b][br]
## 1. 完整节点树、SVG 纹章图标与 [`SoulsAstBlueprintView`](file:///d:/code/GodotProject/slacker-survivors/src/test/souls_arena/view/component/blueprint_dialog/souls_ast_blueprint_view.tscn) 子场景均直接构建于 [`souls_blueprint_dialog.tscn`](file:///d:/code/GodotProject/slacker-survivors/src/test/souls_arena/view/component/blueprint_dialog/souls_blueprint_dialog.tscn)，脚本零 `.new()` 动态拼装；[br]
## 2. 按 `B` 或 `Tab` 键、或点击右上角 `[B] AST 蓝图` 按钮即可随时开关。


#region 信号定义

signal close_requested()
signal rerun_verification_requested()

#endregion


#region 场景唯一节点绑定 (%UniqueName)

@onready var _backdrop: ColorRect = %Backdrop as ColorRect
@onready var _ast_view: SoulsAstBlueprintView = %AstBlueprintView as SoulsAstBlueprintView
@onready var _log_rt: RichTextLabel = %LogRichText as RichTextLabel
@onready var _summary_label: Label = %SummaryLabel as Label
@onready var _rerun_btn: Button = %RerunBtn as Button
@onready var _close_btn: Button = %CloseBtn as Button

#endregion


#region 生命周期与输入处理

func _ready() -> void:
	if _backdrop != null:
		_backdrop.gui_input.connect(_on_backdrop_gui_input)
	if _rerun_btn != null:
		_rerun_btn.pressed.connect(func() -> void: rerun_verification_requested.emit())
	if _close_btn != null:
		_close_btn.pressed.connect(func() -> void: close_requested.emit())


func _on_backdrop_gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb: InputEventMouseButton = ev as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			close_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event as InputEventKey
		if (
			key_event.keycode == KEY_ESCAPE
			or key_event.keycode == KEY_B
			or key_event.keycode == KEY_TAB
		):
			get_viewport().set_input_as_handled()
			close_requested.emit()

#endregion


#region 外部刷新接口

## 绑定 Boss 的 BTGraphDef 与玩家的 FsmGraphDef 至 AST 蓝图组件
func bind_ast_graphs(
	bt_graph: BTGraphDef,
	bt_blackboard: BTBlackboard,
	fsm_graph: FsmGraphDef
) -> void:
	if _ast_view != null:
		_ast_view.bind_ast_graphs(bt_graph, bt_blackboard, fsm_graph)


## 根据实时状态刷新高亮分支与测试统计摘要
func refresh_from_state(state: SoulsArenaState) -> void:
	if state == null:
		return
	if _ast_view != null:
		_ast_view.update_live_state(state.player_fsm_state, state.boss_bt_leaf)
	if _summary_label != null:
		_summary_label.text = "自检 %d / %d 通过" % [
			state.passed_cases,
			state.total_cases,
		]


## 重新渲染完整日志列表
func render_all_logs(lines: PackedStringArray) -> void:
	if _log_rt == null:
		return
	_log_rt.clear()
	for line: String in lines:
		_log_rt.append_text(line + "\n")


## 增量追加单行 BBCode 日志
func append_log_line(bbcode_line: String) -> void:
	if _log_rt != null:
		_log_rt.append_text(bbcode_line + "\n")

#endregion
