@tool
extends RefCounted

## 画布指针、手势、磁吸连线、快速建点与键盘快捷键交互控制器（Canvas Pointer & Shortcut Input Controller）。[br]
##
## 由 [`MermaidGraphCanvas`](mermaid_graph_canvas.gd) 下行喂入 `InputEvent` 与几何快照，上行通过信号汇报视野变换、连线磁吸、拉线空投建点、原位改名、拖拽及菜单意图。

const CanvasGeometry = preload(FlowGraphContracts.SCRIPT_CANVAS_GEOMETRY)

const SNAP_STEP: float = 16.0
const RMB_CLICK_SLOP_PX: float = 5.0
const WIRE_DROP_MIN_PX: float = 12.0
const DRAG_DEADZONE_SQ: float = 2.25

signal scroll_delta_requested(delta: Vector2)
signal zoom_at_requested(anchor_screen: Vector2, factor: float)
signal minimap_pan_requested(world_pt: Vector2)

signal node_selected(node_id: String, emit_inspect: bool)
signal edge_selected(edge_key: String)
signal portal_hub_jumped(hub_id: String)
signal hover_state_changed(node_id: String, port_node_id: String, portal_key: String, edge_key: String, tooltip: String)
signal connection_preview_changed(from_id: String, mouse_world: Vector2, snap_target_id: String)
signal wire_dropped_on_blank(popup_screen_pos: Vector2i, world_pos: Vector2, from_id: String)

signal quick_picker_requested(popup_screen_pos: Vector2i, world_pos: Vector2, from_id: String, split_to_id: String)
signal inline_rename_requested(node_id: String)
signal append_downstream_requested(node_id: String)

signal edge_connection_added(from_id: String, to_id: String)
signal edge_connection_removed(from_id: String, to_id: String)

signal node_drag_started()
signal node_dragged_to(node_id: String, next_pos: Vector2)
signal node_drag_finished(moved: bool)

signal node_force_requested(node_id: String, params: Dictionary)
signal sub_graph_open_requested(sub_graph_path: String, node_id: String)
signal node_context_menu_requested(popup_screen_pos: Vector2i, node_id: String)
signal edge_context_menu_requested(popup_screen_pos: Vector2i, world_pos: Vector2, edge_key: String)
signal blank_context_menu_requested(popup_screen_pos: Vector2i, world_pos: Vector2)

signal node_deleted_requested(node_id: String)
signal node_duplicated_requested(node_id: String)
signal undo_requested()
signal redo_requested()

var _is_panning: bool = false
var _rmb_pressed: bool = false
var _rmb_press_screen: Vector2 = Vector2.ZERO
var _rmb_panning: bool = false
var _dragging_node_id: String = ""
var _drag_node_start_pos: Vector2 = Vector2.ZERO
var _drag_mouse_start_world: Vector2 = Vector2.ZERO
var _drag_moved: bool = false
var _connecting_from_id: String = ""
var _connect_start_screen: Vector2 = Vector2.ZERO
var _last_mouse_screen: Vector2 = Vector2(240.0, 180.0)


func reset_interaction_state() -> void:
	_is_panning = false
	_rmb_pressed = false
	_rmb_panning = false
	_dragging_node_id = ""
	_drag_moved = false
	_connecting_from_id = ""


func is_interacting() -> bool:
	return _is_panning or _rmb_pressed or not _dragging_node_id.is_empty() or not _connecting_from_id.is_empty()


func handle_gui_input(canvas: Control, event: InputEvent, state: Dictionary) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(canvas, event as InputEventMouseButton, state)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(canvas, event as InputEventMouseMotion, state)
	elif event is InputEventKey:
		_handle_key_event(canvas, event as InputEventKey, state)
	elif event is InputEventPanGesture:
		scroll_delta_requested.emit((event as InputEventPanGesture).delta * 18.0)
		canvas.accept_event()


