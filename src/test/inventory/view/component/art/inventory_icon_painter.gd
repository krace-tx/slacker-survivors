class_name InventoryIconPainter
extends RefCounted

## 极简几何矢量物品图标绘制器（`src/test/inventory/view/component/art/`）。[br]
##
## [b]设计职责：[/b][br]
## 基于 [CanvasItem] 原生抗锯齿多边形与折线原语绘制高辨识度的现代暗色风矢量图标，
## 自动适配 `1×1` 正方槽位（45° 斜置构图）与二维网格 `W×H` 异形占地（随 90° 旋转姿态同步转向）。


#region Public Drawing Entry

## 在 [param canvas] 的目标区域 [param rect] 内绘制指定 [param icon_kind] 矢量图标。[br]
## [param accent] 主色调。[br]
## [param is_rotated] 是否处于二维网格 90 度旋转姿态。[br]
## [param alpha] 整体不透明度倍率。
static func draw_icon(
	canvas: CanvasItem,
	rect: Rect2,
	icon_kind: int,
	accent: Color,
	is_rotated: bool = false,
	alpha: float = 1.0
) -> void:
	if canvas == null or rect.size.x <= 4.0 or rect.size.y <= 4.0:
		return

	var center: Vector2 = rect.get_center()
	var min_dim: float = minf(rect.size.x, rect.size.y)
	var max_dim: float = maxf(rect.size.x, rect.size.y)
	var is_elongated: bool = max_dim > min_dim * 1.35

	# 正方格内长柄武器采用经典 35° 斜置构图；长条网格内沿主轴垂直或水平舒展
	var weapon_angle: float = 0.62
	var weapon_radius: float = min_dim * 0.38
	if is_elongated:
		weapon_angle = PI * 0.5 if is_rotated or rect.size.x > rect.size.y else 0.0
		var wing_cap: float = (
			min_dim * 0.54 if icon_kind == InventoryItemVisualConfig.IconKind.AXE else min_dim * 0.88
		)
		weapon_radius = minf(max_dim * 0.40, wing_cap)

	var base_radius: float = min_dim * 0.36
	var col_main := Color(accent.r, accent.g, accent.b, accent.a * alpha)
	var col_light := Color(
		lerpf(accent.r, 1.0, 0.55),
		lerpf(accent.g, 1.0, 0.55),
		lerpf(accent.b, 1.0, 0.55),
		alpha
	)
	var col_dark := Color(accent.r * 0.48, accent.g * 0.50, accent.b * 0.58, alpha)
	var col_steel := Color(0.80, 0.85, 0.93, alpha)
	var col_handle := Color(0.38, 0.43, 0.53, alpha)

	match icon_kind:
		InventoryItemVisualConfig.IconKind.COIN:
			_draw_coin(canvas, center, base_radius, col_main, col_light, col_dark)
		InventoryItemVisualConfig.IconKind.GEM:
			_draw_gem(canvas, center, base_radius, col_main, col_light, col_dark)
		InventoryItemVisualConfig.IconKind.SWORD:
			_draw_sword(canvas, center, weapon_radius, weapon_angle, col_steel, col_light, col_main, col_handle, false)
		InventoryItemVisualConfig.IconKind.RUNE_SWORD:
			_draw_sword(canvas, center, weapon_radius, weapon_angle, col_main, col_light, col_light, col_dark, true)
		InventoryItemVisualConfig.IconKind.AXE:
			_draw_axe(canvas, center, weapon_radius, weapon_angle, col_main, col_light, col_steel, col_handle)
		InventoryItemVisualConfig.IconKind.SHIELD:
			var sh_angle: float = PI * 0.5 if (is_elongated and is_rotated) else 0.0
			_draw_shield(canvas, center, base_radius * 1.06, sh_angle, col_main, col_light, col_dark)
		InventoryItemVisualConfig.IconKind.RING:
			_draw_ring(canvas, center, base_radius * 0.92, col_main, col_light)
		InventoryItemVisualConfig.IconKind.TOTEM:
			var tm_r: float = minf(max_dim * 0.36, min_dim * 0.62) if is_elongated else base_radius
			_draw_totem(canvas, center, tm_r, col_main, col_light, col_dark)
		InventoryItemVisualConfig.IconKind.POTION:
			_draw_potion(canvas, center, base_radius, col_main, col_light, col_steel)
		InventoryItemVisualConfig.IconKind.ORE:
			_draw_ore(canvas, center, base_radius, col_main, col_light, col_dark)
		InventoryItemVisualConfig.IconKind.MARK_WEAPON:
			_draw_sword(canvas, center, base_radius * 0.92, 0.62, col_main, col_main, col_main, col_main, false)
		InventoryItemVisualConfig.IconKind.MARK_SHIELD:
			_draw_shield(canvas, center, base_radius * 0.88, 0.0, col_main, col_main, col_dark)
		InventoryItemVisualConfig.IconKind.MARK_RING:
			_draw_ring(canvas, center, base_radius * 0.80, col_main, col_main)

