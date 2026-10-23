class_name DisplaySystem
extends BaseDisplaySystem

## 全局显示设备、视口舞台、异形屏安全区与画布分层系统实现。[br]
##
## [b]核心设计（第一性原理）：[/b][br]
## 1. [b]有状态显示与画布舞台合一[/b]：统一托管五大 [CanvasLayer] 渲染层（Background / Main / Popup / Toast / Top）
##    以及 OS 窗口状态机、分辨率钳制、拉伸策略、异形屏 Safe Area 投影与 VSync 控制；[br]
## 2. [b]防呆窗口状态机与边界钳制[/b]：切换窗口化模式或修改分辨率时，自动将最大尺寸钳制在当前显示器可用工作区内并执行居中对齐，
##    彻底杜绝“低分屏误选 4K 窗口导致标题栏与确认按钮飞出屏幕外”的经典事故；[br]
## 3. [b]异形屏安全区逆矩阵投影与防拉伸约束[/b]：通过物理屏幕安全区与窗口矩形求交 + [method Viewport.get_final_transform] 逆矩阵映射，
##    精确还原逻辑画布空间下的内边距，并支持协同 [method CoordUtils.fit_rect_aspect] 锁定设计宽高比。

#region Module Dependency Manifest
const MODULE_ID: StringName = &"display"
const REQUIRED_MODULES: Array[StringName] = []
const OPTIONAL_MODULES: Array[StringName] = [&"logger"]
#endregion

#region Constants & State
const EPSILON: float = 0.00001
const ERR_INVALID_SIZE: String = "Display.InvalidSize"
const ERR_INVALID_NODE: String = "Display.InvalidNode"

static var _default_safe_area_scale: float = DEFAULT_SAFE_AREA_SCALE
static var _default_lock_design_aspect: bool = false
static var _active_instance: DisplaySystem = null

var _logger: BaseFrameworkLogger
var _layers: Dictionary = {}  ## Layer enum -> CanvasLayer
#endregion

#region Lifecycle
func _init(logger: BaseFrameworkLogger = null) -> void:
	_logger = logger
	_active_instance = self


func initialize() -> Result:
	_active_instance = self
	return Result.ok()


func _ready() -> void:
	_active_instance = self
	_setup_layers()


func set_logger(logger: BaseFrameworkLogger) -> void:
	_logger = logger


func dispose() -> void:
	if _active_instance == self:
		_active_instance = null
	for layer: CanvasLayer in _layers.values():
		if is_instance_valid(layer):
			for child in layer.get_children():
				child.queue_free()
	_layers.clear()
	if is_inside_tree():
		queue_free()
#endregion


#region 1. Canvas Layer Management
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


#region 2. Window Mode State Machine
func set_window_mode(mode: WindowMode, screen_index: int = -1) -> Result:
	if _is_mobile_or_web():
		return Result.ok(get_window_mode())

	if screen_index >= 0 and screen_index < DisplayServer.get_screen_count():
		if DisplayServer.window_get_current_screen() != screen_index:
			DisplayServer.window_set_current_screen(screen_index)

	# 幂等短路保护：若当前已处于目标窗口模式，直接返回，避免 OS 窗口管理器与 Vulkan 交换链重复重建卡死
	if get_window_mode() == mode:
		return Result.ok(mode)

	match mode:
		WindowMode.WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			center_window(screen_index)
		WindowMode.BORDERLESS_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			center_window(screen_index)
		WindowMode.FULLSCREEN:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		WindowMode.EXCLUSIVE_FULLSCREEN:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_:
			return Result.err_ex(
				ERR_INVALID_SIZE,
				"DisplaySystem.set_window_mode failed: unknown mode %d." % int(mode),
				{"mode": int(mode)},
				false,
				null,
				FrameworkError.CATEGORY_PARAM
			)

	return Result.ok(mode)


