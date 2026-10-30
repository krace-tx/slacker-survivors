@tool
class_name OtomeBustOverlay
extends Control

## 乙女向男主「陆星野」心动近景动态半身立绘组件（`rev2d avatar -> Spine 4.2` 双轨制特写轨道）。[br]
##
## [b]核心特性：[/b][br]
## 1. 承载高精正立面商业乙女插画经 `rev2d avatar` 自动分层绑定的 2.5D 半身动态立绘（转头微倾、眨眼、视线、呼吸、说话口型与 10 束银发物理摆动）；[br]
## 2. 进入热点互动或切换 `[C]` 半身特写镜头时从右侧柔光滑入，漫游全景时自动休眠内部 [SubViewport] 零开销；[br]
## 3. 联动神态切换（`gentle_idle` / `happy_talk` / `shy_blush`）与户外天光色温（春昼通透原色 ⇄ 落日星灯暖金微染）。

#region Exports
@export var bust_skeleton_data: Resource = null:
	set(value):
		bust_skeleton_data = value
		_notify_editor_preview_dirty()

@export var bust_viewport_size: Vector2i = Vector2i(896, 1200):
	set(value):
		bust_viewport_size = value
		_notify_editor_preview_dirty()

@export var show_in_editor_preview: bool = true:
	set(value):
		show_in_editor_preview = value
		_notify_editor_preview_dirty()

@export_enum("gentle_idle", "happy_talk", "shy_blush") var editor_preview_anim: String = "gentle_idle":
	set(value):
		editor_preview_anim = value
		_notify_editor_preview_dirty()
#endregion

#region Node Refs & Private State
@onready var _bust_viewport: SubViewport = %BustViewport as SubViewport
@onready var _bust_spine_root: Node2D = %BustSpineRoot as Node2D
@onready var _bust_glow_backdrop: TextureRect = %BustGlowBackdrop as TextureRect
@onready var _bust_texture_rect: TextureRect = %BustTextureRect as TextureRect

var _spine_ctrl: SpineController = null
var _active_anim: String = ""
var _shown_state: bool = false
var _slide_tween: Tween = null
var _weather_tint: Color = Color.WHITE
#endregion


#region Lifecycle
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_setup_glow_backdrop_texture()
	_configure_viewport_and_rect()

	if Engine.is_editor_hint():
		_refresh_editor_preview()
		return

	_dispose_editor_preview_node()
	visible = false
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	if _bust_viewport != null:
		_bust_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_ensure_runtime_mounted_fallback.call_deferred()


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		release_spine()
#endregion


#region Public Mount & Render API
## 从场景级 [SpinePool] 借出 [SpineController] 挂载高精度动态半身像。
func mount_from_pool(pool: SpinePool, skel_res: Resource) -> void:
	_dispose_editor_preview_node()
	release_spine()
	if pool == null or skel_res == null or _bust_spine_root == null:
		return
	var acq_res: Result = pool.acquire(skel_res, _bust_spine_root, Vector2.ZERO)
	if acq_res.is_err():
		mount_standalone(skel_res)
		return
	_spine_ctrl = acq_res.value as SpineController
	_post_mount_init()


## 独立创建并挂载半身像 [SpineController]（单场景运行兜底）。
func mount_standalone(skel_res: Resource) -> void:
	_dispose_editor_preview_node()
	release_spine()
	if skel_res == null or _bust_spine_root == null:
		return
	var create_res: Result = SpineController.create(skel_res)
	if create_res.is_err():
		return
	_spine_ctrl = create_res.value as SpineController
	if _spine_ctrl != null and _spine_ctrl.is_valid():
		_bust_spine_root.add_child(_spine_ctrl.node)
		_spine_ctrl.set_transform_2d(Vector2.ZERO)
	_post_mount_init()


## 归还或释放内部持有的 [SpineController]。
func release_spine() -> void:
	if _spine_ctrl != null:
		_spine_ctrl.release()
		_spine_ctrl = null
	_active_anim = ""