#region 键盘快捷键（F2 改名 / Tab 派生 / Space 快速建点 / Del 删点或删边 / Ctrl+Z,Y,D）

func _handle_key_event(canvas: Control, ke: InputEventKey, state: Dictionary) -> void:
	var read_only_topo: bool = bool(state["read_only_topology"])
	if not ke.pressed or ke.echo or read_only_topo:
		return
	var nodes: Dictionary = state["nodes"] as Dictionary
	var edge_by_key: Dictionary = state["edge_by_key"] as Dictionary
	var sel_id: String = str(state["selected_node_id"])
	var sel_edge: String = str(state.get("selected_edge_key", ""))
	var is_bt: bool = bool(state.get("is_bt", false))
	var ctrl: bool = ke.is_command_or_control_pressed() or ke.ctrl_pressed

	if ctrl and not ke.shift_pressed and ke.keycode == KEY_Z:
		undo_requested.emit()
		canvas.accept_event()
		return
	if (ctrl and ke.keycode == KEY_Y) or (ctrl and ke.shift_pressed and ke.keycode == KEY_Z):
		redo_requested.emit()
		canvas.accept_event()
		return
	if ctrl and ke.keycode == KEY_D:
		if not sel_id.is_empty() and nodes.has(sel_id):
			node_duplicated_requested.emit(sel_id)
			canvas.accept_event()
		return

	if not ctrl and ke.keycode == KEY_F2:
		if not sel_id.is_empty() and nodes.has(sel_id):
			inline_rename_requested.emit(sel_id)
			canvas.accept_event()
		return

	if not ctrl and not ke.shift_pressed and ke.keycode == KEY_TAB:
		if not sel_id.is_empty() and nodes.has(sel_id):
			var rec: Dictionary = nodes[sel_id] as Dictionary
			if CanvasGeometry.can_node_emit_edge(str(rec.get("kind", "State")), is_bt):
				append_downstream_requested.emit(sel_id)
				canvas.accept_event()
		return

	if (not ctrl and ke.keycode == KEY_SPACE) or (not ctrl and ke.shift_pressed and ke.keycode == KEY_A):
		var zoom: float = maxf(float(state["zoom"]), 0.15)
		var scroll_offset: Vector2 = state["scroll_offset"] as Vector2
		var scr_pt: Vector2 = _last_mouse_screen.clamp(Vector2(24.0, 24.0), (canvas.size - Vector2(24.0, 24.0)).max(Vector2(24.0, 24.0)))
		var w_pt: Vector2 = (scr_pt + scroll_offset) / zoom
		var pop_pos := Vector2i((canvas.get_screen_transform() * scr_pt).round())
		quick_picker_requested.emit(pop_pos, w_pt, "", "")
		canvas.accept_event()
		return

	if not ctrl and (ke.keycode == KEY_DELETE or ke.keycode == KEY_BACKSPACE):
		if not sel_edge.is_empty() and edge_by_key.has(sel_edge):
			var ed_rec: Dictionary = edge_by_key[sel_edge] as Dictionary
			edge_selected.emit("")
			edge_connection_removed.emit(str(ed_rec["from"]), str(ed_rec["to"]))
			canvas.accept_event()
		elif not sel_id.is_empty() and nodes.has(sel_id):
			node_deleted_requested.emit(sel_id)
			canvas.accept_event()

#endregion


#region 鼠标按键与滚轮缩放

