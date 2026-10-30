class_name InventoryGridPanel
extends PanelContainer

## 右栏 `6×5` 二维空间战术箱面板预制体脚本（`src/test/inventory/view/component/grid/`）。[br]
##
## [b]设计职责：[/b]绑定 `inventory_grid_panel.tscn` 中的栏头容量标签、旋转按钮与 [InventoryGridBoard] 画布，对外暴露声明式刷新与交互信号。


#region Signals

## 点击「旋转 [R]」按钮。
signal rotate_requested

## 左键选中二维网格内实例。
signal item_selected(uid: int)

## 右键请求将网格实例收回背包。
signal item_quick_triggered(uid: int)

## 拖拽松手落入二维网格坐标。
signal grid_dropped(drag_data: Dictionary, target_pos: Vector2i, is_rotated: bool)

#endregion


#region Node References

@onready var _used_cells_label: Label = %UsedCellsLabel as Label
@onready var _rotate_btn: Button = %RotateButton as Button
@onready var _grid_board: InventoryGridBoard = %GridBoard as InventoryGridBoard

#endregion


#region Lifecycle & Public API

func _ready() -> void:
	if _rotate_btn != null:
		_rotate_btn.pressed.connect(func() -> void: rotate_requested.emit())
	if _grid_board != null:
		_grid_board.item_selected.connect(func(uid: int) -> void:
			item_selected.emit(uid)
		)
		_grid_board.item_quick_triggered.connect(func(uid: int) -> void:
			item_quick_triggered.emit(uid)
		)
		_grid_board.grid_dropped.connect(func(data: Dictionary, pos: Vector2i, rot: bool) -> void:
			grid_dropped.emit(data, pos, rot)
		)


## 初始化绑定底层 [GridItemContainer]、图鉴表与拖拽预判闭包。
func setup_panel(service: InventoryDemoService) -> void:
	if _grid_board != null and service != null:
		_grid_board.setup_board(service.grid, service.catalog, service.can_drop_on_grid)


## 刷新网格占用格数、旋转按钮可用态与矩阵画布焦点。
func render_panel(service: InventoryDemoService) -> void:
	if service == null:
		return
	var sel_cid: StringName = service.state.selected_container_id
	var sel_uid: int = service.state.selected_uid

	if _grid_board != null:
		_grid_board.bind_selection(sel_uid if sel_cid == &"grid" else 0)
	if _used_cells_label != null:
		var total_cells: int = service.grid.width * service.grid.height
		var used_cells: int = total_cells - service.grid.get_free_cell_count()
		_used_cells_label.text = "%d / %d" % [used_cells, total_cells]
	if _rotate_btn != null:
		_rotate_btn.disabled = not service.can_rotate_selected()


## 当拖拽途中按下 `R` 旋转载荷后，通知内部画布刷新占地预览框。
func refresh_active_drag_preview(drag_data: Dictionary) -> void:
	if _grid_board != null:
		_grid_board.refresh_active_drag_preview(drag_data)

#endregion