func get_window_mode() -> WindowMode:
	var raw_mode := DisplayServer.window_get_mode()
	match raw_mode:
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			return WindowMode.EXCLUSIVE_FULLSCREEN
		DisplayServer.WINDOW_MODE_FULLSCREEN:
			return WindowMode.FULLSCREEN
		_:
			var borderless := DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)
			return WindowMode.BORDERLESS_WINDOWED if borderless else WindowMode.WINDOWED


func is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func toggle_fullscreen(use_exclusive: bool = false) -> Result:
	if is_fullscreen():
		return set_window_mode(WindowMode.WINDOWED)
	return set_window_mode(WindowMode.EXCLUSIVE_FULLSCREEN if use_exclusive else WindowMode.FULLSCREEN)
#endregion


#region 3. Resolution, Multi-Monitor & Clamping
func set_resolution(
	size: Vector2i,
	center_on_screen: bool = true,
	clamp_to_usable_screen: bool = true
) -> Result:
	if size.x <= 0 or size.y <= 0:
		return Result.err_ex(
			ERR_INVALID_SIZE,
			"DisplaySystem.set_resolution failed: width and height must be positive (%s)." % str(size),
			{"requested_size": size},
			false,
			null,
			FrameworkError.CATEGORY_PARAM
		)

	if _is_mobile_or_web() or is_fullscreen():
		return Result.ok(DisplayServer.window_get_size())

	var target_size := size
	if clamp_to_usable_screen:
		var usable := get_usable_screen_rect()
		if usable.size.x > 0 and usable.size.y > 0:
			target_size.x = mini(target_size.x, usable.size.x)
			target_size.y = mini(target_size.y, usable.size.y)

	if DisplayServer.window_get_size() != target_size:
		DisplayServer.window_set_size(target_size)
	if center_on_screen:
		center_window()

	return Result.ok(target_size)


func get_resolution() -> Vector2i:
	return DisplayServer.window_get_size()


func get_screen_size(screen_index: int = -1) -> Vector2i:
	var idx := _resolve_screen_index(screen_index)
	return DisplayServer.screen_get_size(idx)


func get_usable_screen_rect(screen_index: int = -1) -> Rect2i:
	var idx := _resolve_screen_index(screen_index)
	return DisplayServer.screen_get_usable_rect(idx)


func center_window(screen_index: int = -1) -> void:
	if _is_mobile_or_web() or is_fullscreen():
		return
	var usable := get_usable_screen_rect(screen_index)
	var win_size := DisplayServer.window_get_size()
	if usable.size.x <= 0 or usable.size.y <= 0:
		return
	@warning_ignore("integer_division")
	var target_pos := usable.position + (usable.size - win_size) / 2
	target_pos.x = maxi(usable.position.x, target_pos.x)
	target_pos.y = maxi(usable.position.y, target_pos.y)
	DisplayServer.window_set_position(target_pos)


func get_available_resolutions(
	presets: Array[Vector2i] = COMMON_RESOLUTIONS,
	screen_index: int = -1
) -> Array[Vector2i]:
	var max_size := get_screen_size(screen_index)
	var out: Array[Vector2i] = []

	for res in presets:
		if res.x <= 0 or res.y <= 0:
			continue
		if max_size.x > 0 and max_size.y > 0 and (res.x > max_size.x or res.y > max_size.y):
			continue
		if not out.has(res):
			out.append(res)

	if max_size.x > 0 and max_size.y > 0 and not out.has(max_size):
		out.append(max_size)

	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var area_a := int(a.x) * int(a.y)
		var area_b := int(b.x) * int(b.y)
		return area_a < area_b if area_a != area_b else a.x < b.x
	)
	return out
#endregion


#region 4. Aspect Ratio, Stretch Mode & Content Scale
func configure_stretch(
	stretch_mode: Window.ContentScaleMode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS,
	stretch_aspect: Window.ContentScaleAspect = Window.CONTENT_SCALE_ASPECT_EXPAND,
	base_size: Vector2i = Vector2i.ZERO,
	scale_factor: float = 1.0
) -> Result:
	var root_window := get_window()
	if not is_instance_valid(root_window):
		return _err_invalid_node("configure_stretch")

	root_window.content_scale_mode = stretch_mode
	root_window.content_scale_aspect = stretch_aspect
	if base_size.x > 0 and base_size.y > 0:
		root_window.content_scale_size = base_size
	root_window.content_scale_factor = clampf(scale_factor, 0.25, 4.0)
	return Result.ok()


