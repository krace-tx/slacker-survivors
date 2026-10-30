@tool
extends RefCounted

## 画布指针、矩形框选、手势平移、磁吸连线与键盘动作控制器（Canvas Pointer, Marquee & Shortcut Controller）。[br]
##
## [b]架构职责：[/b][br]
## 1. 100% 通过 [`FlowEditorInput`](../../input/flow_editor_input.gd) 解析语义动作与修饰键，内部严禁散落任何物理键码或鼠标按键常量；[br]
## 2. 左键在空白画布拖拽驱动矩形框选（支持标准覆盖、`Shift` 追加、`Ctrl/Cmd` 反选切换），视口平移统一收拢至「中键拖拽 / 右键拖拽 / `Space` + 左键抓手 / 触控板双指平移」；[br]
## 3. 支持单选与多选节点群组等距拖拽、输出端口磁吸拉线、拉线空投建点、`F` 聚焦选集、`F9` 批量切换断点、`Ctrl+A` 全选与 `Esc` 逐级取消。

const CanvasGeometry = preload(FlowGraphContracts.SCRIPT_CANVAS_GEOMETRY)
const CanvasSelectionModel = preload(FlowGraphContracts.SCRIPT_CANVAS_SELECTION)

const SNAP_STEP: float = 16.0
const RMB_CLICK_SLOP_PX: float = 5.0
const WIRE_DROP_MIN_PX: float = 12.0
const DRAG_DEADZONE_SQ: float = 2.25

signal scroll_delta_requested(delta: Vector2)
signal zoom_at_requested(anchor_screen: Vector2, factor: float)
signal minimap_pan_requested(world_pt: Vector2)
signal frame_or_fit_requested()

signal selection_visual_changed(emit_inspect: bool)
signal portal_hub_jumped(hub_id: String)
signal hover_state_changed(node_id: String, port_node_id: String, portal_key: String, edge_key: String, tooltip: String)
signal connection_preview_changed(from_id: String, mouse_world: Vector2, snap_target_id: String)
signal wire_dropped_on_blank(popup_screen_pos: Vector2i, world_pos: Vector2, from_id: String)

signal quick_picker_requested(popup_screen_pos: Vector2i, world_pos: Vector2, from_id: String, split_to_id: String)
signal inline_rename_requested(node_id: String)
signal append_downstream_requested(node_id: String)

signal edge_connection_added(from_id: String, to_id: String)
signal edge_connection_removed(from_id: String, to_id: String)

signal group_drag_started()
signal group_dragged_by(world_delta: Vector2)
signal group_drag_finished(moved: bool)

signal node_force_requested(node_id: String, params: Dictionary)
signal sub_graph_open_requested(sub_graph_path: String, node_id: String)
signal node_context_menu_requested(popup_screen_pos: Vector2i, node_id: String)
signal edge_context_menu_requested(popup_screen_pos: Vector2i, world_pos: Vector2, edge_key: String)
signal blank_context_menu_requested(popup_screen_pos: Vector2i, world_pos: Vector2)

signal nodes_deleted_requested(node_ids: Array[String])
signal nodes_duplicated_requested(node_ids: Array[String])
signal breakpoints_toggle_requested(node_ids: Array[String])
signal undo_requested()
signal redo_requested()

var _is_middle_panning: bool = false
var _space_pan_armed: bool = false
var _space_pan_dragging: bool = false
var _space_pan_used: bool = false
var _rmb_pressed: bool = false
var _rmb_press_screen: Vector2 = Vector2.ZERO
var _rmb_panning: bool = false

var _dragging_anchor_id: String = ""
var _drag_anchor_start_pos: Vector2 = Vector2.ZERO
var _drag_mouse_start_world: Vector2 = Vector2.ZERO
var _drag_moved: bool = false
var _collapse_to_single_on_release: bool = false

var _connecting_from_id: String = ""
var _connect_start_screen: Vector2 = Vector2.ZERO
var _last_mouse_screen: Vector2 = Vector2(240.0, 180.0)


func reset_interaction_state() -> void:
	_is_middle_panning = false
	_space_pan_armed = false
	_space_pan_dragging = false
	_space_pan_used = false
	_rmb_pressed = false
	_rmb_panning = false
	_dragging_anchor_id = ""
	_drag_moved = false
	_collapse_to_single_on_release = false
	_connecting_from_id = ""


