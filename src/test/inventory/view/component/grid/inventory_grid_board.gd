class_name InventoryGridBoard
extends Control

## 二维空间矩阵战术箱交互画布脚本（`src/test/inventory/view/component/grid/`）。[br]
##
## [b]设计职责：[/b][br]
## 1. 作为 `inventory_grid_panel.tscn` 内的声明式子节点，复用 `.tscn` 注入的 `StyleBoxFlat` 资源绘制 `6×5` 格点与 `W×H` 物品块；[br]
## 2. 悬停或选中时自动调用 [method GridItemContainer.get_adjacent_uids] 点亮正交邻接共鸣边；[br]
## 3. 拖拽悬停期间渲染磁吸对齐的翡翠绿/珊瑚红实时占地预览框。


#region Signals

## 左键选中网格内某件实例（点击空格时 `uid = 0`）。
signal item_selected(uid: int)

## 右键请求将网格内实例快捷收回主背包。
signal item_quick_triggered(uid: int)

## 拖拽松手落入网格目标锚点与朝向。
signal grid_dropped(drag_data: Dictionary, target_pos: Vector2i, is_rotated: bool)

#endregion


#region Exports & Constants

const DEFAULT_CELL_PX: float = 82.0
const _COL_NEIGHBOR := Color(0.204, 0.855, 0.725, 0.95)

@export_group("Grid Dimensions")
## 单格像素边长（在 `.tscn` 中可直接调节）。
@export var cell_px: float = DEFAULT_CELL_PX

@export_group("Declarative Styles & Prefabs")
## 底层单格空底板样式。
@export var cell_style: StyleBoxFlat = null
## 物品块常态样式。
@export var tile_normal_style: StyleBoxFlat = null
## 物品块悬停样式。
@export var tile_hover_style: StyleBoxFlat = null
## 物品块选中样式。
@export var tile_selected_style: StyleBoxFlat = null
## 正交邻接物品共鸣样式。
@export var tile_neighbor_style: StyleBoxFlat = null
## 拖拽合法落位预览样式。
@export var preview_valid_style: StyleBoxFlat = null
## 拖拽冲突拒绝预览样式。
@export var preview_reject_style: StyleBoxFlat = null
## 拖拽跟随预览徽章预制体（`inventory_drag_badge.tscn`）。
@export var drag_badge_scene: PackedScene = null

#endregion


#region State

var _grid: GridItemContainer = null
var _catalog: Dictionary = {}
var _drop_validator: Callable = Callable()

var _selected_uid: int = 0
var _hovered_uid: int = 0

var _preview_active: bool = false
var _preview_rect: Rect2i = Rect2i()
var _preview_valid: bool = false

#endregion


#region Setup & Refresh

func _ready() -> void:
	mouse_exited.connect(_on_mouse_exited)


## 绑定底层 [GridItemContainer]、图鉴表与落位预判闭包。
func setup_board(
	p_grid: GridItemContainer,
	p_catalog: Dictionary,
	p_drop_validator: Callable
) -> void:
	_grid = p_grid
	_catalog = p_catalog
	_drop_validator = p_drop_validator
	if _grid != null:
		custom_minimum_size = Vector2(
			float(_grid.width) * cell_px,
			float(_grid.height) * cell_px
		)
	queue_redraw()


## 同步外部选中 UID 并重绘网格。
func bind_selection(p_selected_uid: int) -> void:
	_selected_uid = p_selected_uid
	queue_redraw()


## 当外部在拖拽途中按下 `R` 翻转拖拽载荷朝向后，刷新实时占地预览。
func refresh_active_drag_preview(drag_data: Dictionary) -> void:
	if not _preview_active or _grid == null:
		return
	_update_preview_from_mouse(get_local_mouse_position(), drag_data)
	queue_redraw()

#endregion


#region Input & Drag-and-Drop

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _preview_active:
		_preview_active = false
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if _grid == null:
		return

	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		var cell: Vector2i = _pixel_to_cell(mm.position)
		var next_hover: int = _grid.get_cell_uid(cell.x, cell.y)
		if next_hover != _hovered_uid:
			_hovered_uid = next_hover
			mouse_default_cursor_shape = (
				Control.CURSOR_POINTING_HAND if _hovered_uid > 0 else Control.CURSOR_ARROW
			)
			queue_redraw()
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if not mb.pressed:
			return
		var click_cell: Vector2i = _pixel_to_cell(mb.position)
		var hit_uid: int = _grid.get_cell_uid(click_cell.x, click_cell.y)
		if mb.button_index == MOUSE_BUTTON_LEFT:
			item_selected.emit(hit_uid)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and hit_uid > 0:
			item_selected.emit(hit_uid)
			item_quick_triggered.emit(hit_uid)
			accept_event()


