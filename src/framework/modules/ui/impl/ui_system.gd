class_name UISystem
extends BaseUISystem

## 全局 UI 画布分层与安全区系统实现。
## 维护 Background、Main、Popup、Toast、Top 五大独立渲染画布层级；
## 提供屏幕安全区（Safe Area）适配计算工具。

#region Dependencies & State
var _asset_system: BaseAssetSystem
var _logger: BaseFrameworkLogger
var _layers: Dictionary = {}  ## Layer enum -> CanvasLayer
#endregion

#region Lifecycle
func _init(asset_system: BaseAssetSystem = null, logger: BaseFrameworkLogger = null) -> void:
	_asset_system = asset_system
	_logger = logger


func initialize() -> Result:
	return Result.ok()


func _ready() -> void:
	_setup_layers()


func set_asset_system(asset_system: BaseAssetSystem) -> void:
	_asset_system = asset_system


func set_logger(logger: BaseFrameworkLogger) -> void:
	_logger = logger


func dispose() -> void:
	for layer: CanvasLayer in _layers.values():
		if is_instance_valid(layer):
			for child in layer.get_children():
				child.queue_free()
	_layers.clear()
	if is_inside_tree():
		queue_free()
#endregion

#region Layers Management
func _setup_layers() -> void:
	var layer_configs := {
		Layer.BACKGROUND: "BackgroundLayer",
		Layer.MAIN: "MainLayer",
		Layer.POPUP: "PopupLayer",
		Layer.TOAST: "ToastLayer",
		Layer.TOP: "TopLayer",
	}

	for layer_val: int in layer_configs:
		var layer_name: String = layer_configs[layer_val]
		var canvas := CanvasLayer.new()
		canvas.layer = layer_val
		canvas.name = layer_name
		add_child(canvas)
		_layers[layer_val] = canvas


func get_layer(layer_type: int) -> CanvasLayer:
	return _layers.get(layer_type, null)
#endregion

#region Safe Area Adaptation
func get_safe_area_margins() -> Dictionary:
	var safe_area := DisplayServer.get_display_safe_area()
	var window_size := DisplayServer.window_get_size()
	return {
		"left": float(safe_area.position.x),
		"top": float(safe_area.position.y),
		"right": float(max(0, window_size.x - safe_area.end.x)),
		"bottom": float(max(0, window_size.y - safe_area.end.y))
	}


func apply_safe_area(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	var margins := get_safe_area_margins()
	control.offset_left = margins.left
	control.offset_top = margins.top
	control.offset_right = -margins.right
	control.offset_bottom = -margins.bottom
#endregion
