@tool
extends RefCounted

## 画布单选、多选与矩形框选状态机（Canvas Single/Multi Selection & Marquee State Model）。[br]
##
## [b]核心职责：[/b][br]
## 1. 统一维护主焦点节点（`primary_node_id`，供右侧检视器展示）、多选节点有序集合（`selected_node_ids` + `O(1)` 哈希表 `selected_lookup`）与选中连线；[br]
## 2. 驱动空白处左键拖拽框选（支持标准覆盖 `MARQUEE_REPLACE`、`Shift` 追加 `MARQUEE_ADD`、`Ctrl/Cmd` 反选切换 `MARQUEE_TOGGLE` 三种集合代数与 `Esc` 无损还原）。

const MARQUEE_REPLACE: StringName = &"replace"
const MARQUEE_ADD: StringName = &"add"
const MARQUEE_TOGGLE: StringName = &"toggle"

const MARQUEE_SLOP_PX: float = 3.5

var primary_node_id: String = ""
var selected_node_ids: Array[String] = []
var selected_lookup: Dictionary = {}
var selected_edge_key: String = ""

var _marquee_armed: bool = false
var _marquee_visible: bool = false
var _marquee_mode: StringName = MARQUEE_REPLACE
var _marquee_start_screen: Vector2 = Vector2.ZERO
var _marquee_anchor_world: Vector2 = Vector2.ZERO
var _marquee_cur_world: Vector2 = Vector2.ZERO
var _pre_marquee_ids: Array[String] = []
var _pre_marquee_primary: String = ""


#region 节点与连线选集操作

func has_node(node_id: String) -> bool:
	return not node_id.is_empty() and selected_lookup.has(node_id)


func get_selected_count() -> int:
	return selected_node_ids.size()


func has_any_selection() -> bool:
	return not selected_node_ids.is_empty() or not selected_edge_key.is_empty()


func clear_all() -> bool:
	var had_any: bool = has_any_selection()
	primary_node_id = ""
	selected_node_ids.clear()
	selected_lookup.clear()
	selected_edge_key = ""
	return had_any


func select_single_node(node_id: String) -> bool:
	var clean_id: String = node_id.strip_edges()
	if clean_id.is_empty():
		var had_nodes: bool = not selected_node_ids.is_empty() or not primary_node_id.is_empty()
		primary_node_id = ""
		selected_node_ids.clear()
		selected_lookup.clear()
		return had_nodes
	if selected_node_ids.size() == 1 and selected_node_ids[0] == clean_id and primary_node_id == clean_id and selected_edge_key.is_empty():
		return false
	selected_edge_key = ""
	primary_node_id = clean_id
	selected_node_ids = [clean_id]
	selected_lookup = {clean_id: true}
	return true


func select_nodes(ids: Array[String], preferred_primary: String = "") -> bool:
	var deduped: Array[String] = []
	var next_lookup: Dictionary = {}
	for raw_id: String in ids:
		var cid: String = raw_id.strip_edges()
		if not cid.is_empty() and not next_lookup.has(cid):
			next_lookup[cid] = true
			deduped.append(cid)

	var next_primary: String = ""
	if not deduped.is_empty():
		var pref: String = preferred_primary.strip_edges()
		next_primary = pref if (not pref.is_empty() and next_lookup.has(pref)) else deduped[deduped.size() - 1]

	var same_primary: bool = (primary_node_id == next_primary)
	var same_list: bool = (selected_node_ids.size() == deduped.size())
	if same_list:
		for i: int in range(deduped.size()):
			if selected_node_ids[i] != deduped[i]:
				same_list = false
				break
	if same_primary and same_list and selected_edge_key.is_empty():
		return false

	selected_edge_key = ""
	primary_node_id = next_primary
	selected_node_ids = deduped
	selected_lookup = next_lookup
	return true


func select_all_nodes(node_order: Array[String]) -> bool:
	return select_nodes(node_order, primary_node_id)


func add_node_to_selection(node_id: String) -> bool:
	var cid: String = node_id.strip_edges()
	if cid.is_empty():
		return false
	selected_edge_key = ""
	if selected_lookup.has(cid):
		if primary_node_id == cid:
			return false
		primary_node_id = cid
		return true
	selected_node_ids.append(cid)
	selected_lookup[cid] = true
	primary_node_id = cid
	return true


func toggle_node_in_selection(node_id: String) -> bool:
	var cid: String = node_id.strip_edges()
	if cid.is_empty():
		return false
	selected_edge_key = ""
	if selected_lookup.has(cid):
		selected_node_ids.erase(cid)
		selected_lookup.erase(cid)
		if primary_node_id == cid:
			primary_node_id = selected_node_ids[selected_node_ids.size() - 1] if not selected_node_ids.is_empty() else ""
		return true
	selected_node_ids.append(cid)
	selected_lookup[cid] = true
	primary_node_id = cid
	return true