func _get_drag_data(at_position: Vector2) -> Variant:
	if _grid == null:
		return null
	var cell: Vector2i = _pixel_to_cell(at_position)
	var uid: int = _grid.get_cell_uid(cell.x, cell.y)
	if uid <= 0:
		return null

	var st: ItemStack = _grid.get_item_by_uid(uid)
	if st == null:
		return null
	var vis: InventoryItemVisualConfig = _catalog.get(st.item_id, null) as InventoryItemVisualConfig
	var rect: Rect2i = _grid.get_item_rect(uid)
	item_selected.emit(uid)

	if vis != null and drag_badge_scene != null:
		var preview: InventoryDragBadge = drag_badge_scene.instantiate() as InventoryDragBadge
		if preview != null:
			var preview_size := Vector2(
				clampf(float(rect.size.x) * cell_px * 0.86, 64.0, 196.0),
				clampf(float(rect.size.y) * cell_px * 0.86, 64.0, 196.0)
			)
			preview.setup_badge(vis, st.count, preview_size, st.rotated)
			set_drag_preview(preview)

	return {
		"inv_drag": true,
		"src_id": _grid.container_id,
		"slot_index": -1,
		"uid": st.uid,
		"item_id": st.item_id,
		"count": st.count,
		"rotated": st.rotated,
	}


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if _grid == null or not (data is Dictionary):
		return false
	var payload: Dictionary = data as Dictionary
	if not bool(payload.get("inv_drag", false)):
		return false

	_update_preview_from_mouse(at_position, payload)
	queue_redraw()
	return true


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if _grid == null or not (data is Dictionary):
		_preview_active = false
		queue_redraw()
		return
	var payload: Dictionary = data as Dictionary
	_update_preview_from_mouse(at_position, payload)
	var target_pos: Vector2i = _preview_rect.position
	var rot: bool = bool(payload.get("rotated", false))
	_preview_active = false
	queue_redraw()
	grid_dropped.emit(payload, target_pos, rot)

#endregion


#region Custom Matrix Rendering

func _draw() -> void:
	if _grid == null:
		return

	# 1. 使用声明式 cell_style 绘制底层单格矩阵
	if cell_style != null:
		for y: int in _grid.height:
			for x: int in _grid.width:
				var c_rect := Rect2(
					Vector2(float(x) * cell_px, float(y) * cell_px),
					Vector2(cell_px, cell_px)
				).grow(-2.5)
				draw_style_box(cell_style, c_rect)

	# 2. 计算当前焦点物品的正交邻接集合
	var focus_uid: int = _hovered_uid if _hovered_uid > 0 else _selected_uid
	var neighbor_uids: Array[int] = []
	if focus_uid > 0:
		neighbor_uids = _grid.get_adjacent_uids(focus_uid, false)

	# 3. 绘制已放置的异形尺寸物品块
	var stacks: Array[ItemStack] = _grid.get_all_stacks()
	var font: Font = ThemeDB.fallback_font

	for st: ItemStack in stacks:
		var grid_rect: Rect2i = _grid.get_item_rect(st.uid)
		if grid_rect.size.x <= 0 or grid_rect.size.y <= 0:
			continue
		var tile_rect := Rect2(
			Vector2(float(grid_rect.position.x) * cell_px, float(grid_rect.position.y) * cell_px),
			Vector2(float(grid_rect.size.x) * cell_px, float(grid_rect.size.y) * cell_px)
		).grow(-2.5)

		var vis: InventoryItemVisualConfig = _catalog.get(st.item_id, null) as InventoryItemVisualConfig
		var accent: Color = vis.accent_color if vis != null else Color(0.6, 0.7, 0.8)
		var is_sel: bool = st.uid == _selected_uid
		var is_hov: bool = st.uid == _hovered_uid
		var is_nbr: bool = neighbor_uids.has(st.uid)

		var chosen_style: StyleBoxFlat = tile_normal_style
		if is_sel and tile_selected_style != null:
			chosen_style = tile_selected_style
		elif is_nbr and tile_neighbor_style != null:
			chosen_style = tile_neighbor_style
		elif is_hov and tile_hover_style != null:
			chosen_style = tile_hover_style

		if chosen_style != null:
			draw_style_box(chosen_style, tile_rect)

		# 柔和稀有度底色浸润与顶部细饰条
		draw_rect(tile_rect.grow(-3.0), Color(accent.r, accent.g, accent.b, 0.05), true)
		draw_rect(
			Rect2(tile_rect.position + Vector2(12.0, 2.0), Vector2(maxf(12.0, tile_rect.size.x - 24.0), 2.5)),
			Color(accent.r, accent.g, accent.b, 0.90),
			true
		)

		if vis != null:
			var pad_x: float = minf(14.0, tile_rect.size.x * 0.14)
			var pad_y: float = minf(14.0, tile_rect.size.y * 0.14)
			var icon_rect := Rect2(
				tile_rect.position + Vector2(pad_x, pad_y + 2.0),
				tile_rect.size - Vector2(pad_x * 2.0, pad_y * 2.0 + 4.0)
			)
			InventoryIconPainter.draw_icon(self, icon_rect, vis.icon_kind, accent, st.rotated, 1.0)

			if vis.spec != null and not vis.spec.rotatable and (grid_rect.size.x > 1 or grid_rect.size.y > 1):
				draw_circle(
					tile_rect.position + Vector2(tile_rect.size.x - 10.0, 11.0),
					3.0,
					Color(0.66, 0.54, 0.98, 0.85)
				)

		if st.count > 1 and font != null:
			draw_string(
				font,
				Vector2(tile_rect.position.x, tile_rect.position.y + tile_rect.size.y - 7.0),
				str(st.count),
				HORIZONTAL_ALIGNMENT_RIGHT,
				tile_rect.size.x - 8.0,
				13,
				Color(0.95, 0.98, 1.0, 0.96)
			)

	# 4. 正交邻接公共边界能量桥
	if focus_uid > 0 and not neighbor_uids.is_empty():
		var focus_r: Rect2i = _grid.get_item_rect(focus_uid)
		for n_uid: int in neighbor_uids:
			var nbr_r: Rect2i = _grid.get_item_rect(n_uid)
			_draw_shared_edge_bridge(focus_r, nbr_r)

	# 5. 拖拽实时占地预览框
	if _preview_active and _preview_rect.size.x > 0 and _preview_rect.size.y > 0:
		var p_style: StyleBoxFlat = preview_valid_style if _preview_valid else preview_reject_style
		if p_style != null:
			var p_px_rect := Rect2(
				Vector2(float(_preview_rect.position.x) * cell_px, float(_preview_rect.position.y) * cell_px),
				Vector2(float(_preview_rect.size.x) * cell_px, float(_preview_rect.size.y) * cell_px)
			).grow(-2.0)
			draw_style_box(p_style, p_px_rect)

