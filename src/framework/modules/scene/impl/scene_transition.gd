class_name SceneTransition
extends RefCounted

## 极简流式视觉转场控制器 (Fluid Motion Transition Kernel)。[br]
##
## [b]核心设计（第一性原理）：[/b][br]
## 1. [b]多根节点视觉树穿透（Visual Root Harvesting）[/b]：自动兼容根节点为纯 [Node]（如下挂 [code]$Background[/code] 与 [code]$UI[/code]）
##    或直接继承 [CanvasItem] 的场景，提取其所有活动顶层画布节点同步驱动并行补间，并在转场后无损还原初始变换快照；[br]
## 2. [b]静默首帧预热[/b]：动画启动前静默渲染 1 帧，吃掉 GPU 着色器编译与 UI 容器排版计算峰值；[br]
## 3. [b]成对淡变与景深体系[/b]：[br]
##    - [b]Push ([constant SceneTransitionType.CROSS_PUSH])[/b]：新场景在顶层优雅淡入覆盖（0.0 -> 1.0），旧场景柔和淡出；[br]
##    - [b]Pop ([constant SceneTransitionType.CROSS_POP])[/b]：底层场景保持 100% 实体静止，顶层场景溶解淡出（1.0 -> 0.0）揭开下层；[br]
##    - [b]Replace ([constant SceneTransitionType.DEPTH_ZOOM])[/b]：Apple 景深微缩放（0.96x -> 1.0x 聚焦推近 + 旧场景 1.03x 散开淡出）；[br]
## 4. [b]无形防穿透保护（Invisible Shield）[/b]：动画期间在 Layer=100 挂载全屏透明控件拦截快速连点。

#region Constants
const DURATION := 0.22 ## 标准动画时长 (秒)
#endregion

#region Private Members
var _host_node: Node
var _shield_layer: CanvasLayer
var _shield: Control
#endregion


#region Lifecycle
func _init(host_node: Node) -> void:
	_host_node = host_node
	_build_shield()


func _build_shield() -> void:
	_shield_layer = CanvasLayer.new()
	_shield_layer.layer = 100
	_shield_layer.name = "TransitionShield"

	_shield = Control.new()
	_shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shield.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shield.visible = false

	_shield_layer.add_child(_shield)
	NodeUtils.mount_required(_shield_layer, _host_node, "ShieldLayer")


func dispose() -> void:
	if is_instance_valid(_shield_layer):
		_shield_layer.queue_free()
	_shield_layer = null
	_shield = null
#endregion


#region Public API
## 执行场景流式转场过渡
func play(from_node: Node, to_node: Node, type: int, op: String = "replace") -> void:
	if type == SceneTransitionType.NONE or not is_instance_valid(_host_node) or not _host_node.is_inside_tree():
		return

	var mode := _resolve_type(type, op)
	if mode == SceneTransitionType.NONE:
		return

	var from_items := _collect_visual_items(from_node)
	var to_items := _collect_visual_items(to_node)
	if from_items.is_empty() and to_items.is_empty():
		return

	var from_snapshots := _capture_snapshots(from_items)
	var to_snapshots := _capture_snapshots(to_items)

	_set_shield(true)
	var vp_size := _host_node.get_viewport().get_visible_rect().size

	match mode:
		SceneTransitionType.CROSS_PUSH:
			await _animate_push(from_items, to_items)
		SceneTransitionType.CROSS_POP:
			await _animate_pop(from_items, to_items)
		SceneTransitionType.DEPTH_ZOOM:
			await _animate_zoom(from_items, to_items, vp_size)

	_restore_snapshots(to_snapshots)
	_restore_snapshots(from_snapshots)
	_set_shield(false)
#endregion


#region Motion Animations
## Push 进场：新场景在顶层 0.0 -> 1.0 平滑淡入覆盖，旧场景柔和淡化
func _animate_push(from_items: Array[CanvasItem], to_items: Array[CanvasItem]) -> void:
	for item in to_items:
		item.modulate.a = 0.001

	await _host_node.get_tree().process_frame
	if not is_instance_valid(_host_node) or not _host_node.is_inside_tree():
		return

	var has_target := false
	var tween := _host_node.create_tween().set_parallel(true)

	for item in to_items:
		if is_instance_valid(item):
			item.modulate.a = 0.0
			tween.tween_property(item, "modulate:a", 1.0, DURATION)\
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			has_target = true

	for item in from_items:
		if is_instance_valid(item):
			tween.tween_property(item, "modulate:a", 0.0, DURATION)\
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
			has_target = true

	if has_target:
		await tween.finished
	else:
		tween.kill()