func promote_primary(node_id: String) -> bool:
	var cid: String = node_id.strip_edges()
	if cid.is_empty() or not selected_lookup.has(cid) or primary_node_id == cid:
		return false
	primary_node_id = cid
	return true


func select_edge(edge_key: String) -> bool:
	if selected_edge_key == edge_key:
		return false
	selected_edge_key = edge_key
	return true


func prune_invalid(valid_nodes: Dictionary, valid_edges: Dictionary) -> void:
	var kept: Array[String] = []
	var next_lookup: Dictionary = {}
	for nid: String in selected_node_ids:
		if valid_nodes.has(nid) and not next_lookup.has(nid):
			next_lookup[nid] = true
			kept.append(nid)
	selected_node_ids = kept
	selected_lookup = next_lookup
	if not primary_node_id.is_empty() and not selected_lookup.has(primary_node_id):
		primary_node_id = kept[kept.size() - 1] if not kept.is_empty() else ""
	if not selected_edge_key.is_empty() and not valid_edges.has(selected_edge_key):
		selected_edge_key = ""

#endregion


#region 矩形框选生命周期与集合代数

func is_marquee_armed() -> bool:
	return _marquee_armed


func is_marquee_visible() -> bool:
	return _marquee_armed and _marquee_visible


func begin_marquee(screen_pos: Vector2, world_pos: Vector2, mode: StringName) -> bool:
	_marquee_armed = true
	_marquee_visible = false
	_marquee_mode = mode
	_marquee_start_screen = screen_pos
	_marquee_anchor_world = world_pos
	_marquee_cur_world = world_pos
	_pre_marquee_ids = selected_node_ids.duplicate()
	_pre_marquee_primary = primary_node_id
	var changed: bool = not selected_edge_key.is_empty()
	selected_edge_key = ""
	if mode == MARQUEE_REPLACE and not selected_node_ids.is_empty():
		primary_node_id = ""
		selected_node_ids.clear()
		selected_lookup.clear()
		changed = true
	return changed


func update_marquee(
	screen_pos: Vector2,
	world_pos: Vector2,
	nodes: Dictionary,
	node_order: Array[String]
) -> bool:
	if not _marquee_armed:
		return false
	_marquee_cur_world = world_pos
	if not _marquee_visible:
		if screen_pos.distance_to(_marquee_start_screen) < MARQUEE_SLOP_PX:
			return false
		_marquee_visible = true

	var tl_w: Vector2 = _marquee_anchor_world.min(_marquee_cur_world)
	var sz_w: Vector2 = (_marquee_cur_world - _marquee_anchor_world).abs()
	var box_world := Rect2(tl_w, sz_w)

	var hit_ids: Array[String] = []
	var hit_set: Dictionary = {}
	for nid: String in node_order:
		if nodes.has(nid):
			var n_rect: Rect2 = (nodes[nid] as Dictionary)["rect"] as Rect2
			if box_world.intersects(n_rect):
				hit_ids.append(nid)
				hit_set[nid] = true

	var next_ids: Array[String] = []
	match _marquee_mode:
		MARQUEE_ADD:
			next_ids = _pre_marquee_ids.duplicate()
			for hid: String in hit_ids:
				if not next_ids.has(hid):
					next_ids.append(hid)
		MARQUEE_TOGGLE:
			for pid: String in _pre_marquee_ids:
				if not hit_set.has(pid):
					next_ids.append(pid)
			for hid: String in hit_ids:
				if not _pre_marquee_ids.has(hid):
					next_ids.append(hid)
		_:
			next_ids = hit_ids

	var pref_primary: String = _pre_marquee_primary
	if not hit_ids.is_empty():
		pref_primary = hit_ids[hit_ids.size() - 1]
	select_nodes(next_ids, pref_primary)
	return true


func finish_marquee() -> bool:
	var was_vis: bool = _marquee_visible
	_marquee_armed = false
	_marquee_visible = false
	_pre_marquee_ids.clear()
	_pre_marquee_primary = ""
	return was_vis


func cancel_marquee() -> bool:
	if not _marquee_armed:
		return false
	_marquee_armed = false
	_marquee_visible = false
	select_nodes(_pre_marquee_ids, _pre_marquee_primary)
	_pre_marquee_ids.clear()
	_pre_marquee_primary = ""
	return true


func get_marquee_screen_rect(zoom: float, scroll_offset: Vector2) -> Rect2:
	if not is_marquee_visible():
		return Rect2()
	var z: float = maxf(zoom, 0.15)
	var p0: Vector2 = _marquee_anchor_world * z - scroll_offset
	var p1: Vector2 = _marquee_cur_world * z - scroll_offset
	return Rect2(p0.min(p1), (p1 - p0).abs())

#endregion
