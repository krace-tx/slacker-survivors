class_name OtomeTerraceView
extends BaseView

## 乙女向户外庭院「晴风湖畔 · 花树咖啡露台」顶层视图协调器（继承 [BaseView]，自动适配安全区）。[br]
##
## [b]核心职责：[/b][br]
## 1. 聚合内嵌 [OtomeHudPanel] 的上行交互信号并向 [OtomeTerracePresenter] 转发；[br]
## 2. 暴露统一的单向状态渲染入口 [method render_state] 与悬浮气泡坐标投影入口 [method update_hotspot_bubbles]。

#region Signals
signal hotspot_clicked(hotspot_id: int)
signal outfit_cycle_requested
signal expr_cycle_requested
signal greet_requested
signal interact_requested
signal weather_toggle_requested
signal camera_toggle_requested
signal choice_selected(choice_index: int)
#endregion

#region Node Refs
@onready var _hud_panel: OtomeHudPanel = %HudPanel as OtomeHudPanel
#endregion


#region Lifecycle
func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _hud_panel != null:
		_hud_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_hud_panel.hotspot_clicked.connect(func(id: int) -> void: hotspot_clicked.emit(id))
		_hud_panel.outfit_cycle_requested.connect(func() -> void: outfit_cycle_requested.emit())
		_hud_panel.expr_cycle_requested.connect(func() -> void: expr_cycle_requested.emit())
		_hud_panel.greet_requested.connect(func() -> void: greet_requested.emit())
		_hud_panel.interact_requested.connect(func() -> void: interact_requested.emit())
		_hud_panel.weather_toggle_requested.connect(func() -> void: weather_toggle_requested.emit())
		_hud_panel.camera_toggle_requested.connect(func() -> void: camera_toggle_requested.emit())
		_hud_panel.choice_selected.connect(func(idx: int) -> void: choice_selected.emit(idx))
#endregion


#region Public Render API
## 从场景级 [SpinePool] 为 HUD 内嵌的 [OtomeBustOverlay] 挂载近景动态半身像。
func mount_bust_from_pool(pool: SpinePool, skel_res: Resource) -> void:
	if _hud_panel != null:
		_hud_panel.mount_bust_from_pool(pool, skel_res)


## 释放 HUD 内嵌近景动态半身像持有的 [SpineController]。
func release_bust_spine() -> void:
	if _hud_panel != null:
		_hud_panel.release_bust_spine()


## 刷新庭院 HUD 状态显示。
func render_state(state: OtomeTerraceState) -> void:
	if _hud_panel != null:
		_hud_panel.render_state(state)


## 更新 3D 热点悬浮气泡的屏幕投影位置与邻近高亮态。
func update_hotspot_bubbles(
	screen_positions: Array[Vector2],
	nearby_id: int,
	hide_all: bool
) -> void:
	if _hud_panel != null:
		_hud_panel.update_hotspot_bubbles(screen_positions, nearby_id, hide_all)
#endregion
