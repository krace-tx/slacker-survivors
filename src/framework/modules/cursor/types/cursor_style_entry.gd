class_name CursorStyleEntry
extends Resource

## 单一光标形状的视觉样式配置资源（Single Cursor Shape Style Entry）。[br]
##
## [b]核心特性：[/b][br]
## 1. 支持配置常态贴图（[member normal_texture]）与左键按下态贴图（[member pressed_texture]）；[br]
## 2. 支持配置像素级点击热点偏移（[member hotspot]），如箭头尖端 `(2, 2)` 或准星中心 `(16, 16)`；[br]
## 3. 支持可选挂载动态画布光标预制体（[member custom_node_scene]），用于需要旋转环、Shader 或骨骼动画的高级指针。

#region Exports
## 该样式条目对应的语义光标形状（见 [enum CursorShapeType.Shape]）。
@export var shape: CursorShapeType.Shape = CursorShapeType.Shape.DEFAULT

## 常态下显示的鼠标光标贴图。
@export var normal_texture: Texture2D = null

## 鼠标左键按住时显示的按压态贴图（为空时自动复用 [member normal_texture] 并执行微缩反馈）。
@export var pressed_texture: Texture2D = null

## 光标点击热点相对贴图左上角的像素坐标（如箭头尖端为 `(2, 2)`，32x32 准星中心为 `(16, 16)`）。
@export var hotspot: Vector2 = Vector2(2.0, 2.0)

## 可选：自定义软件动态光标节点预制体（`.tscn`，根节点建议继承 [Node2D]）。[br]
## 若配置了此预制体或开启 [member force_software_mode]，切入该形状时将自动隐藏系统硬件鼠标并渲染画布动态节点。
@export var custom_node_scene: PackedScene = null

## 是否强制走顶层画布软件渲染模式（开启后支持平滑缩放/旋转补间与射击扩散脉冲）。
@export var force_software_mode: bool = false

## 软件渲染或左键按下时的缩放系数（默认按下时微缩至 `0.88` 提供清脆按压感）。
@export_range(0.5, 1.5, 0.01) var pressed_scale: float = 0.88
#endregion


#region Helpers
## 快速构造一条样式配置。
static func create(
	p_shape: CursorShapeType.Shape,
	p_normal_tex: Texture2D,
	p_pressed_tex: Texture2D = null,
	p_hotspot: Vector2 = Vector2(2.0, 2.0),
	p_force_software: bool = false
) -> CursorStyleEntry:
	var entry := CursorStyleEntry.new()
	entry.shape = p_shape
	entry.normal_texture = p_normal_tex
	entry.pressed_texture = p_pressed_tex if p_pressed_tex != null else p_normal_tex
	entry.hotspot = p_hotspot
	entry.force_software_mode = p_force_software
	return entry


## 获取指定按压态下应生效的贴图。
func get_texture(is_pressed: bool) -> Texture2D:
	if is_pressed and pressed_texture != null:
		return pressed_texture
	return normal_texture


## 判断该样式是否应当使用顶层画布软件光标驱动。
func uses_software_cursor() -> bool:
	return force_software_mode or custom_node_scene != null
#endregion
