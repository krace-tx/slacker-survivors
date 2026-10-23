class_name CursorThemeConfig
extends Resource

## 鼠标光标主题与粒子特效配置表（Cursor Theme & VFX Configuration Resource）。[br]
##
## [b]核心定位：[/b][br]
## 1. 继承自 [Resource]，可保存为 `res://src/resources/presets/prs_cursor_theme.tres` 在编辑器 Inspector 中可视化配置；[br]
## 2. 集中定义 11 种语义光标形状（[CursorStyleEntry]）、高分屏 DPI 自适应重采样策略、移动拖尾粒子与点击爆裂特效参数；[br]
## 3. 内置 [method create_procedural_default] 程序化矢量/像素风格默认光标生成器，在未导入外部美术贴图时亦可开箱即用。

#region Exports
@export_group("Cursor Styles")
## 各语义形状对应的视觉样式条目列表。
@export var styles: Array[CursorStyleEntry] = []

## 是否根据当前窗口分辨率与设计分辨率比例自动缩放硬件光标尺寸与热点（防止 4K 显示器下硬件光标缩成蚂蚁大小）。
@export var enable_dpi_scaling: bool = true

## 是否全局偏好使用画布软件光标模式（开启后所有状态均支持平滑缩放过渡与脉冲动画；关闭时静态状态优先走 0 延迟 OS 硬件光标）。
@export var prefer_software_cursor: bool = false


@export_group("Trail & Click Particle VFX")
## 是否启用鼠标移动星尘拖尾粒子与丝带轨迹。
@export var enable_trail_vfx: bool = true

## 是否启用鼠标点击瞬间的水波纹扩散与粒子迸发特效。
@export var enable_click_vfx: bool = true

## 可选：自定义移动拖尾特效预制体（`.tscn`）；为空时自动使用内置程序化星尘拖尾发射器。
@export var trail_vfx_scene: PackedScene = null

## 可选：自定义点击爆裂特效预制体（`.tscn`）；为空时自动使用内置 8 槽位环形池水波纹与粒子迸发器。
@export var click_vfx_scene: PackedScene = null

## 内置移动拖尾与丝带的主色调。
@export var trail_color: Color = Color(0.42, 0.88, 1.0, 0.85)

## 内置点击爆裂粒子与扩散环的主色调。
@export var click_color: Color = Color(1.0, 0.85, 0.35, 0.95)
#endregion


#region Lookup API
## 查找指定语义形状的样式条目（未配置时回退至 DEFAULT 条目；若均未配置则返回 null）。
func get_style(shape: int) -> CursorStyleEntry:
	var fallback: CursorStyleEntry = null
	for entry: CursorStyleEntry in styles:
		if entry == null:
			continue
		if int(entry.shape) == shape:
			return entry
		if entry.shape == CursorShapeType.Shape.DEFAULT and fallback == null:
			fallback = entry
	return fallback
#endregion