func on_focus_lost(canvas: Control, selection: CanvasSelectionModel) -> void:
	if _space_pan_armed or _space_pan_dragging:
		_space_pan_armed = false
		_space_pan_dragging = false
		_space_pan_used = false
		if canvas != null:
			canvas.mouse_default_cursor_shape = Control.CURSOR_ARROW
	if selection != null and selection.is_marquee_armed():
		selection.cancel_marquee()
		selection_visual_changed.emit(true)


func is_interacting(selection: CanvasSelectionModel = null) -> bool:
	var mq: bool = selection != null and selection.is_marquee_armed()
	return (
		_is_middle_panning
		or _space_pan_dragging
		or _rmb_pressed
		or mq
		or not _dragging_anchor_id.is_empty()
		or not _connecting_from_id.is_empty()
	)


func handle_gui_input(canvas: Control, event: InputEvent, selection: CanvasSelectionModel, state: Dictionary) -> void:
	var zoom_factor: float = FlowEditorInput.resolve_zoom_factor(event)
	if zoom_factor > 0.0:
		var anchor_pt: Vector2 = _last_mouse_screen
		if event is InputEventMouse:
			anchor_pt = (event as InputEventMouse).position
			_last_mouse_screen = anchor_pt
		zoom_at_requested.emit(anchor_pt, zoom_factor)
		canvas.accept_event()
		return

	var pan_gesture: Vector2 = FlowEditorInput.resolve_pan_gesture_delta(event)
	if pan_gesture != Vector2.ZERO:
		scroll_delta_requested.emit(pan_gesture)
		canvas.accept_event()
		return

	if event is InputEventMouseButton:
		_handle_mouse_button(canvas, event as InputEventMouseButton, selection, state)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(canvas, event as InputEventMouseMotion, selection, state)
	elif event is InputEventKey:
		_handle_key_event(canvas, event as InputEventKey, selection, state)


#region 键盘语义动作处理（全选 / 取消 / 聚焦 / 断点 / 抓手或快速建点 / 批量增删改）

func _handle_key_event(canvas: Control, ke: InputEventKey, selection: CanvasSelectionModel, state: Dictionary) -> void:
	var read_only_topo: bool = bool(state["read_only_topology"])

	# Space 松开判定：若按住期间未用于抓手平移，则在可编辑模式下弹出快速搜索建点面板
	if FlowEditorInput.is_key_release(ke, FlowEditorInput.CANVAS_SPACE_HAND_OR_PICKER):
		var open_picker_now: bool = _space_pan_armed and not _space_pan_used and not read_only_topo
		_space_pan_armed = false
		_space_pan_dragging = false
		_space_pan_used = false
		canvas.mouse_default_cursor_shape = Control.CURSOR_ARROW
		if open_picker_now and not is_interacting(selection):
			_emit_quick_picker_at_cursor(canvas, state)
		canvas.accept_event()
		return

	var action: StringName = FlowEditorInput.resolve_canvas_key_action(ke, false)
	if action == &"":
		return

	var nodes: Dictionary = state["nodes"] as Dictionary
	var node_order: Array[String] = state["node_order"] as Array[String]
	var edge_by_key: Dictionary = state["edge_by_key"] as Dictionary
	var is_bt: bool = bool(state.get("is_bt", false))
	var primary_id: String = selection.primary_node_id

	# ── 全模式通用动作（含运行期 LIVE 与快照 SNAPSHOT）──
	match action:
		FlowEditorInput.CANVAS_SPACE_HAND_OR_PICKER:
			_space_pan_armed = true
			_space_pan_used = false
			canvas.mouse_default_cursor_shape = Control.CURSOR_DRAG
			canvas.accept_event()
			return
		FlowEditorInput.CANVAS_SELECT_ALL:
			if not node_order.is_empty() and selection.select_all_nodes(node_order):
				selection_visual_changed.emit(true)
			canvas.accept_event()
			return
		FlowEditorInput.CANVAS_CANCEL_OR_CLEAR:
			if not _connecting_from_id.is_empty():
				_connecting_from_id = ""
				canvas.mouse_default_cursor_shape = Control.CURSOR_ARROW
				connection_preview_changed.emit("", Vector2.ZERO, "")
				canvas.accept_event()
				return
			if selection.is_marquee_armed():
				selection.cancel_marquee()
				selection_visual_changed.emit(true)
				canvas.accept_event()
				return
			if selection.clear_all():
				selection_visual_changed.emit(true)
				canvas.accept_event()
			return
		FlowEditorInput.CANVAS_FIT_OR_FRAME:
			frame_or_fit_requested.emit()
			canvas.accept_event()
			return
		FlowEditorInput.CANVAS_TOGGLE_BREAKPOINT:
			if selection.get_selected_count() > 0:
				breakpoints_toggle_requested.emit(selection.selected_node_ids.duplicate())
				canvas.accept_event()
			return

	# ── 仅可编辑模式（DRAFT / RESOURCE）允许的拓扑变更动作 ──
	if read_only_topo:
		return

	match action:
		FlowEditorInput.CANVAS_UNDO:
			undo_requested.emit()
			canvas.accept_event()
		FlowEditorInput.CANVAS_REDO:
			redo_requested.emit()
			canvas.accept_event()
		FlowEditorInput.CANVAS_DUPLICATE:
			if selection.get_selected_count() > 0:
				nodes_duplicated_requested.emit(selection.selected_node_ids.duplicate())
				canvas.accept_event()
		FlowEditorInput.CANVAS_RENAME:
			if not primary_id.is_empty() and nodes.has(primary_id):
				inline_rename_requested.emit(primary_id)
				canvas.accept_event()
		FlowEditorInput.CANVAS_APPEND_DOWNSTREAM:
			if not primary_id.is_empty() and nodes.has(primary_id):
				var rec: Dictionary = nodes[primary_id] as Dictionary
				if CanvasGeometry.can_node_emit_edge(str(rec.get("kind", "State")), is_bt):
					append_downstream_requested.emit(primary_id)
					canvas.accept_event()
		FlowEditorInput.CANVAS_QUICK_ADD:
			_emit_quick_picker_at_cursor(canvas, state)
			canvas.accept_event()
		FlowEditorInput.CANVAS_DELETE:
			var sel_edge: String = selection.selected_edge_key
			if not sel_edge.is_empty() and edge_by_key.has(sel_edge):
				var ed_rec: Dictionary = edge_by_key[sel_edge] as Dictionary
				selection.select_edge("")
				selection_visual_changed.emit(false)
				edge_connection_removed.emit(str(ed_rec["from"]), str(ed_rec["to"]))
				canvas.accept_event()
			elif selection.get_selected_count() > 0:
				nodes_deleted_requested.emit(selection.selected_node_ids.duplicate())
				canvas.accept_event()