#endregion


#region Vector Shapes

static func _draw_coin(
	canvas: CanvasItem,
	c: Vector2,
	r: float,
	col_main: Color,
	col_light: Color,
	col_dark: Color
) -> void:
	canvas.draw_circle(c, r, col_dark)
	canvas.draw_circle(c, r * 0.86, col_main)
	canvas.draw_arc(c, r * 0.86, -PI * 0.85, -PI * 0.15, 20, col_light, 1.8, true)
	var inner_diamond: PackedVector2Array = _xform([
		Vector2(0.0, -0.42), Vector2(0.34, 0.0), Vector2(0.0, 0.42), Vector2(-0.34, 0.0)
	], c, r, 0.0)
	canvas.draw_colored_polygon(inner_diamond, col_light)


static func _draw_gem(
	canvas: CanvasItem,
	c: Vector2,
	r: float,
	col_main: Color,
	col_light: Color,
	col_dark: Color
) -> void:
	var outer: PackedVector2Array = _xform([
		Vector2(0.0, -1.0), Vector2(0.76, -0.26), Vector2(0.48, 0.92),
		Vector2(-0.48, 0.92), Vector2(-0.76, -0.26)
	], c, r, 0.0)
	canvas.draw_colored_polygon(outer, col_dark)
	var body: PackedVector2Array = _xform([
		Vector2(0.0, -0.92), Vector2(0.68, -0.24), Vector2(0.42, 0.82),
		Vector2(-0.42, 0.82), Vector2(-0.68, -0.24)
	], c, r, 0.0)
	canvas.draw_colored_polygon(body, col_main)
	var crown: PackedVector2Array = _xform([
		Vector2(0.0, -0.92), Vector2(0.42, -0.22), Vector2(0.0, 0.24), Vector2(-0.42, -0.22)
	], c, r, 0.0)
	canvas.draw_colored_polygon(crown, col_light)


static func _draw_sword(
	canvas: CanvasItem,
	c: Vector2,
	r: float,
	angle: float,
	col_blade: Color,
	col_edge: Color,
	col_guard: Color,
	col_grip: Color,
	with_rune: bool
) -> void:
	var grip: PackedVector2Array = _xform([
		Vector2(-0.07, 0.44), Vector2(0.07, 0.44), Vector2(0.06, 0.86), Vector2(-0.06, 0.86)
	], c, r, angle)
	canvas.draw_colored_polygon(grip, col_grip)

	var blade_left: PackedVector2Array = _xform([
		Vector2(0.0, -1.02), Vector2(0.0, 0.36), Vector2(-0.17, 0.34), Vector2(-0.13, -0.68)
	], c, r, angle)
	var blade_right: PackedVector2Array = _xform([
		Vector2(0.0, -1.02), Vector2(0.13, -0.68), Vector2(0.17, 0.34), Vector2(0.0, 0.36)
	], c, r, angle)
	canvas.draw_colored_polygon(blade_left, col_edge)
	canvas.draw_colored_polygon(blade_right, col_blade)

	var guard: PackedVector2Array = _xform([
		Vector2(-0.40, 0.32), Vector2(0.40, 0.32), Vector2(0.32, 0.46), Vector2(-0.32, 0.46)
	], c, r, angle)
	canvas.draw_colored_polygon(guard, col_guard)

	var pommel_pos: Vector2 = _pt(Vector2(0.0, 0.92), c, r, angle)
	canvas.draw_circle(pommel_pos, maxf(2.5, r * 0.11), col_guard)

	if with_rune:
		var r1: Vector2 = _pt(Vector2(0.0, -0.48), c, r, angle)
		var r2: Vector2 = _pt(Vector2(0.0, 0.12), c, r, angle)
		canvas.draw_line(r1, r2, Color(1.0, 1.0, 1.0, col_edge.a * 0.90), 2.0, true)
		var gem_c: Vector2 = _pt(Vector2(0.0, 0.39), c, r, angle)
		canvas.draw_circle(gem_c, maxf(2.2, r * 0.08), Color(1.0, 0.95, 1.0, col_edge.a))


