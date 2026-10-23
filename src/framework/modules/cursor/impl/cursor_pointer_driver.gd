class_name CursorPointerDriver
extends Node2D

## 微内核 ②：硬件/软件双模指针本体渲染驱动（Hybrid Hardware/Software Pointer Driver）。[br]
##
## [b]单一职责：[/b][br]
## 1. 接收 [CursorStateResolver] 裁决出的 `(shape, is_pressed)` 并渲染指针本体；[br]
## 2. [b]模式 A（OS 硬件光标）[/b]：调用 `DisplayServer.cursor_set_custom_image`，并根据当前窗口与设计分辨率比例自动执行 DPI 重采样缓存；[br]
## 3. [b]模式 B（画布软件动态光标）[/b]：当样式配置了 `custom_node_scene` 或开启软件模式时，自动隐藏系统硬件鼠标，在顶层画布渲染支持旋转与射击扩散脉冲（[method pulse]）的动态节点，保证硬件与软件指针 100% 互斥。

#region State & Collaborators
var _theme: CursorThemeConfig = null
var _software_preferred: bool = false
var _using_software: bool = false
var _cursor_visible: bool = true
var _confined_active: bool = false
var _is_inside_window: bool = true

var _current_shape: int = -1
var _current_pressed: bool = false
var _cached_dpi_scale: float = 1.0
var _hw_scaled_cache: Dictionary = {} ## "shape_pressed_scale" -> {"tex": ImageTexture, "hotspot": Vector2}

var _sw_pivot: Node2D = null
var _sw_sprite: Sprite2D = null
var _sw_custom_node: Node2D = null
var _sw_custom_scene_path: String = ""
var _pulse_tween: Tween = null
var _wait_spin_deg: float = 0.0
#endregion


#region Lifecycle
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 100
	_sw_pivot = Node2D.new()
	_sw_pivot.name = "SoftwarePointerPivot"
	add_child(_sw_pivot)

	_sw_sprite = Sprite2D.new()
	_sw_sprite.name = "PointerSprite"
	_sw_sprite.centered = false
	_sw_pivot.add_child(_sw_sprite)
	_sw_pivot.visible = false


func _process(delta: float) -> void:
	if _using_software and _sw_pivot != null and _sw_pivot.visible:
		if _current_shape == CursorShapeType.Shape.WAIT:
			_wait_spin_deg = fmod(_wait_spin_deg + 260.0 * delta, 360.0)
			_sw_pivot.rotation_degrees = _wait_spin_deg
		elif not is_zero_approx(_sw_pivot.rotation_degrees):
			_sw_pivot.rotation_degrees = 0.0
#endregion


#region Configuration & State Sync
func set_theme(theme: CursorThemeConfig) -> void:
	var had_theme := (_theme != null)
	_theme = theme
	_hw_scaled_cache.clear()
	if _theme == null and had_theme:
		_reset_os_custom_cursors()
	_force_refresh()


func get_theme() -> CursorThemeConfig:
	return _theme


func set_software_preferred(preferred: bool) -> void:
	if _software_preferred == preferred:
		return
	_software_preferred = preferred
	_force_refresh()


func is_using_software() -> bool:
	return _using_software


func update_cursor_position(canvas_pos: Vector2) -> void:
	if _sw_pivot != null:
		_sw_pivot.position = canvas_pos


func set_window_inside(inside: bool) -> void:
	_is_inside_window = inside
	_sync_software_visibility()


func apply_visibility_and_confinement(visible_flag: bool, confined_flag: bool) -> void:
	_cursor_visible = visible_flag
	_confined_active = confined_flag
	_apply_os_mouse_mode()
	_sync_software_visibility()


## 应用裁决出的目标形状与按压态（内置幂等短路）。
func apply_state(shape: int, is_pressed: bool, dpi_scale: float = 1.0) -> void:
	var clamped_scale := clampf(dpi_scale, 0.5, 4.0)
	var scale_changed := not is_equal_approx(_cached_dpi_scale, clamped_scale)
	if not scale_changed and _current_shape == shape and _current_pressed == is_pressed:
		return

	_current_shape = shape
	_current_pressed = is_pressed
	_cached_dpi_scale = clamped_scale

	# 未配置自定义主题 (_theme == null) 时，保持操作系统原生默认鼠标光标，不覆盖自定义贴图与软件指针
	if _theme == null:
		_using_software = false
		_apply_os_mouse_mode()
		_sync_software_visibility()
		return

	var style := _theme.get_style(shape)
	var should_use_sw := (
		_software_preferred
		or _theme.prefer_software_cursor
		or (style != null and style.uses_software_cursor())
		or shape == CursorShapeType.Shape.WAIT
	)

	_using_software = should_use_sw
	_apply_os_mouse_mode()

	if _using_software:
		_render_software_pointer(style, shape, is_pressed)
	else:
		_render_hardware_pointer(style, shape, is_pressed, clamped_scale)

	_sync_software_visibility()


## 触发一次软件指针或准星的扩散回弹脉冲（若当前为硬件光标则自动短暂平滑缩放软件镜像）。
func pulse(scale_kick: float = 1.35, duration: float = 0.12) -> void:
	if _sw_pivot == null or not is_inside_tree():
		return
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()

	var target_rest := Vector2.ONE
	if _current_pressed and _theme != null:
		var st := _theme.get_style(_current_shape)
		if st != null:
			target_rest = Vector2.ONE * st.pressed_scale

	_sw_pivot.scale = Vector2.ONE * clampf(scale_kick, 0.6, 2.5)
	_pulse_tween = create_tween()
	_pulse_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_property(_sw_pivot, "scale", target_rest, maxf(0.04, duration))
#endregion