## 根据 [OtomeTerraceState] 同步近景半身立绘显隐、神态动画与天光微染。
func render_bust_state(
	show_closeup: bool,
	expr_index: int,
	weather_mode: int
) -> void:
	_weather_tint = (
		Color(1.0, 0.94, 0.90, 1.0)
		if weather_mode == OtomeTerraceConfig.WeatherMode.SUNSET_LIGHTS
		else Color(1.0, 1.0, 1.0, 1.0)
	)
	if _bust_texture_rect != null:
		_bust_texture_rect.self_modulate = _weather_tint

	var anim_idx: int = clampi(expr_index, 0, OtomeTerraceConfig.BUST_EXPR_ANIMS.size() - 1)
	var target_anim: String = OtomeTerraceConfig.BUST_EXPR_ANIMS[anim_idx]

	if Engine.is_editor_hint():
		editor_preview_anim = target_anim
		_refresh_editor_preview()
		return

	if show_closeup:
		if _bust_viewport != null:
			_bust_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_play_bust_anim_if_needed(target_anim)

	if _shown_state == show_closeup:
		return
	_shown_state = show_closeup

	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()

	if show_closeup:
		visible = true
		if _bust_texture_rect != null:
			_bust_texture_rect.offset_left = 36.0
			_bust_texture_rect.offset_right = 36.0
		_slide_tween = create_tween().set_parallel(true)
		_slide_tween.tween_property(self, "modulate:a", 1.0, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if _bust_texture_rect != null:
			_slide_tween.tween_property(_bust_texture_rect, "offset_left", 0.0, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_slide_tween.tween_property(_bust_texture_rect, "offset_right", 0.0, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_slide_tween = create_tween()
		_slide_tween.tween_property(self, "modulate:a", 0.0, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_slide_tween.tween_callback(_on_hide_tween_finished)
#endregion


#region Internal Helpers & Editor Preview
func _on_hide_tween_finished() -> void:
	if _shown_state:
		return
	visible = false
	if _bust_viewport != null:
		_bust_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _post_mount_init() -> void:
	if _spine_ctrl == null or not _spine_ctrl.is_valid():
		return
	_play_bust_anim_if_needed("gentle_idle")
	_spine_ctrl.step(0.016)


func _play_bust_anim_if_needed(anim_name: String) -> void:
	if _spine_ctrl == null or not _spine_ctrl.is_valid():
		return
	if _active_anim == anim_name:
		return
	_active_anim = anim_name
	_spine_ctrl.play(anim_name, true, 0, 1.0, 0.22)


func _ensure_runtime_mounted_fallback() -> void:
	if Engine.is_editor_hint() or _spine_ctrl != null:
		return
	var skel_res: Resource = (
		bust_skeleton_data
		if bust_skeleton_data != null
		else (load(OtomeTerraceConfig.BUST_SPINE_DATA_PATH) as Resource)
	)
	if skel_res != null:
		mount_standalone(skel_res)


func _configure_viewport_and_rect() -> void:
	if _bust_viewport != null:
		_bust_viewport.size = bust_viewport_size
		_bust_viewport.transparent_bg = true
		_bust_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	if _bust_glow_backdrop != null:
		_bust_glow_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _bust_texture_rect != null:
		_bust_texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_bust_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bust_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_bust_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if _bust_viewport != null:
			_bust_texture_rect.texture = _bust_viewport.get_texture()


func _setup_glow_backdrop_texture() -> void:
	if _bust_glow_backdrop == null:
		return
	_bust_glow_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bust_glow_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bust_glow_backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y: int in range(64):
		var ny: float = (float(y) - 26.0) / 34.0
		for x: int in range(64):
			var nx: float = (float(x) - 32.0) / 30.0
			var dist: float = sqrt(nx * nx + ny * ny)
			var a: float = pow(clampf(1.0 - dist, 0.0, 1.0), 2.1) * 0.24
			img.set_pixel(x, y, Color(1.0, 0.93, 0.90, a))
	_bust_glow_backdrop.texture = ImageTexture.create_from_image(img)


func _notify_editor_preview_dirty() -> void:
	if not Engine.is_editor_hint() or not is_node_ready():
		return
	_configure_viewport_and_rect()
	_refresh_editor_preview()


func _refresh_editor_preview() -> void:
	visible = show_in_editor_preview
	modulate = Color.WHITE
	if _bust_viewport != null:
		_bust_viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if show_in_editor_preview else SubViewport.UPDATE_DISABLED
		)
	if not show_in_editor_preview or _bust_spine_root == null:
		return

	var preview_node: Node2D = _bust_spine_root.get_node_or_null("EditorPreviewBustSpine") as Node2D
	if preview_node == null and ClassDB.can_instantiate(&"SpineSprite"):
		preview_node = ClassDB.instantiate(&"SpineSprite") as Node2D
		if preview_node != null:
			preview_node.name = "EditorPreviewBustSpine"
			_bust_spine_root.add_child(preview_node)
	if preview_node == null:
		return

	preview_node.position = Vector2.ZERO
	preview_node.scale = Vector2.ONE
	var skel_res: Resource = (
		bust_skeleton_data
		if bust_skeleton_data != null
		else (load(OtomeTerraceConfig.BUST_SPINE_DATA_PATH) as Resource)
	)
	if skel_res == null:
		return
	if preview_node.get("skeleton_data_res") != skel_res:
		preview_node.set("skeleton_data_res", skel_res)
	preview_node.set("preview_skin", "default")
	preview_node.set("preview_animation", editor_preview_anim if not editor_preview_anim.is_empty() else "gentle_idle")
	preview_node.set("preview_frame", false)


func _dispose_editor_preview_node() -> void:
	if _bust_spine_root == null:
		return
	var preview_node: Node = _bust_spine_root.get_node_or_null("EditorPreviewBustSpine")
	if preview_node != null:
		_bust_spine_root.remove_child(preview_node)
		preview_node.free()
#endregion