func _handle_mouse_button(canvas: Control, mb: InputEventMouseButton, state: Dictionary) -> void:
	_last_mouse_screen = mb.position
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
		zoom_at_requested.emit(mb.position, 1.12)
		canvas.accept_event()
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
		zoom_at_requested.emit(mb.position, 1.0 / 1.12)
		canvas.accept_event()
		return
	if mb.button_index == MOUSE_BUTTON_MIDDLE:
		_is_panning = mb.pressed
		canvas.mouse_default_cursor_shape = Control.CURSOR_DRAG if _is_panning else Control.CURSOR_ARROW
		canvas.accept_event()
		return
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		_handle_right_mouse_button(canvas, mb, state)
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return

	var nodes: Dictionary = state["nodes"] as Dictionary
	var node_order: Array[String] = state["node_order"] as Array[String]
	var routed_edges: Array[Dictionary] = state["routed_edges"] as Array[Dictionary]
	var edge_by_key: Dictionary = state["edge_by_key"] as Dictionary
	var read_only_topo: bool = bool(state["read_only_topology"])
	var live_mode: bool = bool(state["live_mode"])
	var is_vertical: bool = bool(state.get("is_vertical", false))
	var is_bt: bool = bool(state.get("is_bt", false))
	var zoom: float = maxf(float(state["zoom"]), 0.15)
	var scroll_offset: Vector2 = state["scroll_offset"] as Vector2
	var w_pt: Vector2 = (mb.position + scroll_offset) / zoom
	var popup_screen_pos := Vector2i((canvas.get_screen_transform() * mb.position).round())

	if mb.pressed:
		if bool(state["minimap_enabled"]) and not nodes.is_empty():
			var mm_hit: Dictionary = CanvasGeometry.minimap_screen_to_world(
				mb.position, canvas.size, float(state["ui_scale"]), state["world_bounds"] as Rect2
			)
			if bool(mm_hit.get("hit", false)):
				minimap_pan_requested.emit(mm_hit["world"] as Vector2)
				canvas.accept_event()
				return

		# 1. 子图右上角 ⧉ 角标单击直达下钻
		var sub_badge_nid: String = CanvasGeometry.hit_test_subgraph_badge(w_pt, nodes, node_order, live_mode, str(state["hovered_node_id"]), zoom)
		if not sub_badge_nid.is_empty() and nodes.has(sub_badge_nid):
			var sb_rec: Dictionary = nodes[sub_badge_nid] as Dictionary
			var sb_path: String = str(sb_rec.get("sub_graph_path", "")).strip_edges()
			if not sb_path.is_empty():
				edge_selected.emit("")
				node_selected.emit(sub_badge_nid, true)
				sub_graph_open_requested.emit(sb_path, sub_badge_nid)
				canvas.accept_event()
				return

		# 2. 流向自适应输出端口手柄拖拽拉线（屏幕像素自适应热区）
		if not read_only_topo:
			var handle_nid: String = CanvasGeometry.hit_test_connect_handle(w_pt, nodes, node_order, is_vertical, is_bt, zoom)
			if not handle_nid.is_empty():
				_connecting_from_id = handle_nid
				_connect_start_screen = mb.position
				edge_selected.emit("")
				node_selected.emit(handle_nid, true)
				connection_preview_changed.emit(handle_nid, w_pt, "")
				canvas.mouse_default_cursor_shape = Control.CURSOR_CROSS
				canvas.accept_event()
				return

		# 3. 节点本体命中：Shift+左键快捷拉线 / 双击改名或下钻 / 按住平滑拖拽
		var hit_nid: String = CanvasGeometry.hit_test_node(w_pt, nodes, node_order)
		if not hit_nid.is_empty():
			var n_rec: Dictionary = nodes[hit_nid] as Dictionary
			if not read_only_topo and mb.shift_pressed and CanvasGeometry.can_node_emit_edge(str(n_rec.get("kind", "State")), is_bt):
				_connecting_from_id = hit_nid
				_connect_start_screen = mb.position
				edge_selected.emit("")
				node_selected.emit(hit_nid, true)
				connection_preview_changed.emit(hit_nid, w_pt, "")
				canvas.mouse_default_cursor_shape = Control.CURSOR_CROSS
				canvas.accept_event()
				return

			edge_selected.emit("")
			node_selected.emit(hit_nid, true)
			if mb.double_click:
				if live_mode:
					node_force_requested.emit(hit_nid, n_rec.get("params", {}) as Dictionary)
					canvas.accept_event()
					return
				var sub_p: String = str(n_rec.get("sub_graph_path", "")).strip_edges()
				if not sub_p.is_empty():
					sub_graph_open_requested.emit(sub_p, hit_nid)
					canvas.accept_event()
					return
				if not read_only_topo:
					inline_rename_requested.emit(hit_nid)
					canvas.accept_event()
					return

			_dragging_node_id = hit_nid
			_drag_node_start_pos = (n_rec["rect"] as Rect2).position
			_drag_mouse_start_world = w_pt
			_drag_moved = false
			canvas.accept_event()
			return

		# 4. FSM 回流胶囊跳转中心状态
		var hit_portal: String = CanvasGeometry.hit_test_portal(w_pt, routed_edges)
		if not hit_portal.is_empty() and edge_by_key.has(hit_portal):
			var target_hub: String = str((edge_by_key[hit_portal] as Dictionary)["to"])
			if nodes.has(target_hub):
				edge_selected.emit("")
				portal_hub_jumped.emit(target_hub)
				canvas.accept_event()
				return

		# 5. 连线命中：单击选中并检视源节点出边规则；双击连线直接插入中间节点
		var hit_edge: String = CanvasGeometry.hit_test_edge(w_pt, routed_edges, zoom)
		if not hit_edge.is_empty() and edge_by_key.has(hit_edge):
			var ed_hit_rec: Dictionary = edge_by_key[hit_edge] as Dictionary
			var ed_from: String = str(ed_hit_rec.get("from", ""))
			var ed_to: String = str(ed_hit_rec.get("to", ""))
			edge_selected.emit(hit_edge)
			if ed_from != "*" and nodes.has(ed_from):
				node_selected.emit(ed_from, true)
			elif nodes.has(ed_to):
				node_selected.emit(ed_to, true)
			if mb.double_click and not read_only_topo and ed_from != "*":
				quick_picker_requested.emit(popup_screen_pos, w_pt, ed_from, ed_to)
			canvas.accept_event()
			return

		# 6. 空白画布：双击弹出快速搜索建点器；单按拖拽平移视口
		edge_selected.emit("")
		node_selected.emit("", true)
		if mb.double_click and not read_only_topo:
			_is_panning = false
			quick_picker_requested.emit(popup_screen_pos, w_pt, "", "")
			canvas.accept_event()
			return

		_is_panning = true
		canvas.accept_event()
	else:
		if _is_panning:
			_is_panning = false
			canvas.mouse_default_cursor_shape = Control.CURSOR_ARROW

		if not _connecting_from_id.is_empty():
			var src_nid: String = _connecting_from_id
			var target_nid: String = CanvasGeometry.hit_test_snap_target(w_pt, src_nid, nodes, node_order, is_vertical, zoom)
			var drag_px: float = mb.position.distance_to(_connect_start_screen)
			_connecting_from_id = ""
			canvas.mouse_default_cursor_shape = Control.CURSOR_ARROW
			if not target_nid.is_empty() and target_nid != src_nid:
				connection_preview_changed.emit("", Vector2.ZERO, "")
				edge_connection_added.emit(src_nid, target_nid)
			elif not read_only_topo and drag_px >= WIRE_DROP_MIN_PX:
				wire_dropped_on_blank.emit(popup_screen_pos, w_pt, src_nid)
			else:
				connection_preview_changed.emit("", Vector2.ZERO, "")
			canvas.accept_event()
			return

		if not _dragging_node_id.is_empty():
			var moved_flag: bool = _drag_moved
			_dragging_node_id = ""
			_drag_moved = false
			canvas.mouse_default_cursor_shape = Control.CURSOR_ARROW
			node_drag_finished.emit(moved_flag)
			canvas.accept_event()


