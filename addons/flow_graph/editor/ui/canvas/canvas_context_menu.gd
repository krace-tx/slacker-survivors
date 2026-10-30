@tool
extends RefCounted

## 画布右键上下文菜单构建与命令派发器（Canvas Context Menu Builder & Dispatcher）。[br]
##
## 节点分类浏览已收敛至左侧节点库抽屉；右键菜单保持轻量聚焦：空白处提供快速建点检索、节点库显隐与视图排版，节点与连线处提供原位编辑、插入、反转、断点与强制触发。

signal quick_picker_requested(screen_pos: Vector2i, world_pos: Vector2)
signal node_drawer_toggle_requested()
signal node_rename_requested(node_id: String)
signal node_append_child_requested(node_id: String)
signal node_delete_requested(node_id: String)
signal node_duplicate_requested(node_id: String)
signal nodes_delete_requested(node_ids: Array[String])
signal nodes_duplicate_requested(node_ids: Array[String])
signal initial_node_set_requested(node_id: String)
signal any_state_edge_toggled(node_id: String)
signal breakpoint_toggled(node_id: String)
signal breakpoints_toggle_requested(node_ids: Array[String])
signal sub_graph_open_requested(sub_graph_path: String, node_id: String)
signal node_force_requested(node_id: String, params: Dictionary)
signal edge_inspect_requested(from_id: String, to_id: String)
signal edge_insert_node_requested(screen_pos: Vector2i, world_pos: Vector2, from_id: String, to_id: String)
signal edge_reverse_requested(from_id: String, to_id: String)
signal edge_delete_requested(from_id: String, to_id: String)
signal direction_toggle_requested()
signal auto_layout_requested()
signal fit_view_requested()

const CMD_OPEN_PICKER: int = 100
const CMD_TOGGLE_DRAWER: int = 101
const CMD_TOGGLE_DIR: int = 110
const CMD_AUTO_LAYOUT: int = 111
const CMD_FIT_VIEW: int = 112

const CMD_SET_INITIAL: int = 200
const CMD_TOGGLE_ANY_EDGE: int = 201
const CMD_DUPLICATE_NODE: int = 202
const CMD_DELETE_NODE: int = 203
const CMD_OPEN_SUBGRAPH: int = 204
const CMD_TOGGLE_BREAKPOINT: int = 205
const CMD_FORCE_NODE: int = 206
const CMD_RENAME_NODE: int = 207
const CMD_APPEND_CHILD: int = 208

const CMD_EDGE_INSPECT: int = 240
const CMD_EDGE_INSERT: int = 241
const CMD_EDGE_REVERSE: int = 242
const CMD_EDGE_DELETE: int = 243

var _root_menu: PopupMenu = null
var _pending_screen_pos: Vector2i = Vector2i.ZERO
var _pending_world_pos: Vector2 = Vector2.ZERO
var _pending_node_id: String = ""
var _pending_batch_ids: Array[String] = []
var _pending_node_params: Dictionary = {}
var _pending_sub_graph_path: String = ""
var _pending_edge_from: String = ""
var _pending_edge_to: String = ""


#region 生命周期装配与弹窗唤起

func setup(host_canvas: Control) -> void:
	if host_canvas == null or _root_menu != null:
		return
	_root_menu = PopupMenu.new()
	_root_menu.name = "CanvasContextPopup"
	host_canvas.add_child(_root_menu)
	_root_menu.id_pressed.connect(_on_menu_id_pressed)


func popup_for_blank(
	screen_pos: Vector2i,
	world_pos: Vector2,
	read_only_topology: bool = false,
	ui_scale: float = 1.0
) -> void:
	if _root_menu == null:
		return
	_pending_screen_pos = screen_pos
	_pending_world_pos = world_pos
	_pending_node_id = ""
	_pending_edge_from = ""
	_pending_edge_to = ""
	_apply_menu_scale(ui_scale)
	_root_menu.clear()

	if not read_only_topology:
		_root_menu.add_icon_item(FlowGraphIcons.NODE_ENTRY, FlowEditorI18n.t(&"ctx.open_picker"), CMD_OPEN_PICKER)
	_root_menu.add_icon_item(FlowGraphIcons.TB_LEFT_DRAWER, FlowEditorI18n.t(&"ctx.toggle_drawer"), CMD_TOGGLE_DRAWER)
	_root_menu.add_separator()
	if not read_only_topology:
		_root_menu.add_icon_item(FlowGraphIcons.TB_DIR_SWITCH, FlowEditorI18n.t(&"ctx.toggle_dir"), CMD_TOGGLE_DIR)
		_root_menu.add_icon_item(FlowGraphIcons.TB_AUTO_LAYOUT, FlowEditorI18n.t(&"ctx.auto_layout"), CMD_AUTO_LAYOUT)
	_root_menu.add_icon_item(FlowGraphIcons.TB_FIT_VIEW, FlowEditorI18n.t(&"ctx.fit_view"), CMD_FIT_VIEW)
	_show_popup_at(screen_pos)