func _emit_quick_picker_at_cursor(canvas: Control, state: Dictionary) -> void:
	var zoom: float = maxf(float(state["zoom"]), 0.15)
	var scroll_offset: Vector2 = state["scroll_offset"] as Vector2
	var scr_pt: Vector2 = _last_mouse_screen.clamp(
		Vector2(24.0, 24.0),
		(canvas.size - Vector2(24.0, 24.0)).max(Vector2(24.0, 24.0))
	)
	var w_pt: Vector2 = (scr_pt + scroll_offset) / zoom
	var pop_pos: Vector2i = _to_popup_screen_pos(canvas, scr_pt)
	quick_picker_requested.emit(pop_pos, w_pt, "", "")


static func _to_popup_screen_pos(canvas: Control, local_pos: Vector2) -> Vector2i:
	if canvas != null and canvas.is_inside_tree():
		return Vector2i((canvas.get_screen_transform() * local_pos).round())
	return Vector2i(local_pos.round())

#endregion


#region 鼠标指针按下/松开（中键平移 / 右键菜单或平移 / 左键点选、框选、连线与群组拖拽）

func _sync_space_physical_state(canvas: Control) -> void:
	if _space_pan_armed and not FlowEditorInput.is_physical_key_held(FlowEditorInput.CANVAS_SPACE_HAND_OR_PICKER):
		_space_pan_armed = false
		_space_pan_dragging = false
		_space_pan_used = false
		if not _is_middle_panning and not _rmb_panning:
			canvas.mouse_default_cursor_shape = Control.CURSOR_ARROW