func _handle_right_mouse_button(canvas: Control, mb: InputEventMouseButton, state: Dictionary) -> void:
	_last_mouse_screen = mb.position
	if mb.pressed:
		_rmb_pressed = true
		_rmb_press_screen = mb.position
		_rmb_panning = false
		canvas.accept_event()
		return

	var was_panning: bool = _rmb_panning
	var dist: float = mb.position.distance_to(_rmb_press_screen)
	_rmb_pressed = false
	_rmb_panning = false
	canvas.mouse_default_cursor_shape = Control.CURSOR_ARROW
	if was_panning or dist > RMB_CLICK_SLOP_PX:
		canvas.accept_event()
		return

	var nodes: Dictionary = state["nodes"] as Dictionary
	var node_order: Array[String] = state["node_order"] as Array[String]
	var routed_edges: Array[Dictionary] = state["routed_edges"] as Array[Dictionary]
	var edge_by_key: Dictionary = state["edge_by_key"] as Dictionary
	var read_only_topo: bool = bool(state["read_only_topology"])
	var zoom: float = maxf(float(state["zoom"]), 0.15)
	var scroll_offset: Vector2 = state["scroll_offset"] as Vector2
	var w_pt: Vector2 = (mb.position + scroll_offset) / zoom
	var popup_screen_pos := Vector2i((canvas.get_screen_transform() * mb.position).round())

	var hit_nid: String = CanvasGeometry.hit_test_node(w_pt, nodes, node_order)
	if not hit_nid.is_empty() and nodes.has(hit_nid):
		edge_selected.emit("")
		node_selected.emit(hit_nid, true)
		node_context_menu_requested.emit(popup_screen_pos, hit_nid)
		canvas.accept_event()
		return

	if not read_only_topo:
		var edge_key_hit: String = CanvasGeometry.hit_test_portal(w_pt, routed_edges)
		if edge_key_hit.is_empty():
			edge_key_hit = CanvasGeometry.hit_test_edge(w_pt, routed_edges, zoom)
		if not edge_key_hit.is_empty() and edge_by_key.has(edge_key_hit):
			edge_selected.emit(edge_key_hit)
			edge_context_menu_requested.emit(popup_screen_pos, w_pt, edge_key_hit)
			canvas.accept_event()
			return
		edge_selected.emit("")
		blank_context_menu_requested.emit(popup_screen_pos, w_pt)

	canvas.accept_event()