func popup_for_node(
	screen_pos: Vector2i,
	node_rec: Dictionary,
	is_fsm: bool,
	read_only_topology: bool,
	live_mode: bool,
	has_breakpoint: bool,
	ui_scale: float = 1.0,
	can_emit_edge: bool = true,
	selected_node_ids: Array[String] = []
) -> void:
	if _root_menu == null or node_rec.is_empty():
		return
	_pending_screen_pos = screen_pos
	_pending_node_id = str(node_rec.get("id", ""))
	if not selected_node_ids.is_empty():
		_pending_batch_ids = selected_node_ids.duplicate()
	else:
		_pending_batch_ids = [_pending_node_id]
	var sel_cnt: int = _pending_batch_ids.size()
	_pending_node_params = (node_rec.get("params", {}) as Dictionary).duplicate(true)
	_pending_sub_graph_path = str(node_rec.get("sub_graph_path", _pending_node_params.get("sub_graph_path", ""))).strip_edges()
	_pending_edge_from = ""
	_pending_edge_to = ""

	_apply_menu_scale(ui_scale)
	_root_menu.clear()

	if not read_only_topology:
		_root_menu.add_item(FlowEditorI18n.t(&"ctx.rename_node"), CMD_RENAME_NODE)
		if can_emit_edge:
			_root_menu.add_item(FlowEditorI18n.t(&"ctx.connect_new"), CMD_APPEND_CHILD)
		_root_menu.add_separator()
		if is_fsm:
			_root_menu.add_check_item(FlowEditorI18n.t(&"ctx.set_initial"), CMD_SET_INITIAL)
			_root_menu.set_item_checked(_root_menu.get_item_index(CMD_SET_INITIAL), bool(node_rec.get("is_initial", false)))
			_root_menu.add_check_item(FlowEditorI18n.t(&"ctx.toggle_any_edge"), CMD_TOGGLE_ANY_EDGE)
			_root_menu.set_item_checked(_root_menu.get_item_index(CMD_TOGGLE_ANY_EDGE), bool(node_rec.get("is_interrupt", false)))
			_root_menu.add_separator()

		var dup_lbl: String = FlowEditorI18n.t(&"ctx.duplicate_nodes", [sel_cnt]) if sel_cnt > 1 else FlowEditorI18n.t(&"ctx.duplicate_node")
		var del_lbl: String = FlowEditorI18n.t(&"ctx.delete_nodes", [sel_cnt]) if sel_cnt > 1 else FlowEditorI18n.t(&"ctx.delete_node")
		_root_menu.add_item(dup_lbl, CMD_DUPLICATE_NODE)
		_root_menu.add_item(del_lbl, CMD_DELETE_NODE)
		_root_menu.add_separator()

	if not _pending_sub_graph_path.is_empty():
		_root_menu.add_item(FlowEditorI18n.t(&"ctx.open_subgraph"), CMD_OPEN_SUBGRAPH)
		_root_menu.add_separator()

	if sel_cnt > 1:
		_root_menu.add_item(FlowEditorI18n.t(&"ctx.toggle_breakpoints", [sel_cnt]), CMD_TOGGLE_BREAKPOINT)
	else:
		_root_menu.add_check_item(FlowEditorI18n.t(&"ctx.toggle_breakpoint"), CMD_TOGGLE_BREAKPOINT)
		_root_menu.set_item_checked(_root_menu.get_item_index(CMD_TOGGLE_BREAKPOINT), has_breakpoint)

	if live_mode:
		_root_menu.add_separator()
		_root_menu.add_icon_item(FlowGraphIcons.STATUS_BOLT, FlowEditorI18n.t(&"ctx.force_node"), CMD_FORCE_NODE)

	_show_popup_at(screen_pos)