func get_design_size() -> Vector2:
	return compute_design_size()


func get_design_aspect() -> float:
	var sz := compute_design_size()
	return sz.x / sz.y


func get_window_aspect() -> float:
	var sz := DisplayServer.window_get_size()
	if sz.x <= 0 or sz.y <= 0:
		return get_design_aspect()
	return float(sz.x) / float(sz.y)
#endregion


#region 5. Display Safe Area & Aspect-Ratio Guard
func set_safe_area_scale(scale_ratio: float) -> void:
	var clamped := clampf(scale_ratio, MIN_SAFE_AREA_SCALE, MAX_SAFE_AREA_SCALE)
	if is_equal_approx(_default_safe_area_scale, clamped):
		return
	_default_safe_area_scale = clamped
	safe_area_changed.emit()


func get_safe_area_scale() -> float:
	return _default_safe_area_scale


func set_lock_design_aspect(locked: bool) -> void:
	if _default_lock_design_aspect == locked:
		return
	_default_lock_design_aspect = locked
	safe_area_changed.emit()


func is_lock_design_aspect() -> bool:
	return _default_lock_design_aspect


## 供同模块内 BaseView 绑定全局安全区配置变更信号（避免隐式访问 App.display）
static func connect_safe_area_changed(callback: Callable) -> void:
	if _active_instance != null and is_instance_valid(_active_instance):
		if not _active_instance.safe_area_changed.is_connected(callback):
			_active_instance.safe_area_changed.connect(callback)


## 供同模块内 BaseView 解绑全局安全区配置变更信号
static func disconnect_safe_area_changed(callback: Callable) -> void:
	if _active_instance != null and is_instance_valid(_active_instance):
		if _active_instance.safe_area_changed.is_connected(callback):
			_active_instance.safe_area_changed.disconnect(callback)


func get_safe_area_rect(viewport: Viewport = null) -> Rect2:
	var vp := viewport if is_instance_valid(viewport) else get_viewport()
	return compute_safe_area_rect(vp)


func get_safe_area_margins(
	viewport: Viewport = null,
	lock_design_aspect: bool = false
) -> Dictionary:
	var vp := viewport if is_instance_valid(viewport) else get_viewport()
	return compute_safe_area_margins(vp, lock_design_aspect)


func apply_safe_area(
	control: Control,
	lock_design_aspect: bool = false
) -> Result:
	return adapt_control_safe_area(control, lock_design_aspect)


## 静态纯计算入口：读取项目设计基准分辨率
static func compute_design_size() -> Vector2:
	var w := float(ProjectSettings.get_setting("display/window/size/viewport_width", 1920))
	var h := float(ProjectSettings.get_setting("display/window/size/viewport_height", 1080))
	return Vector2(maxf(1.0, w), maxf(1.0, h))