#endregion


#region 鼠标移动：平滑拖拽、磁吸预览与端口不闪烁悬停

func _handle_mouse_motion(canvas: Control, mm: InputEventMouseMotion, state: Dictionary) -> void:
	_last_mouse_screen = mm.position
	if _rmb_pressed:
		if not _rmb_panning and mm.position.distance_to(_rmb_press_screen) > RMB_CLICK_SLOP_PX:
			_rmb_panning = true
			canvas.mouse_default_cursor_shape = Control.CURSOR_DRAG
		if _rmb_panning:
			scroll_delta_requested.emit(-mm.relative)
			canvas.accept_event()
			return

	if _is_panning:
		canvas.mouse_default_cursor_shape = Control.CURSOR_DRAG
		scroll_delta_requested.emit(-mm.relative)
		canvas.accept_event()
		return

	var nodes: Dictionary = state["nodes"] as Dictionary
	var node_order: Array[String] = state["node_order"] as Array[String]
	var routed_edges: Array[Dictionary] = state["routed_edges"] as Array[Dictionary]
	var read_only_topo: bool = bool(state["read_only_topology"])
	var live_mode: bool = bool(state["live_mode"])
	var is_vertical: bool = bool(state.get("is_vertical", false))
	var is_bt: bool = bool(state.get("is_bt", false))
	var zoom: float = maxf(float(state["zoom"]), 0.15)
	var scroll_offset: Vector2 = state["scroll_offset"] as Vector2
	var w_cur: Vector2 = (mm.position + scroll_offset) / zoom

	if not _connecting_from_id.is_empty():
		var snap_target: String = CanvasGeometry.hit_test_snap_target(w_cur, _connecting_from_id, nodes, node_order, is_vertical, zoom)
		connection_preview_changed.emit(_connecting_from_id, w_cur, snap_target)
		canvas.accept_event()
		return

	if not _dragging_node_id.is_empty() and nodes.has(_dragging_node_id):
		var delta_w: Vector2 = w_cur - _drag_mouse_start_world
		if not _drag_moved:
			if delta_w.length_squared() <= DRAG_DEADZONE_SQ:
				return
			_drag_moved = true
			canvas.mouse_default_cursor_shape = Control.CURSOR_DRAG
			if not read_only_topo:
				node_drag_started.emit()
		var next_pos: Vector2 = _drag_node_start_pos + delta_w
		if bool(state["snapping_enabled"]) and not mm.alt_pressed:
			next_pos = next_pos.snapped(Vector2(SNAP_STEP, SNAP_STEP))
		node_dragged_to.emit(_dragging_node_id, next_pos)
		canvas.accept_event()
		return

	# 优先测试输出端口手柄：即使指针在节点边框外半圆，依然保持所属节点悬停态，杜绝圆点闪烁消失
	var next_port: String = CanvasGeometry.hit_test_connect_handle(w_cur, nodes, node_order, is_vertical, is_bt, zoom) if not read_only_topo else ""
	var next_sub_badge: String = CanvasGeometry.hit_test_subgraph_badge(w_cur, nodes, node_order, live_mode, str(state["hovered_node_id"]), zoom) if next_port.is_empty() else ""
	var next_hn: String = next_port if not next_port.is_empty() else CanvasGeometry.hit_test_node(w_cur, nodes, node_order)
	var next_hp: String = CanvasGeometry.hit_test_portal(w_cur, routed_edges) if next_hn.is_empty() else ""
	var next_he: String = CanvasGeometry.hit_test_edge(w_cur, routed_edges, zoom) if (next_hn.is_empty() and next_hp.is_empty()) else ""

	# 光标形状实时反馈
	if not next_port.is_empty() or not next_sub_badge.is_empty() or not next_hp.is_empty() or not next_he.is_empty():
		canvas.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	elif not next_hn.is_empty():
		canvas.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if live_mode else (Control.CURSOR_ARROW if read_only_topo else Control.CURSOR_MOVE)
	else:
		canvas.mouse_default_cursor_shape = Control.CURSOR_ARROW

	if (
		next_hn != str(state["hovered_node_id"])
		or next_port != str(state.get("hovered_port_node_id", ""))
		or next_hp != str(state["hovered_portal_key"])
		or next_he != str(state["hovered_edge_key"])
	):
		var tip: String = ""
		if not next_port.is_empty():
			tip = FlowEditorI18n.t(&"canvas.tip_port")
		elif not next_hn.is_empty() and nodes.has(next_hn):
			var h_rec: Dictionary = nodes[next_hn] as Dictionary
			var h_title: String = str(h_rec.get("title", next_hn))
			var sub_sfx: String = FlowEditorI18n.t(&"canvas.tip_sub_suffix") if not str(h_rec.get("sub_graph_path", "")).is_empty() else ""
			if live_mode:
				tip = FlowEditorI18n.t(&"canvas.tip_live", [h_title])
			elif read_only_topo:
				tip = FlowEditorI18n.t(&"canvas.tip_ro", [h_title, sub_sfx])
			else:
				tip = FlowEditorI18n.t(&"canvas.tip_edit", [h_title, sub_sfx])
		elif not next_hp.is_empty():
			tip = FlowEditorI18n.t(&"canvas.tip_portal_ro") if read_only_topo else FlowEditorI18n.t(&"canvas.tip_portal_edit")
		elif not next_he.is_empty() and not read_only_topo:
			tip = FlowEditorI18n.t(&"canvas.tip_edge")
		hover_state_changed.emit(next_hn, next_port, next_hp, next_he, tip)

#endregion
