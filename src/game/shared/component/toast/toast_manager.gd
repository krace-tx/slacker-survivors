class_name ToastManager
extends RefCounted

## 游戏业务层轻量飘字提示调度组件（位于 src/game/shared/component/toast/）。[br]
## 负责在全局画布层（默认 `App.display.get_layer(BaseDisplaySystem.Layer.TOAST)`）展示渐入渐出的居中提示。

#region Constants
const _LOG_TAG: String = "ToastManager"
const _FALLBACK_UI_NODE_PATH: NodePath = ^"UI"
const _DEFAULT_DURATION: float = 2.0
const _BOTTOM_OFFSET_Y: float = 120.0
const _FLOAT_DISTANCE_Y: float = 40.0
const _FADE_IN_DURATION: float = 0.20
const _FADE_OUT_DURATION: float = 0.30
const _PROP_MODULATE_ALPHA: NodePath = ^"modulate:a"
const _PROP_POSITION_Y: NodePath = ^"position:y"
#endregion


#region Public API
## 弹出一条全局 Toast 提示。
## [param message] 提示文本。
## [param duration] 屏幕停留时间（秒）。
static func show(message: String, duration: float = _DEFAULT_DURATION) -> void:
	var target_layer: Node = null
	if App != null and App.display != null:
		target_layer = App.display.get_layer(BaseDisplaySystem.Layer.TOAST)

	if target_layer == null:
		var scene_tree := Engine.get_main_loop() as SceneTree
		if scene_tree != null and scene_tree.current_scene != null:
			target_layer = scene_tree.current_scene.get_node_or_null(_FALLBACK_UI_NODE_PATH)

	if target_layer == null:
		if App != null and App.logger != null:
			App.logger.warn(_LOG_TAG, "No valid target layer to show toast: %s" % message)
		else:
			push_warning("[%s] No valid target layer to show toast: %s" % [_LOG_TAG, message])
		return

	var panel := PanelContainer.new()
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)

	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.position.y -= _BOTTOM_OFFSET_Y
	panel.modulate.a = 0.0
	target_layer.add_child(panel)

	var tween := panel.create_tween()
	tween.tween_property(panel, _PROP_MODULATE_ALPHA, 1.0, _FADE_IN_DURATION)
	tween.tween_interval(maxf(0.1, duration))
	tween.tween_property(panel, _PROP_MODULATE_ALPHA, 0.0, _FADE_OUT_DURATION)
	tween.parallel().tween_property(
		panel,
		_PROP_POSITION_Y,
		panel.position.y - _FLOAT_DISTANCE_Y,
		_FADE_OUT_DURATION
	)
	tween.tween_callback(panel.queue_free)
#endregion