func _handle_mouse_button(canvas: Control, mb: InputEventMouseButton, selection: CanvasSelectionModel, state: Dictionary) -> void:
	_last_mouse_screen = mb.position
	_sync_space_physical_state(canvas)

	if FlowEditorInput.is_pointer_button(mb, FlowEditorInput.PTR_PAN_DEDICATED):
		_is_middle_panning = mb.pressed
		canvas.mouse_default_cursor_shape = Control.CURSOR_DRAG if _is_middle_panning else Control.CURSOR_ARROW
		canvas.accept_event()
		return

	if FlowEditorInput.is_pointer_button(mb, FlowEditorInput.PTR_CONTEXT_OR_PAN):
		_handle_context_or_pan_button(canvas, mb, selection, state)
		return

	if not FlowEditorInput.is_pointer_button(mb, FlowEditorInput.PTR_PRIMARY):
		return

	# Space 按住期间左键接管为抓手视口平移
	if _space_pan_armed and mb.pressed:
		_space_pan_dragging = true
		_space_pan_used = true
		canvas.mouse_default_cursor_shape = Control.CURSOR_DRAG
		canvas.accept_event()
		return
	if _space_pan_dragging and not mb.pressed:
		_space_pan_dragging = false
		canvas.mouse_default_cursor_shape = Control.CURSOR_DRAG if _space_pan_armed else Control.CURSOR_ARROW
		canvas.accept_event()
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
	var popup_screen_pos: Vector2i = _to_popup_screen_pos(canvas, mb.position)

	if mb.pressed:
		if bool(state["minimap_enabled"]) and not nodes.is_empty():
			var mm_hit: Dictionary = CanvasGeometry.minimap_screen_to_world(
				mb.position, canvas.size, float(state["ui_scale"]), state["world_bounds"] as Rect2
			)
			if bool(mm_hit.get("hit", false)):
				minimap_pan_requested.emit(mm_hit["world"] as Vector2)
				canvas.accept_event()
				return

		# 1. 子图右上角角标单击直达下钻
		var sub_badge_nid: String = CanvasGeometry.hit_test_subgraph_badge(
			w_pt, nodes, node_order, live_mode, str(state["hovered_node_id"]), zoom
		)
		if not sub_badge_nid.is_empty() and nodes.has(sub_badge_nid):
			var sb_rec: Dictionary = nodes[sub_badge_nid] as Dictionary
			var sb_path: String = str(sb_rec.get("sub_graph_path", "")).strip_edges()
			if not sb_path.is_empty():
				selection.select_single_node(sub_badge_nid)
				selection_visual_changed.emit(true)
				sub_graph_open_requested.emit(sb_path, sub_badge_nid)
				canvas.accept_event()
				return

		# 2. 流向自适应输出端口手柄拖拽拉线
		if not read_only_topo:
			var handle_nid: String = CanvasGeometry.hit_test_connect_handle(w_pt, nodes, node_order, is_vertical, is_bt, zoom)
			if not handle_nid.is_empty():
				_connecting_from_id = handle_nid
				_connect_start_screen = mb.position
				selection.select_single_node(handle_nid)
				selection_visual_changed.emit(true)
				connection_preview_changed.emit(handle_nid, w_pt, "")
				canvas.mouse_default_cursor_shape = Control.CURSOR_CROSS
				canvas.accept_event()
				return

		# 3. 节点本体命中：Ctrl/Cmd 切换多选、Shift 追加多选、双击改名/下钻/强制触发、按住群组平滑拖拽
		var hit_nid: String = CanvasGeometry.hit_test_node(w_pt, nodes, node_order)
		if not hit_nid.is_empty():
			var n_rec: Dictionary = nodes[hit_nid] as Dictionary
			var mod_toggle: bool = FlowEditorInput.has_modifier(mb, FlowEditorInput.MOD_TOGGLE_SELECT)
			var mod_add: bool = FlowEditorInput.has_modifier(mb, FlowEditorInput.MOD_ADDITIVE_SELECT)

			if mod_toggle:
				selection.toggle_node_in_selection(hit_nid)
				selection_visual_changed.emit(true)
				if selection.has_node(hit_nid):
					_arm_group_drag(hit_nid, (n_rec["rect"] as Rect2).position, w_pt, false)
				canvas.accept_event()
				return

			if mod_add:
				selection.add_node_to_selection(hit_nid)
				selection_visual_changed.emit(true)
				_arm_group_drag(hit_nid, (n_rec["rect"] as Rect2).position, w_pt, false)
				canvas.accept_event()
				return

			if FlowEditorInput.is_pointer_double_click(mb, FlowEditorInput.PTR_PRIMARY):
				selection.select_single_node(hit_nid)
				selection_visual_changed.emit(true)
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

			if selection.has_node(hit_nid) and selection.get_selected_count() > 1:
				var had_edge: bool = selection.select_edge("")
				var promoted: bool = selection.promote_primary(hit_nid)
				if had_edge or promoted:
					selection_visual_changed.emit(true)
				_arm_group_drag(hit_nid, (n_rec["rect"] as Rect2).position, w_pt, true)
			else:
				if selection.select_single_node(hit_nid):
					selection_visual_changed.emit(true)
				_arm_group_drag(hit_nid, (n_rec["rect"] as Rect2).position, w_pt, false)
			canvas.accept_event()
			return

		# 4. FSM 回流胶囊跳转中心状态
		var hit_portal: String = CanvasGeometry.hit_test_portal(w_pt, routed_edges)
		if not hit_portal.is_empty() and edge_by_key.has(hit_portal):
			var target_hub: String = str((edge_by_key[hit_portal] as Dictionary)["to"])
			if nodes.has(target_hub):
				selection.select_single_node(target_hub)
				portal_hub_jumped.emit(target_hub)
				canvas.accept_event()
				return

		# 5. 连线命中：单击选中并检视源节点出边规则；双击连线直接插入中间节点
		var hit_edge: String = CanvasGeometry.hit_test_edge(w_pt, routed_edges, zoom)
		if not hit_edge.is_empty() and edge_by_key.has(hit_edge):
			var ed_hit_rec: Dictionary = edge_by_key[hit_edge] as Dictionary
			var ed_from: String = str(ed_hit_rec.get("from", ""))
			var ed_to: String = str(ed_hit_rec.get("to", ""))
			var inspect_nid: String = ed_from if (ed_from != "*" and nodes.has(ed_from)) else (ed_to if nodes.has(ed_to) else "")
			selection.select_single_node(inspect_nid)
			selection.select_edge(hit_edge)
			selection_visual_changed.emit(true)
			if FlowEditorInput.is_pointer_double_click(mb, FlowEditorInput.PTR_PRIMARY) and not read_only_topo and ed_from != "*":
				quick_picker_requested.emit(popup_screen_pos, w_pt, ed_from, ed_to)
			canvas.accept_event()
			return

		# 6. 空白画布：双击弹出快速搜索建点器；单按拖拽启动矩形框选（支持 Shift 追加 / Ctrl 反选）
		if FlowEditorInput.is_pointer_double_click(mb, FlowEditorInput.PTR_PRIMARY) and not read_only_topo:
			selection.finish_marquee()
			if selection.clear_all():
				selection_visual_changed.emit(true)
			quick_picker_requested.emit(popup_screen_pos, w_pt, "", "")
			canvas.accept_event()
			return

		var mq_mode: StringName = CanvasSelectionModel.MARQUEE_REPLACE
		if FlowEditorInput.has_modifier(mb, FlowEditorInput.MOD_TOGGLE_SELECT):
			mq_mode = CanvasSelectionModel.MARQUEE_TOGGLE
		elif FlowEditorInput.has_modifier(mb, FlowEditorInput.MOD_ADDITIVE_SELECT):
			mq_mode = CanvasSelectionModel.MARQUEE_ADD
		if selection.begin_marquee(mb.position, w_pt, mq_mode):
			selection_visual_changed.emit(true)
		canvas.accept_event()
	else:
		if selection.is_marquee_armed():
			selection.finish_marquee()
			selection_visual_changed.emit(true)
			canvas.accept_event()
			return

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

		if not _dragging_anchor_id.is_empty():
			var moved_flag: bool = _drag_moved
			var collapse_nid: String = _dragging_anchor_id if (_collapse_to_single_on_release and not moved_flag) else ""
			_dragging_anchor_id = ""
			_drag_moved = false
			_collapse_to_single_on_release = false
			canvas.mouse_default_cursor_shape = Control.CURSOR_ARROW
			if not collapse_nid.is_empty() and selection.select_single_node(collapse_nid):
				selection_visual_changed.emit(true)
			group_drag_finished.emit(moved_flag)
			canvas.accept_event()