static func _draw_axe(
	canvas: CanvasItem,
	c: Vector2,
	r: float,
	angle: float,
	col_main: Color,
	col_light: Color,
	col_steel: Color,
	col_shaft: Color
) -> void:
	var shaft: PackedVector2Array = _xform([
		Vector2(-0.06, -0.82), Vector2(0.06, -0.82), Vector2(0.07, 0.95), Vector2(-0.07, 0.95)
	], c, r, angle)
	canvas.draw_colored_polygon(shaft, col_shaft)

	var left_wing: PackedVector2Array = _xform([
		Vector2(-0.06, -0.56), Vector2(-0.66, -0.78), Vector2(-0.78, -0.32),
		Vector2(-0.62, 0.12), Vector2(-0.06, -0.10)
	], c, r, angle)
	var right_wing: PackedVector2Array = _xform([
		Vector2(0.06, -0.56), Vector2(0.66, -0.78), Vector2(0.78, -0.32),
		Vector2(0.62, 0.12), Vector2(0.06, -0.10)
	], c, r, angle)
	canvas.draw_colored_polygon(left_wing, col_main)
	canvas.draw_colored_polygon(right_wing, col_steel)

	var left_bevel: PackedVector2Array = _xform([
		Vector2(-0.56, -0.74), Vector2(-0.78, -0.32), Vector2(-0.56, 0.08)
	], c, r, angle)
	var right_bevel: PackedVector2Array = _xform([
		Vector2(0.56, -0.74), Vector2(0.78, -0.32), Vector2(0.56, 0.08)
	], c, r, angle)
	canvas.draw_polyline(left_bevel, col_light, 2.0, true)
	canvas.draw_polyline(right_bevel, col_light, 2.0, true)

	var spike: PackedVector2Array = _xform([
		Vector2(0.0, -1.0), Vector2(0.11, -0.70), Vector2(-0.11, -0.70)
	], c, r, angle)
	canvas.draw_colored_polygon(spike, col_light)


static func _draw_shield(
	canvas: CanvasItem,
	c: Vector2,
	r: float,
	angle: float,
	col_main: Color,
	col_light: Color,
	col_dark: Color
) -> void:
	var rim: PackedVector2Array = _xform([
		Vector2(0.0, -0.88), Vector2(0.74, -0.64), Vector2(0.66, 0.14),
		Vector2(0.0, 0.92), Vector2(-0.66, 0.14), Vector2(-0.74, -0.64)
	], c, r, angle)
	canvas.draw_colored_polygon(rim, col_light)

	var plate_l: PackedVector2Array = _xform([
		Vector2(0.0, -0.74), Vector2(0.0, 0.76), Vector2(-0.54, 0.10), Vector2(-0.60, -0.54)
	], c, r, angle)
	var plate_r: PackedVector2Array = _xform([
		Vector2(0.0, -0.74), Vector2(0.60, -0.54), Vector2(0.54, 0.10), Vector2(0.0, 0.76)
	], c, r, angle)
	canvas.draw_colored_polygon(plate_l, col_main)
	canvas.draw_colored_polygon(plate_r, col_dark)

	var boss: PackedVector2Array = _xform([
		Vector2(0.0, -0.30), Vector2(0.24, -0.04), Vector2(0.0, 0.24), Vector2(-0.24, -0.04)
	], c, r, angle)
	canvas.draw_colored_polygon(boss, col_light)


static func _draw_ring(
	canvas: CanvasItem,
	c: Vector2,
	r: float,
	col_main: Color,
	col_light: Color
) -> void:
	var band_center := Vector2(c.x, c.y + r * 0.14)
	var band_col := Color(0.93, 0.76, 0.34, col_main.a)
	canvas.draw_arc(band_center, r * 0.60, 0.0, TAU, 28, band_col, maxf(3.2, r * 0.20), true)
	canvas.draw_arc(band_center, r * 0.66, -PI * 0.8, -PI * 0.2, 16, col_light, 1.5, true)

	var ruby_center := Vector2(c.x, c.y - r * 0.48)
	var gem_poly: PackedVector2Array = _xform([
		Vector2(0.0, -0.34), Vector2(0.30, 0.0), Vector2(0.0, 0.30), Vector2(-0.30, 0.0)
	], ruby_center, r, 0.0)
	var ruby_col := Color(0.96, 0.26, 0.42, col_main.a)
	canvas.draw_colored_polygon(gem_poly, ruby_col)
	canvas.draw_circle(ruby_center + Vector2(-r * 0.07, -r * 0.08), maxf(1.6, r * 0.08), col_light)


