@tool
extends RefCounted

## 画布右键上下文菜单构建与命令派发器（Canvas Context Menu Builder & Dispatcher）。[br]
##
## 封装空白画布新建（FSM 状态 / BT 三大家族 15 种积木、方向切换、自动重排）与节点原位操作（设为入口、切换 `*` 全局打断边、复制、删除、打开子图、切换断点 `●`、运行期强制触发）。

const CanvasThemePalette = preload(FlowGraphContracts.SCRIPT_CANVAS_PALETTE)

signal node_add_requested(kind: String, world_pos: Vector2)
signal node_rename_requested(node_id: String)
signal node_append_child_requested(node_id: String)
signal node_delete_requested(node_id: String)
signal node_duplicate_requested(node_id: String)
signal initial_node_set_requested(node_id: String)
signal any_state_edge_toggled(node_id: String)
signal breakpoint_toggled(node_id: String)
signal sub_graph_open_requested(sub_graph_path: String, node_id: String)
signal node_force_requested(node_id: String, params: Dictionary)
signal edge_inspect_requested(from_id: String, to_id: String)
signal edge_insert_node_requested(screen_pos: Vector2i, world_pos: Vector2, from_id: String, to_id: String)
signal edge_reverse_requested(from_id: String, to_id: String)
signal edge_delete_requested(from_id: String, to_id: String)
signal direction_toggle_requested()
signal auto_layout_requested()

const CMD_ADD_STATE: int = 100
const CMD_QUICK_SEQ: int = 101
const CMD_QUICK_SEL: int = 102
const CMD_QUICK_ACT: int = 103
const CMD_QUICK_COND: int = 104
const CMD_TOGGLE_DIR: int = 110
const CMD_AUTO_LAYOUT: int = 111

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

const CMD_BT_KIND_BASE: int = 300

const BT_COMPOSITE_KINDS: PackedStringArray = [
	"Selector", "WeightedSelector", "Sequence", "Parallel",
]

const BT_DECORATOR_KINDS: PackedStringArray = [
	"Cooldown", "Repeater", "TimeLimit", "Inverter",
	"ForceSuccess", "ForceFailure", "Service",
]

const BT_LEAF_KINDS: PackedStringArray = [
	"Action", "Condition", "Wait", "SubTree",
]

var _root_menu: PopupMenu = null
var _sub_composites: PopupMenu = null
var _sub_decorators: PopupMenu = null
var _sub_leaves: PopupMenu = null

var _kind_by_cmd: Dictionary = {}
var _pending_screen_pos: Vector2i = Vector2i.ZERO
var _pending_world_pos: Vector2 = Vector2.ZERO
var _pending_node_id: String = ""
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

	_sub_composites = PopupMenu.new()
	_sub_composites.name = "SubComposites"
	_sub_decorators = PopupMenu.new()
	_sub_decorators.name = "SubDecorators"
	_sub_leaves = PopupMenu.new()
	_sub_leaves.name = "SubLeaves"

	_root_menu.add_child(_sub_composites)
	_root_menu.add_child(_sub_decorators)
	_root_menu.add_child(_sub_leaves)
	host_canvas.add_child(_root_menu)

	_populate_bt_submenus()

	_root_menu.id_pressed.connect(_on_menu_id_pressed)
	_sub_composites.id_pressed.connect(_on_menu_id_pressed)
	_sub_decorators.id_pressed.connect(_on_menu_id_pressed)
	_sub_leaves.id_pressed.connect(_on_menu_id_pressed)


