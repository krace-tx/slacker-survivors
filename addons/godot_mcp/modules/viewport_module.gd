@tool
extends "res://addons/godot_mcp/modules/base_module.gd"

## 编辑器视口捕获与图像渲染模块 (Viewport Module)
## 抓取 2D 视口或特定节点的渲染画面，为大模型多模态视觉 (Vision) 提供输入支撑。


func register_commands(registry: CommandRegistry) -> void:
	# 1. viewport.capture_2d
	registry.register_command(
		"viewport.capture_2d",
		"Capture the current 2D editor viewport screenshot as base64 or save to path",
		{
			"save_path": {"type": "string", "default": "", "description": "Optional file path to save PNG (e.g. res://screenshot.png)"},
			"return_base64": {"type": "bool", "default": true, "description": "Whether to return image base64 data string"},
		},
		_capture_viewport_2d
	)
	registry.register_alias("capture_viewport_2d", "viewport.capture_2d")

	# 2. viewport.capture_node
	registry.register_command(
		"viewport.capture_node",
		"Capture a specific 2D/UI node bounding area from the editor viewport",
		{
			"node_path": {"type": "string", "required": true, "description": "Target CanvasItem / Control node path"},
			"save_path": {"type": "string", "default": "", "description": "Optional file path to save PNG"},
			"return_base64": {"type": "bool", "default": true, "description": "Whether to return image base64 data string"},
		},
		_capture_node
	)
	registry.register_alias("capture_node", "viewport.capture_node")


func _capture_viewport_2d(p: Dictionary) -> Variant:
	var iface := ctx.get_interface()
	if iface == null:
		return RpcError.execution_error("EditorInterface unavailable")

	var vp: SubViewport = iface.get_editor_viewport_2d()
	if vp == null:
		return RpcError.execution_error("2D editor viewport unavailable")

	var tex := vp.get_texture()
	if tex == null:
		return RpcError.execution_error("Viewport texture is null")

	var image := tex.get_image()
	if image == null or image.is_empty():
		return RpcError.execution_error("Failed to capture viewport image")

	return _process_image(image, p)


func _capture_node(p: Dictionary) -> Variant:
	var node := ctx.resolve_node(p.node_path)
	if node == null:
		return RpcError.not_found("Node not found: %s" % p.node_path)

	if not node is CanvasItem:
		return RpcError.invalid_params("Node '%s' is not a CanvasItem or Control" % p.node_path)

	var iface := ctx.get_interface()
	if iface == null:
		return RpcError.execution_error("EditorInterface unavailable")

	var vp: SubViewport = iface.get_editor_viewport_2d()
	if vp == null:
		return RpcError.execution_error("2D editor viewport unavailable")

	var tex := vp.get_texture()
	if tex == null:
		return RpcError.execution_error("Viewport texture is null")

	var image := tex.get_image()
	if image == null or image.is_empty():
		return RpcError.execution_error("Failed to capture viewport image")

	# 计算节点在视口中的区域范围
	var canvas_item: CanvasItem = node
	var xform := canvas_item.get_global_transform_with_canvas()
	var rect := Rect2(Vector2.ZERO, Vector2(100, 100))

	if canvas_item is Control:
		rect = Rect2(Vector2.ZERO, canvas_item.size)
	elif canvas_item is Sprite2D and canvas_item.texture != null:
		rect = Rect2(-canvas_item.texture.get_size() / 2.0, canvas_item.texture.get_size())

	var screen_rect := Rect2(xform * rect.position, xform.basis_xform(rect.size).abs())

	# 边界裁剪防越界
	var img_rect := Rect2i(0, 0, image.get_width(), image.get_height())
	var crop_rect := Rect2i(screen_rect).intersection(img_rect)

	var target_image := image
	if crop_rect.size.x > 0 and crop_rect.size.y > 0:
		target_image = image.get_region(crop_rect)

	return _process_image(target_image, p)


func _process_image(image: Image, p: Dictionary) -> Variant:
	var save_path: String = p.get("save_path", "")
	var return_b64: bool = p.get("return_base64", true)

	if not save_path.is_empty():
		var dir := save_path.get_base_dir()
		if not DirAccess.dir_exists_absolute(dir):
			DirAccess.make_dir_recursive_absolute(dir)
		var save_err := image.save_png(save_path)
		if save_err != OK:
			return RpcError.execution_error("Failed to save image to '%s', error: %d" % [save_path, save_err])

	var res := {
		"width": image.get_width(),
		"height": image.get_height(),
		"save_path": save_path,
	}

	if return_b64:
		var buf := image.save_png_to_buffer()
		res["base64_png"] = Marshalls.raw_to_base64(buf)

	return res
