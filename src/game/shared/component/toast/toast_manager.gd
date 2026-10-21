class_name ToastManager
extends RefCounted

## 游戏业务层轻量飘字提示调度组件（位于 src/game/shared/component/toast/）。[br]
## 负责在全局画布层 (默认 App.display.get_layer(BaseDisplaySystem.Layer.TOAST)) 展示渐入渐出的居中提示。

## 弹出一条全局 Toast 提示。
## [param message] 提示文本。
## [param duration] 屏幕停留时间（秒）。
static func show(message: String, duration: float = 2.0) -> void:
	var target_layer: CanvasLayer = null
	if App != null and App.display != null:
		target_layer = App.display.get_layer(BaseDisplaySystem.Layer.TOAST)

	if target_layer == null:
		var scene_tree := Engine.get_main_loop() as SceneTree
		if scene_tree != null and scene_tree.current_scene != null:
			target_layer = scene_tree.current_scene.get_node_or_null("UI") as CanvasLayer

	if target_layer == null:
		push_warning("[ToastManager] No valid target layer to show toast: %s" % message)
		return

	var panel := PanelContainer.new()
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)

	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.position.y -= 120.0
	panel.modulate.a = 0.0
	target_layer.add_child(panel)

	var tween := panel.create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.2)
	tween.tween_interval(duration)
	tween.tween_property(panel, "modulate:a", 0.0, 0.3)
	tween.parallel().tween_property(panel, "position:y", panel.position.y - 40.0, 0.3)
	tween.tween_callback(panel.queue_free)