func popup_for_blank(
	screen_pos: Vector2i,
	world_pos: Vector2,
	is_fsm: bool,
	is_empty_generic: bool,
	ui_scale: float = 1.0
) -> void:
	if _root_menu == null:
		return
	_pending_screen_pos = screen_pos
	_pending_world_pos = world_pos
	_pending_node_id = ""
	_pending_edge_from = ""
	_pending_edge_to = ""
	_populate_bt_submenus()
	_apply_menu_scale(ui_scale)
	_root_menu.clear(false)

	if is_fsm or is_empty_generic:
		_add_root_kind_item("State", FlowEditorI18n.t(&"ctx.add_state"), CMD_ADD_STATE, true)

	if (not is_fsm) or is_empty_generic:
		if is_empty_generic:
			_root_menu.add_separator()
		_add_root_kind_item("Sequence", FlowEditorI18n.t(&"ctx.quick_bt_seq"), CMD_QUICK_SEQ, false)
		_add_root_kind_item("Selector", FlowEditorI18n.t(&"ctx.quick_bt_sel"), CMD_QUICK_SEL, false)
		_add_root_kind_item("Action", FlowEditorI18n.t(&"ctx.quick_bt_act"), CMD_QUICK_ACT, false)
		_add_root_kind_item("Condition", FlowEditorI18n.t(&"ctx.quick_bt_cond"), CMD_QUICK_COND, false)
		_root_menu.add_separator()
		_root_menu.add_submenu_node_item(FlowEditorI18n.t(&"ctx.group_composites"), _sub_composites)
		_root_menu.add_submenu_node_item(FlowEditorI18n.t(&"ctx.group_decorators"), _sub_decorators)
		_root_menu.add_submenu_node_item(FlowEditorI18n.t(&"ctx.group_leaves"), _sub_leaves)

	_root_menu.add_separator()
	_root_menu.add_item(FlowEditorI18n.t(&"ctx.toggle_dir"), CMD_TOGGLE_DIR)
	_root_menu.add_item(FlowEditorI18n.t(&"ctx.auto_layout"), CMD_AUTO_LAYOUT)
	_show_popup_at(screen_pos)


func popup_for_node(
	screen_pos: Vector2i,
	node_rec: Dictionary,
	is_fsm: bool,
	read_only_topology: bool,
	live_mode: bool,
	has_breakpoint: bool,
	ui_scale: float = 1.0,
	can_emit_edge: bool = true
) -> void:
	if _root_menu == null or node_rec.is_empty():
		return
	_pending_screen_pos = screen_pos
	_pending_node_id = str(node_rec.get("id", ""))
	_pending_node_params = (node_rec.get("params", {}) as Dictionary).duplicate(true)
	_pending_sub_graph_path = str(node_rec.get("sub_graph_path", _pending_node_params.get("sub_graph_path", ""))).strip_edges()
	_pending_edge_from = ""
	_pending_edge_to = ""

	_apply_menu_scale(ui_scale)
	_root_menu.clear(false)

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

		_root_menu.add_item(FlowEditorI18n.t(&"ctx.duplicate_node"), CMD_DUPLICATE_NODE)
		_root_menu.add_item(FlowEditorI18n.t(&"ctx.delete_node"), CMD_DELETE_NODE)
		_root_menu.add_separator()

	if not _pending_sub_graph_path.is_empty():
		_root_menu.add_item(FlowEditorI18n.t(&"ctx.open_subgraph"), CMD_OPEN_SUBGRAPH)
		_root_menu.add_separator()

	_root_menu.add_check_item(FlowEditorI18n.t(&"ctx.toggle_breakpoint"), CMD_TOGGLE_BREAKPOINT)
	_root_menu.set_item_checked(_root_menu.get_item_index(CMD_TOGGLE_BREAKPOINT), has_breakpoint)

	if live_mode:
		_root_menu.add_separator()
		_root_menu.add_item(FlowEditorI18n.t(&"ctx.force_node"), CMD_FORCE_NODE)

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
	_root_menu.clear(false)

	_root_menu.add_item(FlowEditorI18n.t(&"ctx.edge_inspect"), CMD_EDGE_INSPECT)
	if from_id != "*":
		_root_menu.add_item(FlowEditorI18n.t(&"ctx.edge_insert_node"), CMD_EDGE_INSERT)
		if is_fsm and from_id != to_id:
			_root_menu.add_item(FlowEditorI18n.t(&"ctx.edge_reverse"), CMD_EDGE_REVERSE)
	_root_menu.add_separator()
	_root_menu.add_item(FlowEditorI18n.t(&"ctx.edge_delete"), CMD_EDGE_DELETE)
	_show_popup_at(screen_pos)