func popup_for_edge(
	screen_pos: Vector2i,
	world_pos: Vector2,
	from_id: String,
	to_id: String,
	is_fsm: bool,
	ui_scale: float = 1.0
) -> void:
	if _root_menu == null or from_id.is_empty() or to_id.is_empty():
		return
	_pending_screen_pos = screen_pos
	_pending_world_pos = world_pos
	_pending_node_id = ""
	_pending_edge_from = from_id
	_pending_edge_to = to_id

	_apply_menu_scale(ui_scale)
	_root_menu.clear()

	_root_menu.add_item(FlowEditorI18n.t(&"ctx.edge_inspect"), CMD_EDGE_INSPECT)
	if from_id != "*":
		_root_menu.add_item(FlowEditorI18n.t(&"ctx.edge_insert_node"), CMD_EDGE_INSERT)
		if is_fsm and from_id != to_id:
			_root_menu.add_item(FlowEditorI18n.t(&"ctx.edge_reverse"), CMD_EDGE_REVERSE)
	_root_menu.add_separator()
	_root_menu.add_item(FlowEditorI18n.t(&"ctx.edge_delete"), CMD_EDGE_DELETE)
	_show_popup_at(screen_pos)


func apply_locale() -> void:
	if _root_menu != null and _root_menu.visible:
		_root_menu.hide()


func get_root_popup() -> PopupMenu:
	return _root_menu

#endregion


#region 缩放同步与命令分发

func _apply_menu_scale(ui_scale: float) -> void:
	if _root_menu == null:
		return
	var s: float = clampf(ui_scale, 0.75, 3.0)
	_root_menu.add_theme_font_size_override("font_size", maxi(12, roundi(13.0 * s)))
	_root_menu.add_theme_constant_override("icon_max_width", maxi(15, roundi(16.0 * s)))


func _show_popup_at(screen_pos: Vector2i) -> void:
	_root_menu.position = screen_pos
	_root_menu.reset_size()
	_root_menu.popup()


func _on_menu_id_pressed(id: int) -> void:
	match id:
		CMD_OPEN_PICKER:
			quick_picker_requested.emit(_pending_screen_pos, _pending_world_pos)
		CMD_TOGGLE_DRAWER:
			node_drawer_toggle_requested.emit()
		CMD_TOGGLE_DIR:
			direction_toggle_requested.emit()
		CMD_AUTO_LAYOUT:
			auto_layout_requested.emit()
		CMD_FIT_VIEW:
			fit_view_requested.emit()
		CMD_RENAME_NODE:
			if not _pending_node_id.is_empty():
				node_rename_requested.emit(_pending_node_id)
		CMD_APPEND_CHILD:
			if not _pending_node_id.is_empty():
				node_append_child_requested.emit(_pending_node_id)
		CMD_SET_INITIAL:
			if not _pending_node_id.is_empty():
				initial_node_set_requested.emit(_pending_node_id)
		CMD_TOGGLE_ANY_EDGE:
			if not _pending_node_id.is_empty():
				any_state_edge_toggled.emit(_pending_node_id)
		CMD_DUPLICATE_NODE:
			if _pending_batch_ids.size() > 1:
				nodes_duplicate_requested.emit(_pending_batch_ids.duplicate())
			elif not _pending_node_id.is_empty():
				node_duplicate_requested.emit(_pending_node_id)
		CMD_DELETE_NODE:
			if _pending_batch_ids.size() > 1:
				nodes_delete_requested.emit(_pending_batch_ids.duplicate())
			elif not _pending_node_id.is_empty():
				node_delete_requested.emit(_pending_node_id)
		CMD_OPEN_SUBGRAPH:
			if not _pending_sub_graph_path.is_empty() and not _pending_node_id.is_empty():
				sub_graph_open_requested.emit(_pending_sub_graph_path, _pending_node_id)
		CMD_TOGGLE_BREAKPOINT:
			if _pending_batch_ids.size() > 1:
				breakpoints_toggle_requested.emit(_pending_batch_ids.duplicate())
			elif not _pending_node_id.is_empty():
				breakpoint_toggled.emit(_pending_node_id)
		CMD_FORCE_NODE:
			if not _pending_node_id.is_empty():
				node_force_requested.emit(_pending_node_id, _pending_node_params)
		CMD_EDGE_INSPECT:
			if not _pending_edge_from.is_empty() and not _pending_edge_to.is_empty():
				edge_inspect_requested.emit(_pending_edge_from, _pending_edge_to)
		CMD_EDGE_INSERT:
			if not _pending_edge_from.is_empty() and not _pending_edge_to.is_empty():
				edge_insert_node_requested.emit(_pending_screen_pos, _pending_world_pos, _pending_edge_from, _pending_edge_to)
		CMD_EDGE_REVERSE:
			if not _pending_edge_from.is_empty() and not _pending_edge_to.is_empty():
				edge_reverse_requested.emit(_pending_edge_from, _pending_edge_to)
		CMD_EDGE_DELETE:
			if not _pending_edge_from.is_empty() and not _pending_edge_to.is_empty():
				edge_delete_requested.emit(_pending_edge_from, _pending_edge_to)

#endregion