func _arm_group_drag(anchor_id: String, anchor_pos: Vector2, mouse_world: Vector2, collapse_on_click: bool) -> void:
	_dragging_anchor_id = anchor_id
	_drag_anchor_start_pos = anchor_pos
	_drag_mouse_start_world = mouse_world
	_drag_moved = false
	_collapse_to_single_on_release = collapse_on_click


func _handle_context_or_pan_button(canvas: Control, mb: InputEventMouseButton, selection: CanvasSelectionModel, state: Dictionary) -> void:
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
	var popup_screen_pos: Vector2i = _to_popup_screen_pos(canvas, mb.position)

	var hit_nid: String = CanvasGeometry.hit_test_node(w_pt, nodes, node_order)
	if not hit_nid.is_empty() and nodes.has(hit_nid):
		if selection.has_node(hit_nid):
			selection.select_edge("")
			selection.promote_primary(hit_nid)
			selection_visual_changed.emit(true)
		else:
			selection.select_single_node(hit_nid)
			selection_visual_changed.emit(true)
		node_context_menu_requested.emit(popup_screen_pos, hit_nid)
		canvas.accept_event()
		return

	if not read_only_topo:
		var edge_key_hit: String = CanvasGeometry.hit_test_portal(w_pt, routed_edges)
		if edge_key_hit.is_empty():
			edge_key_hit = CanvasGeometry.hit_test_edge(w_pt, routed_edges, zoom)
		if not edge_key_hit.is_empty() and edge_by_key.has(edge_key_hit):
			selection.select_edge(edge_key_hit)
			selection_visual_changed.emit(false)
			edge_context_menu_requested.emit(popup_screen_pos, w_pt, edge_key_hit)
			canvas.accept_event()
			return
		selection.select_edge("")
		selection_visual_changed.emit(false)
		blank_context_menu_requested.emit(popup_screen_pos, w_pt)

	canvas.accept_event()