func apply_locale() -> void:
	if _sub_composites != null:
		_populate_bt_submenus()


func get_root_popup() -> PopupMenu:
	return _root_menu

#endregion


#region 子菜单装配与命令分发

func _add_root_kind_item(kind_s: String, label_s: String, cmd_id: int, use_initial_icon: bool) -> void:
	var ico: Texture2D = CanvasThemePalette.resolve_kind_icon(kind_s, use_initial_icon, false, false)
	if ico != null:
		_root_menu.add_icon_item(ico, label_s, cmd_id)
	else:
		_root_menu.add_item(label_s, cmd_id)


func _populate_bt_submenus() -> void:
	_kind_by_cmd.clear()
	var next_id: int = CMD_BT_KIND_BASE
	next_id = _fill_bt_group(_sub_composites, BT_COMPOSITE_KINDS, next_id)
	next_id = _fill_bt_group(_sub_decorators, BT_DECORATOR_KINDS, next_id)
	_fill_bt_group(_sub_leaves, BT_LEAF_KINDS, next_id)


func _fill_bt_group(menu: PopupMenu, kinds: PackedStringArray, start_id: int) -> int:
	menu.clear()
	var cur_id: int = start_id
	for kind_s: String in kinds:
		var label_s: String = FlowEditorI18n.kind_label(kind_s)
		var ico: Texture2D = CanvasThemePalette.resolve_kind_icon(kind_s, false, false, false)
		if ico != null:
			menu.add_icon_item(ico, label_s, cur_id)
		else:
			menu.add_item(label_s, cur_id)
		_kind_by_cmd[cur_id] = kind_s
		cur_id += 1
	return cur_id


func _apply_menu_scale(ui_scale: float) -> void:
	var s: float = clampf(ui_scale, 0.75, 3.0)
	var fs: int = maxi(12, roundi(13.0 * s))
	var ico_w: int = maxi(15, roundi(16.0 * s))
	for m: PopupMenu in [_root_menu, _sub_composites, _sub_decorators, _sub_leaves]:
		if m != null:
			m.add_theme_font_size_override("font_size", fs)
			m.add_theme_constant_override("icon_max_width", ico_w)


func _show_popup_at(screen_pos: Vector2i) -> void:
	_root_menu.position = screen_pos
	_root_menu.reset_size()
	_root_menu.popup()


func _on_menu_id_pressed(id: int) -> void:
	if _kind_by_cmd.has(id):
		node_add_requested.emit(str(_kind_by_cmd[id]), _pending_world_pos)
		return

	match id:
		CMD_ADD_STATE:
			node_add_requested.emit("State", _pending_world_pos)
		CMD_QUICK_SEQ:
			node_add_requested.emit("Sequence", _pending_world_pos)
		CMD_QUICK_SEL:
			node_add_requested.emit("Selector", _pending_world_pos)
		CMD_QUICK_ACT:
			node_add_requested.emit("Action", _pending_world_pos)
		CMD_QUICK_COND:
			node_add_requested.emit("Condition", _pending_world_pos)
		CMD_TOGGLE_DIR:
			direction_toggle_requested.emit()
		CMD_AUTO_LAYOUT:
			auto_layout_requested.emit()
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
			if not _pending_node_id.is_empty():
				node_duplicate_requested.emit(_pending_node_id)
		CMD_DELETE_NODE:
			if not _pending_node_id.is_empty():
				node_delete_requested.emit(_pending_node_id)
		CMD_OPEN_SUBGRAPH:
			if not _pending_sub_graph_path.is_empty() and not _pending_node_id.is_empty():
				sub_graph_open_requested.emit(_pending_sub_graph_path, _pending_node_id)
		CMD_TOGGLE_BREAKPOINT:
			if not _pending_node_id.is_empty():
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