## 静态纯计算入口：通过物理安全区求交与 Viewport 逆矩阵投影计算逻辑画布安全区矩形
static func compute_safe_area_rect(viewport: Viewport = null) -> Rect2:
	var win_size_i := DisplayServer.window_get_size()
	var design_size := compute_design_size()
	var logical_rect := viewport.get_visible_rect() if is_instance_valid(viewport) else Rect2(Vector2.ZERO, design_size)

	# 桌面端 DisplayServer.get_display_safe_area() 实际返回扣除系统任务栏的桌面工作区 (usable_rect)，
	# 并非移动端屏幕内的刘海/底部手势条遮挡区；仅在移动端 (iOS / Android) 执行硬件异形屏安全区裁剪。
	if not OS.has_feature("mobile"):
		return logical_rect

	if win_size_i.x <= 0 or win_size_i.y <= 0:
		return logical_rect

	var win_pos_i := DisplayServer.window_get_position()
	var win_screen_rect := Rect2i(win_pos_i, win_size_i)
	var display_safe_rect := DisplayServer.get_display_safe_area()

	if display_safe_rect.size.x <= 0 or display_safe_rect.size.y <= 0 or not display_safe_rect.intersects(win_screen_rect):
		return logical_rect

	var clipped_screen := display_safe_rect.intersection(win_screen_rect)
	var local_win_safe := Rect2(
		Vector2(clipped_screen.position - win_pos_i),
		Vector2(clipped_screen.size)
	)

	if is_instance_valid(viewport):
		var inv_final := viewport.get_final_transform().affine_inverse()
		var p_min := inv_final * local_win_safe.position
		var p_max := inv_final * local_win_safe.end
		var mapped := Rect2(p_min, p_max - p_min).intersection(logical_rect)
		if mapped.size.x > EPSILON and mapped.size.y > EPSILON:
			return mapped
		return logical_rect

	var scale_x := logical_rect.size.x / float(win_size_i.x)
	var scale_y := logical_rect.size.y / float(win_size_i.y)
	var static_rect := Rect2(
		Vector2(local_win_safe.position.x * scale_x, local_win_safe.position.y * scale_y),
		Vector2(local_win_safe.size.x * scale_x, local_win_safe.size.y * scale_y)
	)
	return static_rect.intersection(logical_rect)


## 静态纯计算入口：计算逻辑视口坐标系下的异形屏与全局安全比例四向内边距
static func compute_safe_area_margins(
	viewport: Viewport = null,
	lock_design_aspect: bool = false
) -> Dictionary:
	var design_size := compute_design_size()
	var full_rect := viewport.get_visible_rect() if is_instance_valid(viewport) else Rect2(Vector2.ZERO, design_size)
	var safe_rect := compute_safe_area_rect(viewport)

	var use_aspect_lock: bool = lock_design_aspect or _default_lock_design_aspect
	if use_aspect_lock and design_size.x > EPSILON and design_size.y > EPSILON:
		safe_rect = CoordUtils.fit_rect_aspect(safe_rect, design_size.x / design_size.y)

	if _default_safe_area_scale < 0.9999:
		var scaled_size: Vector2 = safe_rect.size * _default_safe_area_scale
		var inset: Vector2 = (safe_rect.size - scaled_size) * 0.5
		safe_rect = Rect2(safe_rect.position + inset, scaled_size)

	return {
		"left": maxf(0.0, safe_rect.position.x - full_rect.position.x),
		"top": maxf(0.0, safe_rect.position.y - full_rect.position.y),
		"right": maxf(0.0, full_rect.end.x - safe_rect.end.x),
		"bottom": maxf(0.0, full_rect.end.y - safe_rect.end.y),
	}


## 静态适配入口（供同模块内 BaseView 直接调用，无需隐式访问 App.display）
static func adapt_control_safe_area(
	control: Control,
	lock_design_aspect: bool = false
) -> Result:
	if not is_instance_valid(control):
		return _err_invalid_node("apply_safe_area")

	var margins := compute_safe_area_margins(control.get_viewport(), lock_design_aspect)
	var left: float = margins["left"]
	var top: float = margins["top"]
	var right: float = margins["right"]
	var bottom: float = margins["bottom"]

	if control is MarginContainer:
		var mc := control as MarginContainer
		mc.add_theme_constant_override("margin_left", roundi(left))
		mc.add_theme_constant_override("margin_top", roundi(top))
		mc.add_theme_constant_override("margin_right", roundi(right))
		mc.add_theme_constant_override("margin_bottom", roundi(bottom))
	else:
		control.offset_left = left
		control.offset_top = top
		control.offset_right = -right
		control.offset_bottom = -bottom

	return Result.ok(margins)
#endregion