#endregion


#region 鼠标移动：视口平移、实时矩形框选、群组等距拖拽、磁吸预览与端口悬停

func _handle_mouse_motion(canvas: Control, mm: InputEventMouseMotion, selection: CanvasSelectionModel, state: Dictionary) -> void:
	_last_mouse_screen = mm.position
	_sync_space_physical_state(canvas)

	if _rmb_pressed:
		if not _rmb_panning and mm.position.distance_to(_rmb_press_screen) > RMB_CLICK_SLOP_PX:
			_rmb_panning = true
			canvas.mouse_default_cursor_shape = Control.CURSOR_DRAG
		if _rmb_panning:
			scroll_delta_requested.emit(-mm.relative)
			canvas.accept_event()
			return

	if _is_middle_panning or _space_pan_dragging:
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

	if selection.is_marquee_armed():
		if selection.update_marquee(mm.position, w_cur, nodes, node_order):
			selection_visual_changed.emit(false)
		canvas.accept_event()
		return

	if not _connecting_from_id.is_empty():
		var snap_target: String = CanvasGeometry.hit_test_snap_target(w_cur, _connecting_from_id, nodes, node_order, is_vertical, zoom)
		connection_preview_changed.emit(_connecting_from_id, w_cur, snap_target)
		canvas.accept_event()
		return

	if not _dragging_anchor_id.is_empty() and nodes.has(_dragging_anchor_id):
		var delta_w: Vector2 = w_cur - _drag_mouse_start_world
		if not _drag_moved:
			if delta_w.length_squared() <= DRAG_DEADZONE_SQ:
				return
			_drag_moved = true
			_collapse_to_single_on_release = false
			canvas.mouse_default_cursor_shape = Control.CURSOR_DRAG
			group_drag_started.emit()
		var anchor_next: Vector2 = _drag_anchor_start_pos + delta_w
		if bool(state["snapping_enabled"]) and not FlowEditorInput.has_modifier(mm, FlowEditorInput.MOD_BYPASS_SNAP):
			anchor_next = anchor_next.snapped(Vector2(SNAP_STEP, SNAP_STEP))
		group_dragged_by.emit(anchor_next - _drag_anchor_start_pos)
		canvas.accept_event()
		return

	if _space_pan_armed:
		canvas.mouse_default_cursor_shape = Control.CURSOR_DRAG
		return

	# 优先测试输出端口手柄：即使指针在节点边框外半圆，依然保持所属节点悬停态，杜绝圆点闪烁消失
	var next_port: String = CanvasGeometry.hit_test_connect_handle(w_cur, nodes, node_order, is_vertical, is_bt, zoom) if not read_only_topo else ""
	var next_sub_badge: String = CanvasGeometry.hit_test_subgraph_badge(w_cur, nodes, node_order, live_mode, str(state["hovered_node_id"]), zoom) if next_port.is_empty() else ""
	var next_hn: String = next_port if not next_port.is_empty() else CanvasGeometry.hit_test_node(w_cur, nodes, node_order)
	var next_hp: String = CanvasGeometry.hit_test_portal(w_cur, routed_edges) if next_hn.is_empty() else ""
	var next_he: String = CanvasGeometry.hit_test_edge(w_cur, routed_edges, zoom) if (next_hn.is_empty() and next_hp.is_empty()) else ""

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