## Pop 退场：底层场景保持 100% 实体静止，顶层场景 1.0 -> 0.0 渐隐溶解揭开下层
func _animate_pop(_from_items: Array[CanvasItem], _to_items: Array[CanvasItem]) -> void:
	await _host_node.get_tree().process_frame
	if not is_instance_valid(_host_node) or not _host_node.is_inside_tree():
		return

	var has_target := false
	var tween := _host_node.create_tween().set_parallel(true)

	for item in _from_items:
		if is_instance_valid(item):
			tween.tween_property(item, "modulate:a", 0.0, DURATION * 0.9)\
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			has_target = true

	if has_target:
		await tween.finished
	else:
		tween.kill()


## Replace 景深推近：新场景 0.96x -> 1.0x 聚焦，旧场景 1.03x 散开淡出
func _animate_zoom(from_items: Array[CanvasItem], to_items: Array[CanvasItem], vp_size: Vector2) -> void:
	var center := vp_size * 0.5
	for item in to_items:
		if item is Control:
			(item as Control).pivot_offset = center
		item.modulate.a = 0.001

	for item in from_items:
		if item is Control:
			(item as Control).pivot_offset = center

	await _host_node.get_tree().process_frame
	if not is_instance_valid(_host_node) or not _host_node.is_inside_tree():
		return

	var has_target := false
	var tween := _host_node.create_tween().set_parallel(true)

	for item in to_items:
		if is_instance_valid(item):
			item.scale = Vector2(0.96, 0.96)
			item.modulate.a = 0.0
			tween.tween_property(item, "scale", Vector2.ONE, DURATION)\
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tween.tween_property(item, "modulate:a", 1.0, DURATION)\
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			has_target = true

	for item in from_items:
		if is_instance_valid(item):
			item.scale = Vector2.ONE
			item.modulate.a = 1.0
			tween.tween_property(item, "scale", Vector2(1.03, 1.03), DURATION)\
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
			tween.tween_property(item, "modulate:a", 0.0, DURATION)\
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
			has_target = true

	if has_target:
		await tween.finished
	else:
		tween.kill()
#endregion


#region Private Visual Harvesting & Snapshot Helpers
## 递归收集场景下的所有顶层可视画布根（当遇到第一个可见的 CanvasItem 即作为控制根加入，不再深入其子级，防止双重叠加透明度或缩放）。
func _collect_visual_items(node: Node) -> Array[CanvasItem]:
	var items: Array[CanvasItem] = []
	if not is_instance_valid(node):
		return items
	_harvest_canvas_roots(node, items)
	return items


func _harvest_canvas_roots(node: Node, out_items: Array[CanvasItem]) -> void:
	if node is CanvasItem:
		var ci := node as CanvasItem
		if ci.visible:
			out_items.append(ci)
		return
	if node is CanvasLayer and not (node as CanvasLayer).visible:
		return
	if node is Window:
		return
	for child in node.get_children():
		_harvest_canvas_roots(child, out_items)


func _capture_snapshots(items: Array[CanvasItem]) -> Array[Dictionary]:
	var snaps: Array[Dictionary] = []
	snaps.resize(items.size())
	for i in items.size():
		var item := items[i]
		var snap := {
			"item": item,
			"modulate": item.modulate,
		}
		if item is Control:
			var ctrl := item as Control
			snap["scale"] = ctrl.scale
			snap["pivot_offset"] = ctrl.pivot_offset
			snap["position"] = ctrl.position
		elif item is Node2D:
			var n2d := item as Node2D
			snap["scale"] = n2d.scale
			snap["position"] = n2d.position
		snaps[i] = snap
	return snaps


func _restore_snapshots(snaps: Array[Dictionary]) -> void:
	for snap in snaps:
		var item: CanvasItem = snap.get("item")
		if not is_instance_valid(item):
			continue
		item.modulate = snap["modulate"]
		if item is Control:
			var ctrl := item as Control
			ctrl.scale = snap["scale"]
			ctrl.pivot_offset = snap["pivot_offset"]
			ctrl.position = snap["position"]
		elif item is Node2D:
			var n2d := item as Node2D
			n2d.scale = snap["scale"]
			n2d.position = snap["position"]


func _resolve_type(type: int, op: String) -> int:
	if type != SceneTransitionType.AUTO:
		return type
	match op:
		"push":
			return SceneTransitionType.CROSS_PUSH
		"pop":
			return SceneTransitionType.CROSS_POP
		"replace":
			return SceneTransitionType.DEPTH_ZOOM
		_:
			return SceneTransitionType.CROSS_PUSH


func _set_shield(active: bool) -> void:
	if is_instance_valid(_shield):
		_shield.visible = active
		_shield.mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
#endregion