#region Internal Hardware & Software Rendering
func _render_software_pointer(style: CursorStyleEntry, shape: int, is_pressed: bool) -> void:
	if _sw_pivot == null:
		return

	var desired_scene: PackedScene = style.custom_node_scene if style != null else null
	var desired_path := desired_scene.resource_path if desired_scene != null else ""

	if desired_scene != null:
		if _sw_custom_node == null or _sw_custom_scene_path != desired_path:
			if is_instance_valid(_sw_custom_node):
				_sw_custom_node.queue_free()
			var inst := desired_scene.instantiate()
			if inst is Node2D:
				_sw_custom_node = inst as Node2D
				_sw_pivot.add_child(_sw_custom_node)
				_sw_custom_scene_path = desired_path
		_sw_sprite.visible = false
	else:
		if is_instance_valid(_sw_custom_node):
			_sw_custom_node.queue_free()
			_sw_custom_node = null
			_sw_custom_scene_path = ""

		var tex: Texture2D = style.get_texture(is_pressed) if style != null else null
		var hs: Vector2 = style.hotspot if style != null else Vector2.ZERO
		_sw_sprite.texture = tex
		_sw_sprite.offset = -hs
		_sw_sprite.visible = (tex != null)

	var base_scale := style.pressed_scale if (is_pressed and style != null) else 1.0
	if _pulse_tween == null or not _pulse_tween.is_running():
		_sw_pivot.scale = Vector2.ONE * base_scale

	if shape != CursorShapeType.Shape.WAIT:
		_sw_pivot.rotation_degrees = 0.0


func _render_hardware_pointer(
	style: CursorStyleEntry,
	shape: int,
	is_pressed: bool,
	dpi_scale: float
) -> void:
	if _is_headless_or_mobile():
		return
	if style == null or style.get_texture(is_pressed) == null:
		return

	var eff_scale := dpi_scale if (_theme != null and _theme.enable_dpi_scaling) else 1.0
	var cache_key := "%d_%d_%.2f" % [shape, 1 if is_pressed else 0, eff_scale]
	var entry: Dictionary
	if _hw_scaled_cache.has(cache_key):
		entry = _hw_scaled_cache[cache_key]
	else:
		entry = _build_scaled_hw_entry(style.get_texture(is_pressed), style.hotspot, eff_scale)
		_hw_scaled_cache[cache_key] = entry

	var scaled_tex: Texture2D = entry["tex"]
	var scaled_hs: Vector2 = entry["hotspot"]
	var ds_shape := CursorShapeType.to_display_server_shape(shape)
	DisplayServer.cursor_set_custom_image(scaled_tex, ds_shape, scaled_hs)
	if ds_shape != DisplayServer.CURSOR_ARROW:
		DisplayServer.cursor_set_custom_image(scaled_tex, DisplayServer.CURSOR_ARROW, scaled_hs)


static func _build_scaled_hw_entry(tex: Texture2D, hotspot: Vector2, dpi_scale: float) -> Dictionary:
	if is_equal_approx(dpi_scale, 1.0) or tex == null:
		return {"tex": tex, "hotspot": hotspot}

	var img := tex.get_image()
	if img == null or img.is_empty():
		return {"tex": tex, "hotspot": hotspot}

	var copy_img := img.duplicate() as Image
	var target_w := clampi(roundi(float(copy_img.get_width()) * dpi_scale), 16, 256)
	var target_h := clampi(roundi(float(copy_img.get_height()) * dpi_scale), 16, 256)
	var actual_ratio_x := float(target_w) / float(maxi(1, copy_img.get_width()))
	var actual_ratio_y := float(target_h) / float(maxi(1, copy_img.get_height()))
	copy_img.resize(target_w, target_h, Image.INTERPOLATE_BILINEAR)

	var new_tex := ImageTexture.create_from_image(copy_img)
	var new_hs := Vector2(
		clampf(roundf(hotspot.x * actual_ratio_x), 0.0, float(target_w - 1)),
		clampf(roundf(hotspot.y * actual_ratio_y), 0.0, float(target_h - 1))
	)
	return {"tex": new_tex, "hotspot": new_hs}


func _apply_os_mouse_mode() -> void:
	if _is_headless_or_mobile():
		return
	var target_mode: DisplayServer.MouseMode
	if not _cursor_visible or _using_software:
		target_mode = (
			DisplayServer.MOUSE_MODE_CONFINED_HIDDEN
			if _confined_active
			else DisplayServer.MOUSE_MODE_HIDDEN
		)
	else:
		target_mode = (
			DisplayServer.MOUSE_MODE_CONFINED
			if _confined_active
			else DisplayServer.MOUSE_MODE_VISIBLE
		)
	if DisplayServer.mouse_get_mode() != target_mode:
		DisplayServer.mouse_set_mode(target_mode)


func _sync_software_visibility() -> void:
	if _sw_pivot != null:
		_sw_pivot.visible = _cursor_visible and _using_software and _is_inside_window


func _force_refresh() -> void:
	var prev_shape := _current_shape if _current_shape >= 0 else CursorShapeType.Shape.DEFAULT
	var prev_pressed := _current_pressed
	_current_shape = -1
	apply_state(prev_shape, prev_pressed, _cached_dpi_scale)


func _reset_os_custom_cursors() -> void:
	if _is_headless_or_mobile():
		return
	for shape_val: int in CursorShapeType.ALL_SHAPES:
		var ds_shape := CursorShapeType.to_display_server_shape(shape_val)
		DisplayServer.cursor_set_custom_image(null, ds_shape)


static func _is_headless_or_mobile() -> bool:
	return DisplayServer.get_name() == "headless" or OS.has_feature("mobile")
#endregion