#region Procedural Built-in Theme Factory
## 生成一套高辨识度的程序化默认光标主题（涵盖全部 11 种语义形状与按压态，零外部贴图依赖，开箱即用）。
static func create_procedural_default() -> CursorThemeConfig:
	var theme := CursorThemeConfig.new()
	theme.enable_dpi_scaling = true
	theme.enable_trail_vfx = true
	theme.enable_click_vfx = true

	# 1. DEFAULT (青白科技箭头)
	theme.styles.append(CursorStyleEntry.create(
		CursorShapeType.Shape.DEFAULT,
		_build_arrow_tex(Color(0.95, 0.98, 1.0), Color(0.20, 0.78, 1.0), 1.0),
		_build_arrow_tex(Color(0.75, 0.95, 1.0), Color(0.10, 0.62, 0.95), 0.86),
		Vector2(3.0, 3.0)
	))
	# 2. POINTER (琥珀金点击手型指针)
	theme.styles.append(CursorStyleEntry.create(
		CursorShapeType.Shape.POINTER,
		_build_pointer_tex(Color(1.0, 0.92, 0.45), Color(0.95, 0.60, 0.15), false),
		_build_pointer_tex(Color(1.0, 0.78, 0.25), Color(0.90, 0.40, 0.10), true),
		Vector2(10.0, 4.0)
	))
	# 3. FORBIDDEN (猩红禁止圆环)
	theme.styles.append(CursorStyleEntry.create(
		CursorShapeType.Shape.FORBIDDEN,
		_build_forbidden_tex(Color(1.0, 0.32, 0.36)),
		_build_forbidden_tex(Color(0.85, 0.18, 0.22)),
		Vector2(16.0, 16.0)
	))
	# 4. GRAB (张开抓取四角爪)
	theme.styles.append(CursorStyleEntry.create(
		CursorShapeType.Shape.GRAB,
		_build_grab_tex(Color(0.55, 0.95, 0.68), false),
		_build_grab_tex(Color(0.35, 0.88, 0.52), true),
		Vector2(16.0, 16.0)
	))
	# 5. GRABBED (收紧抓取锁定框)
	theme.styles.append(CursorStyleEntry.create(
		CursorShapeType.Shape.GRABBED,
		_build_grab_tex(Color(0.35, 0.92, 0.55), true),
		_build_grab_tex(Color(0.25, 0.82, 0.45), true),
		Vector2(16.0, 16.0)
	))
	# 6. CROSSHAIR (翡翠绿战术十字准星 — 默认启用软件模式支持射击扩散脉冲)
	theme.styles.append(CursorStyleEntry.create(
		CursorShapeType.Shape.CROSSHAIR,
		_build_crosshair_tex(Color(0.32, 1.0, 0.62), false),
		_build_crosshair_tex(Color(0.65, 1.0, 0.35), true),
		Vector2(16.0, 16.0),
		true
	))
	# 7. ATTACK (绯红战斗锁定菱形准星 — 软件模式)
	theme.styles.append(CursorStyleEntry.create(
		CursorShapeType.Shape.ATTACK,
		_build_crosshair_tex(Color(1.0, 0.36, 0.32), true),
		_build_crosshair_tex(Color(1.0, 0.68, 0.22), true),
		Vector2(16.0, 16.0),
		true
	))
	# 8. INTERACT (品红/紫晶菱形交互光环)
	theme.styles.append(CursorStyleEntry.create(
		CursorShapeType.Shape.INTERACT,
		_build_diamond_tex(Color(0.82, 0.52, 1.0), false),
		_build_diamond_tex(Color(0.95, 0.72, 1.0), true),
		Vector2(16.0, 16.0)
	))
	# 9. INSPECT (天蓝放大镜观察圆环)
	theme.styles.append(CursorStyleEntry.create(
		CursorShapeType.Shape.INSPECT,
		_build_inspect_tex(Color(0.45, 0.85, 1.0)),
		_build_inspect_tex(Color(0.70, 0.95, 1.0)),
		Vector2(14.0, 14.0)
	))
	# 10. IBEAM (文本输入工字光标)
	theme.styles.append(CursorStyleEntry.create(
		CursorShapeType.Shape.IBEAM,
		_build_ibeam_tex(Color(0.92, 0.96, 1.0)),
		_build_ibeam_tex(Color(0.55, 0.85, 1.0)),
		Vector2(16.0, 16.0)
	))
	# 11. WAIT (双色沙漏/等待圆环)
	theme.styles.append(CursorStyleEntry.create(
		CursorShapeType.Shape.WAIT,
		_build_wait_tex(Color(1.0, 0.78, 0.32)),
		_build_wait_tex(Color(1.0, 0.78, 0.32)),
		Vector2(16.0, 16.0)
	))

	return theme


static func _build_arrow_tex(fill: Color, rim: Color, scale_ratio: float) -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var max_len := int(roundf(22.0 * scale_ratio))
	for y in range(2, 2 + max_len):
		var dy := y - 2
		var row_w := int(roundf(float(dy) * 0.68))
		for x in range(2, 2 + row_w + 1):
			if y == 2 + max_len - 1 or x == 2 or x == 2 + row_w:
				img.set_pixel(x, y, rim)
			else:
				img.set_pixel(x, y, fill)
	return ImageTexture.create_from_image(img)


