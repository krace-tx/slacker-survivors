class_name UISystem
extends BaseUISystem

## 全局 UI 分层与弹窗调度系统。
## 维护 Background、Main、Popup、Toast、Top 五大独立渲染画布层级；
## 提供弹窗堆栈管理、模态暗色遮罩流转与轻量飘字调度。
## 模态弹窗管理见 [ModalStack]。

#region Dependencies & State
var _asset_system: BaseAssetSystem
var _logger: BaseFrameworkLogger

var _layers: Dictionary = {}        ## Layer enum -> CanvasLayer
var _modal_stack: ModalStack        ## 活动模态弹窗栈与遮罩管理器
#endregion

#region Lifecycle
func _init(asset_system: BaseAssetSystem = null, logger: BaseFrameworkLogger = null) -> void:
	_asset_system = asset_system
	_logger = logger
	_modal_stack = ModalStack.new()


func initialize() -> Result:
	return Result.ok()


func _ready() -> void:
	_setup_layers()
	_modal_stack.setup(_layers.get(Layer.POPUP))


func set_asset_system(asset_system: BaseAssetSystem) -> void:
	_asset_system = asset_system


func set_logger(logger: BaseFrameworkLogger) -> void:
	_logger = logger


func dispose() -> void:
	clear_popups()
	super.dispose()
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

#region Modal & Popup Management
func open_popup(path: String, params: Dictionary = {}) -> Result:
	if path.is_empty():
		return Result.err("Popup path is empty.")

	var packed: PackedScene = null
	if _asset_system != null:
		var load_res := await _asset_system.load(path)
		if load_res.is_err():
			_log_error("Failed to load popup: %s - %s" % [path, load_res.error])
			return load_res
		packed = load_res.value as PackedScene
	else:
		if not ResourceLoader.exists(path):
			return Result.err("Popup scene not found: %s" % path)
		packed = ResourceLoader.load(path) as PackedScene

	if packed == null:
		return Result.err("Failed to instantiate popup, invalid PackedScene: %s" % path)

	var instance := packed.instantiate()
	if not (instance is Control):
		instance.queue_free()
		return Result.err("Popup root must be a Control: %s" % path)

	var popup_ctrl := instance as Control
	var popup_layer: CanvasLayer = _layers.get(Layer.POPUP)
	if popup_layer == null:
		instance.queue_free()
		return Result.err("Popup layer is missing.")

	_modal_stack.push(popup_ctrl, params, self)
	return Result.ok(popup_ctrl)


func close_popup(dialog: Control = null) -> void:
	_modal_stack.pop(dialog)


func close_top_popup() -> bool:
	return _modal_stack.pop_top()


func has_modal() -> bool:
	return _modal_stack.has_modal()


func clear_popups() -> void:
	if _modal_stack != null:
		_modal_stack.clear()
#endregion

#region Toast Notification
func show_toast(message: String, duration: float = 2.0) -> void:
	var toast_layer: CanvasLayer = _layers.get(Layer.TOAST)
	if toast_layer == null:
		return

	var panel := PanelContainer.new()
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)

	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.position.y -= 120.0
	panel.modulate.a = 0.0
	toast_layer.add_child(panel)

	# 飘字渐入与向上微移
	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.2)
	tween.tween_interval(duration)
	tween.tween_property(panel, "modulate:a", 0.0, 0.3)
	tween.parallel().tween_property(panel, "position:y", panel.position.y - 40.0, 0.3)
	tween.tween_callback(panel.queue_free)
#endregion

#region Internal Helpers
func _log_error(message: String) -> void:
	if _logger != null:
		_logger.error("UISystem", message)
	else:
		push_error("[UISystem] %s" % message)
#endregion
