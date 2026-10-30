class_name SpineStageView
extends BaseView

## 2.5D「方案 B」舞台顶层 UI 视图根协调器（继承 [BaseView]，自动适配异形屏安全区）。[br]
##
## [b]核心职责：[/b][br]
## 1. 聚合内嵌 [SpineStageHudPanel] 的上行交互信号并向 [SpineStagePresenter] 转发；[br]
## 2. 暴露统一的单向状态渲染入口 [method render_state]。

#region Signals
## 转发武器槽位选择事件。
signal weapon_selected(index: int)
## 转发服饰套装槽位选择事件。
signal outfit_selected(index: int)
## 转发 3D 光影预设切换请求。
signal lighting_toggle_requested
#endregion

#region Node Refs
@onready var _hud_panel: SpineStageHudPanel = %HudPanel as SpineStageHudPanel
#endregion


#region Lifecycle
func _ready() -> void:
	super._ready()
	if _hud_panel != null:
		_hud_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_hud_panel.weapon_selected.connect(_on_weapon_selected)
		_hud_panel.outfit_selected.connect(_on_outfit_selected)
		_hud_panel.lighting_toggle_requested.connect(_on_lighting_toggle_requested)
#endregion


#region Public Render API
## 刷新舞台 HUD 状态显示。
func render_state(state: SpineStageState) -> void:
	if _hud_panel != null:
		_hud_panel.render_state(state)
#endregion


#region Signal Forwarders
func _on_weapon_selected(index: int) -> void:
	weapon_selected.emit(index)


func _on_outfit_selected(index: int) -> void:
	outfit_selected.emit(index)


func _on_lighting_toggle_requested() -> void:
	lighting_toggle_requested.emit()
#endregion