#endregion


#region Spatial & Edge Helpers

func _pixel_to_cell(local_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(local_pos.x / cell_px)),
		int(floor(local_pos.y / cell_px))
	)


func _update_preview_from_mouse(local_pos: Vector2, payload: Dictionary) -> void:
	var item_id: StringName = payload.get("item_id", &"") as StringName
	var vis: InventoryItemVisualConfig = _catalog.get(item_id, null) as InventoryItemVisualConfig
	var spec: ItemSpec = vis.spec if vis != null else null
	var rot: bool = bool(payload.get("rotated", false))
	if spec != null and not spec.rotatable:
		rot = false
		payload["rotated"] = false

	var eff: Vector2i = spec.get_effective_size(rot) if spec != null else Vector2i.ONE
	var raw_x: int = int(floor((local_pos.x - float(eff.x - 1) * cell_px * 0.5) / cell_px))
	var raw_y: int = int(floor((local_pos.y - float(eff.y - 1) * cell_px * 0.5) / cell_px))
	var clamped_x: int = clampi(raw_x, 0, maxi(0, _grid.width - eff.x))
	var clamped_y: int = clampi(raw_y, 0, maxi(0, _grid.height - eff.y))
	var anchor := Vector2i(clamped_x, clamped_y)

	_preview_active = true
	_preview_rect = Rect2i(anchor, eff)
	if _drop_validator.is_valid():
		_preview_valid = bool(_drop_validator.call(payload, anchor, rot))
	else:
		_preview_valid = true


func _draw_shared_edge_bridge(a: Rect2i, b: Rect2i) -> void:
	if a.position.x + a.size.x == b.position.x or b.position.x + b.size.x == a.position.x:
		var shared_x: int = b.position.x if a.position.x + a.size.x == b.position.x else a.position.x
		var y0: int = maxi(a.position.y, b.position.y)
		var y1: int = mini(a.position.y + a.size.y, b.position.y + b.size.y)
		if y1 > y0:
			var px_x: float = float(shared_x) * cell_px
			var mid_y: float = float(y0 + y1) * 0.5 * cell_px
			var half_span: float = minf(16.0, float(y1 - y0) * cell_px * 0.28)
			draw_line(
				Vector2(px_x, mid_y - half_span),
				Vector2(px_x, mid_y + half_span),
				_COL_NEIGHBOR,
				3.5,
				true
			)
	elif a.position.y + a.size.y == b.position.y or b.position.y + b.size.y == a.position.y:
		var shared_y: int = b.position.y if a.position.y + a.size.y == b.position.y else a.position.y
		var x0: int = maxi(a.position.x, b.position.x)
		var x1: int = mini(a.position.x + a.size.x, b.position.x + b.size.x)
		if x1 > x0:
			var px_y: float = float(shared_y) * cell_px
			var mid_x: float = float(x0 + x1) * 0.5 * cell_px
			var half_span_x: float = minf(16.0, float(x1 - x0) * cell_px * 0.28)
			draw_line(
				Vector2(mid_x - half_span_x, px_y),
				Vector2(mid_x + half_span_x, px_y),
				_COL_NEIGHBOR,
				3.5,
				true
			)


func _on_mouse_exited() -> void:
	var dirty: bool = false
	if _hovered_uid != 0:
		_hovered_uid = 0
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		dirty = true
	if _preview_active:
		_preview_active = false
		dirty = true
	if dirty:
		queue_redraw()

#endregion