static func _build_pointer_tex(fill: Color, rim: Color, compact: bool) -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var top_y := 6 if compact else 3
	for y in range(top_y, 18):
		for x in range(9, 13):
			img.set_pixel(x, y, rim if (x == 9 or x == 12 or y == top_y) else fill)
	for y in range(14, 26):
		for x in range(7, 21):
			var is_edge := (x == 7 or x == 20 or y == 14 or y == 25)
			img.set_pixel(x, y, rim if is_edge else fill)
	return ImageTexture.create_from_image(img)


static func _build_forbidden_tex(col: Color) -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var center := Vector2(16.0, 16.0)
	for y in range(32):
		for x in range(32):
			var p := Vector2(float(x), float(y))
			var d := p.distance_to(center)
			var on_ring := d >= 9.5 and d <= 12.5
			var on_slash := d <= 11.0 and absf(float(x - y)) <= 1.8
			if on_ring or on_slash:
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


static func _build_grab_tex(col: Color, closed: bool) -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var pad := 9 if closed else 5
	var arm := 5
	for i in range(arm):
		for t in range(2):
			img.set_pixel(pad + i, pad + t, col)
			img.set_pixel(pad + t, pad + i, col)
			img.set_pixel(31 - pad - i, pad + t, col)
			img.set_pixel(31 - pad - t, pad + i, col)
			img.set_pixel(pad + i, 31 - pad - t, col)
			img.set_pixel(pad + t, 31 - pad - i, col)
			img.set_pixel(31 - pad - i, 31 - pad - t, col)
			img.set_pixel(31 - pad - t, 31 - pad - i, col)
	if closed:
		for y in range(14, 19):
			for x in range(14, 19):
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


static func _build_crosshair_tex(col: Color, tight: bool) -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var gap := 3 if tight else 5
	var outer := 13
	for i in range(gap, outer + 1):
		for t in range(-1, 2):
			var a := 1.0 if t == 0 else 0.65
			var c := Color(col.r, col.g, col.b, a)
			img.set_pixel(16 + i, 16 + t, c)
			img.set_pixel(16 - i, 16 + t, c)
			img.set_pixel(16 + t, 16 + i, c)
			img.set_pixel(16 + t, 16 - i, c)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			img.set_pixel(16 + dx, 16 + dy, Color(1.0, 1.0, 1.0, 0.95))
	return ImageTexture.create_from_image(img)


static func _build_diamond_tex(col: Color, filled: bool) -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(32):
			var md := absi(x - 16) + absi(y - 16)
			if (filled and md <= 9) or (md >= 8 and md <= 10):
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


static func _build_inspect_tex(col: Color) -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var center := Vector2(13.0, 13.0)
	for y in range(32):
		for x in range(32):
			var d := Vector2(float(x), float(y)).distance_to(center)
			if d >= 7.0 and d <= 9.5:
				img.set_pixel(x, y, col)
	for i in range(7):
		for t in range(-1, 2):
			img.set_pixel(clampi(19 + i + t, 0, 31), clampi(19 + i, 0, 31), col)
	return ImageTexture.create_from_image(img)


static func _build_ibeam_tex(col: Color) -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in range(6, 26):
		img.set_pixel(16, y, col)
		img.set_pixel(15, y, col)
	for x in range(11, 21):
		img.set_pixel(x, 6, col)
		img.set_pixel(x, 7, col)
		img.set_pixel(x, 24, col)
		img.set_pixel(x, 25, col)
	return ImageTexture.create_from_image(img)


static func _build_wait_tex(col: Color) -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var center := Vector2(16.0, 16.0)
	for y in range(32):
		for x in range(32):
			var p := Vector2(float(x), float(y))
			var d := p.distance_to(center)
			if d >= 8.5 and d <= 11.5:
				var angle := atan2(p.y - 16.0, p.x - 16.0)
				if absf(angle) < 2.2:
					img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)
#endregion