#region 6. VSync, Frame Rate Cap & Hardware Diagnostics
func set_vsync_mode(mode: DisplayServer.VSyncMode) -> void:
	if DisplayServer.window_get_vsync_mode() != mode:
		DisplayServer.window_set_vsync_mode(mode)


func get_vsync_mode() -> DisplayServer.VSyncMode:
	return DisplayServer.window_get_vsync_mode()


func set_max_fps(max_fps: int) -> void:
	var clamped := maxi(0, max_fps)
	if Engine.max_fps != clamped:
		Engine.max_fps = clamped


func get_max_fps() -> int:
	return Engine.max_fps


func get_screen_refresh_rate(screen_index: int = -1) -> float:
	var rate := DisplayServer.screen_get_refresh_rate(_resolve_screen_index(screen_index))
	return rate if rate > 0.0 else 60.0


func get_screen_dpi(screen_index: int = -1) -> int:
	return DisplayServer.screen_get_dpi(_resolve_screen_index(screen_index))


func get_screen_scale(screen_index: int = -1) -> float:
	return DisplayServer.screen_get_scale(_resolve_screen_index(screen_index))
#endregion


#region 7. Viewport Rendering Pipeline Primitives
func set_msaa_2d(mode: Viewport.MSAA) -> void:
	var vp := get_viewport()
	if is_instance_valid(vp) and vp.msaa_2d != mode:
		vp.msaa_2d = mode


func get_msaa_2d() -> Viewport.MSAA:
	var vp := get_viewport()
	return vp.msaa_2d if is_instance_valid(vp) else Viewport.MSAA_DISABLED


func set_msaa_3d(mode: Viewport.MSAA) -> void:
	var vp := get_viewport()
	if is_instance_valid(vp) and vp.msaa_3d != mode:
		vp.msaa_3d = mode


func get_msaa_3d() -> Viewport.MSAA:
	var vp := get_viewport()
	return vp.msaa_3d if is_instance_valid(vp) else Viewport.MSAA_DISABLED


func set_screen_space_aa(mode: Viewport.ScreenSpaceAA) -> void:
	var vp := get_viewport()
	if is_instance_valid(vp) and vp.screen_space_aa != mode:
		vp.screen_space_aa = mode


func get_screen_space_aa() -> Viewport.ScreenSpaceAA:
	var vp := get_viewport()
	return vp.screen_space_aa if is_instance_valid(vp) else Viewport.SCREEN_SPACE_AA_DISABLED


func set_scaling_3d_scale(scale: float) -> void:
	var vp := get_viewport()
	var clamped := clampf(scale, 0.25, 2.0)
	if is_instance_valid(vp) and not is_equal_approx(vp.scaling_3d_scale, clamped):
		vp.scaling_3d_scale = clamped


func get_scaling_3d_scale() -> float:
	var vp := get_viewport()
	return vp.scaling_3d_scale if is_instance_valid(vp) else 1.0


func set_canvas_texture_filter(filter: Viewport.DefaultCanvasItemTextureFilter) -> void:
	var vp := get_viewport()
	if is_instance_valid(vp) and vp.canvas_item_default_texture_filter != filter:
		vp.canvas_item_default_texture_filter = filter


func get_canvas_texture_filter() -> Viewport.DefaultCanvasItemTextureFilter:
	var vp := get_viewport()
	return vp.canvas_item_default_texture_filter if is_instance_valid(vp) else Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
#endregion


#region Private Helpers
static func _resolve_screen_index(screen_index: int) -> int:
	var count := DisplayServer.get_screen_count()
	if count <= 0:
		return 0
	if screen_index < 0 or screen_index >= count:
		return clampi(DisplayServer.window_get_current_screen(), 0, count - 1)
	return screen_index


static func _is_mobile_or_web() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web")


static func _err_invalid_node(method_name: String) -> Result:
	return Result.err_ex(
		ERR_INVALID_NODE,
		"DisplaySystem.%s failed: target node is null or freed." % method_name,
		{},
		false,
		null,
		FrameworkError.CATEGORY_PARAM
	)
#endregion