static func _draw_totem(
	canvas: CanvasItem,
	c: Vector2,
	r: float,
	col_main: Color,
	col_light: Color,
	col_dark: Color
) -> void:
	var slab: PackedVector2Array = _xform([
		Vector2(-0.36, -0.86), Vector2(0.0, -1.02), Vector2(0.36, -0.86),
		Vector2(0.44, 0.92), Vector2(-0.44, 0.92)
	], c, r, 0.0)
	canvas.draw_colored_polygon(slab, col_dark)

	var inner: PackedVector2Array = _xform([
		Vector2(-0.28, -0.76), Vector2(0.0, -0.90), Vector2(0.28, -0.76),
		Vector2(0.34, 0.82), Vector2(-0.34, 0.82)
	], c, r, 0.0)
	canvas.draw_colored_polygon(inner, col_main)

	canvas.draw_circle(c + Vector2(0.0, -r * 0.24), maxf(2.6, r * 0.16), col_light)
	canvas.draw_line(
		c + Vector2(0.0, -r * 0.04),
		c + Vector2(0.0, r * 0.56),
		col_light,
		2.2,
		true
	)
	canvas.draw_line(
		c + Vector2(-r * 0.18, r * 0.26),
		c + Vector2(r * 0.18, r * 0.26),
		col_light,
		2.0,
		true
	)


static func _draw_potion(
	canvas: CanvasItem,
	c: Vector2,
	r: float,
	col_main: Color,
	col_light: Color,
	col_glass: Color
) -> void:
	var neck: PackedVector2Array = _xform([
		Vector2(-0.18, -0.78), Vector2(0.18, -0.78), Vector2(0.22, -0.34), Vector2(-0.22, -0.34)
	], c, r, 0.0)
	canvas.draw_colored_polygon(neck, Color(col_glass.r, col_glass.g, col_glass.b, col_main.a * 0.55))

	var cork: PackedVector2Array = _xform([
		Vector2(-0.15, -0.94), Vector2(0.15, -0.94), Vector2(0.13, -0.76), Vector2(-0.13, -0.76)
	], c, r, 0.0)
	canvas.draw_colored_polygon(cork, Color(0.76, 0.56, 0.34, col_main.a))

	var bulb_c := Vector2(c.x, c.y + r * 0.22)
	var bulb_r: float = r * 0.66
	canvas.draw_circle(bulb_c, bulb_r, Color(col_glass.r, col_glass.g, col_glass.b, col_main.a * 0.28))
	var liquid_col := Color(0.94, 0.29, 0.42, col_main.a * 0.92)
	canvas.draw_circle(bulb_c + Vector2(0.0, bulb_r * 0.08), bulb_r * 0.82, liquid_col)
	canvas.draw_arc(bulb_c, bulb_r, -PI * 0.85, PI * 0.85, 24, Color(col_glass.r, col_glass.g, col_glass.b, col_main.a * 0.65), 1.6, true)
	canvas.draw_circle(bulb_c + Vector2(-bulb_r * 0.32, -bulb_r * 0.24), maxf(2.0, r * 0.11), col_light)


static func _draw_ore(
	canvas: CanvasItem,
	c: Vector2,
	r: float,
	col_main: Color,
	col_light: Color,
	col_dark: Color
) -> void:
	var back_shard: PackedVector2Array = _xform([
		Vector2(-0.48, -0.58), Vector2(-0.08, -0.88), Vector2(0.24, 0.56), Vector2(-0.72, 0.62)
	], c, r, 0.0)
	var right_shard: PackedVector2Array = _xform([
		Vector2(0.32, -0.68), Vector2(0.74, -0.18), Vector2(0.58, 0.72), Vector2(-0.04, 0.64)
	], c, r, 0.0)
	var front_shard: PackedVector2Array = _xform([
		Vector2(-0.06, -0.44), Vector2(0.34, 0.08), Vector2(0.18, 0.80),
		Vector2(-0.44, 0.76), Vector2(-0.46, 0.12)
	], c, r, 0.0)
	canvas.draw_colored_polygon(back_shard, col_dark)
	canvas.draw_colored_polygon(right_shard, col_main)
	canvas.draw_colored_polygon(front_shard, col_light)

#endregion


#region Transform Math

static func _xform(
	norm_pts: Array,
	center: Vector2,
	radius: float,
	angle: float
) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(norm_pts.size())
	var cos_a: float = cos(angle)
	var sin_a: float = sin(angle)
	for i: int in norm_pts.size():
		var p: Vector2 = norm_pts[i] as Vector2
		var rx: float = (p.x * cos_a - p.y * sin_a) * radius
		var ry: float = (p.x * sin_a + p.y * cos_a) * radius
		out[i] = Vector2(center.x + rx, center.y + ry)
	return out


static func _pt(norm_pt: Vector2, center: Vector2, radius: float, angle: float) -> Vector2:
	var cos_a: float = cos(angle)
	var sin_a: float = sin(angle)
	return Vector2(
		center.x + (norm_pt.x * cos_a - norm_pt.y * sin_a) * radius,
		center.y + (norm_pt.x * sin_a + norm_pt.y * cos_a) * radius
	)

#endregion
