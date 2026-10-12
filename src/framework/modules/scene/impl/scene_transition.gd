class_name SceneTransition
extends RefCounted

## 极简流式视觉转场控制器 (Fluid Motion Transition Kernel)。
##
## [b]核心设计：[/b]
## 1. [b]连续视觉流[/b]：摒弃黑屏/遮罩掩耳盗铃，新旧场景在空间中并行流式过渡；
## 2. [b]静默首帧预热[/b]：动画启动前静默渲染 1 帧，吃掉 GPU 着色器编译与排版计算峰值；
## 3. [b]成对淡变体系[/b]：
##    - [b]Push[/b]：新场景在顶层优雅淡入覆盖（0.0 -> 1.0）；
##    - [b]Pop[/b]：底层场景保持 100% 实体静止，顶层场景溶解淡出（1.0 -> 0.0）揭开下层；
##    - [b]Replace[/b]：Apple 景深微缩放（0.96x -> 1.0x 聚焦推近 + 旧场景 1.03x 散开淡出）；
## 4. [b]无形防穿透保护[/b]：动画期间在 Layer=100 挂载全屏透明控件拦截快速连点。

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
#endregion


#region Public API
## 执行场景流式转场过渡
func play(from_node: Node, to_node: Node, type: int, op: String = "replace") -> void:
	if type == SceneTransitionType.NONE or not _host_node.is_inside_tree():
		return

	var mode := _resolve_type(type, op)
	if mode == SceneTransitionType.NONE:
		return

	_set_shield(true)

	var vp_size := _host_node.get_viewport().get_visible_rect().size
	var from_item := from_node as CanvasItem if is_instance_valid(from_node) else null
	var to_item := to_node as CanvasItem if is_instance_valid(to_node) else null

	match mode:
		SceneTransitionType.CROSS_PUSH:
			await _animate_push(from_item, to_item)
		SceneTransitionType.CROSS_POP:
			await _animate_pop(from_item, to_item)
		SceneTransitionType.DEPTH_ZOOM:
			await _animate_zoom(from_item, to_item, vp_size)

	_set_shield(false)
#endregion


#region Motion Animations
## Push 进场：新场景在顶层 0.0 -> 1.0 平滑淡入覆盖
func _animate_push(from_item: CanvasItem, to_item: CanvasItem) -> void:
	if to_item:
		to_item.visible = true
		to_item.position = Vector2.ZERO
		to_item.modulate = Color(1, 1, 1, 0.001)

	if from_item:
		from_item.visible = true
		from_item.position = Vector2.ZERO
		from_item.modulate = Color.WHITE

	await _host_node.get_tree().process_frame
	if not is_instance_valid(to_item) and not is_instance_valid(from_item):
		return

	if to_item and is_instance_valid(to_item):
		to_item.modulate.a = 0.0

	var tween := _host_node.create_tween().set_parallel(true)
	if to_item and is_instance_valid(to_item):
		tween.tween_property(to_item, "modulate:a", 1.0, DURATION)\
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if from_item and is_instance_valid(from_item):
		tween.tween_property(from_item, "modulate:a", 0.0, DURATION)\
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)

	await tween.finished
	if to_item and is_instance_valid(to_item):
		to_item.modulate = Color.WHITE
	if from_item and is_instance_valid(from_item):
		from_item.position = Vector2.ZERO
		from_item.modulate = Color.WHITE


## Pop 退场：底层场景保持 100% 实体静止，顶层场景 1.0 -> 0.0 渐隐溶解揭开下层
func _animate_pop(from_item: CanvasItem, to_item: CanvasItem) -> void:
	if to_item:
		to_item.visible = true
		to_item.position = Vector2.ZERO
		to_item.modulate = Color.WHITE

	if from_item:
		from_item.visible = true
		from_item.position = Vector2.ZERO
		from_item.modulate = Color.WHITE

	await _host_node.get_tree().process_frame
	if not is_instance_valid(to_item) and not is_instance_valid(from_item):
		return

	var tween := _host_node.create_tween()
	if from_item and is_instance_valid(from_item):
		tween.tween_property(from_item, "modulate:a", 0.0, DURATION * 0.9)\
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	await tween.finished
	if from_item and is_instance_valid(from_item):
		from_item.position = Vector2.ZERO
		from_item.modulate = Color.WHITE
	if to_item and is_instance_valid(to_item):
		to_item.position = Vector2.ZERO
		to_item.modulate = Color.WHITE


## Replace 景深推近：新场景 0.96x -> 1.0x 聚焦，旧场景 1.03x 散开淡出
func _animate_zoom(from_item: CanvasItem, to_item: CanvasItem, vp_size: Vector2) -> void:
	var center := vp_size * 0.5
	if to_item:
		to_item.visible = true
		to_item.position = Vector2.ZERO
		if to_item is Control:
			(to_item as Control).pivot_offset = center
		to_item.scale = Vector2.ONE
		to_item.modulate.a = 0.001

	if from_item and from_item is Control:
		(from_item as Control).pivot_offset = center

	await _host_node.get_tree().process_frame
	if not is_instance_valid(to_item) and not is_instance_valid(from_item):
		return

	if to_item and is_instance_valid(to_item):
		to_item.scale = Vector2(0.96, 0.96)
		to_item.modulate.a = 0.0

	var tween := _host_node.create_tween().set_parallel(true)
	if to_item and is_instance_valid(to_item):
		tween.tween_property(to_item, "scale", Vector2.ONE, DURATION)\
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(to_item, "modulate:a", 1.0, DURATION)\
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	if from_item and is_instance_valid(from_item):
		from_item.visible = true
		from_item.scale = Vector2.ONE
		from_item.modulate.a = 1.0
		tween.tween_property(from_item, "scale", Vector2(1.03, 1.03), DURATION)\
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(from_item, "modulate:a", 0.0, DURATION)\
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)

	await tween.finished
	if to_item and is_instance_valid(to_item):
		to_item.scale = Vector2.ONE
		to_item.modulate = Color.WHITE
	if from_item and is_instance_valid(from_item):
		from_item.scale = Vector2.ONE
		from_item.modulate = Color.WHITE
#endregion


#region Private Helpers
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
