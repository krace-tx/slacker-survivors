class_name VideoCutsceneOverlay
extends CanvasLayer

## 全屏剧情/过场视频专用渲染遮罩层（Video Cutscene UI Overlay Component）。[br]
##
## 本组件负责桌面端与引擎软解模式下的全屏过场视觉编排与跳过交互：[br]
## - 画面层级置顶：默认挂载于 [code]layer = 95[/code]，覆盖游戏常规场景；[br]
## - 纯黑防穿透底衬：全屏 [ColorRect] 阻断下层视口交互与背景噪点；[br]
## - 等比居中画幅：[TextureRect] 自适应视口尺寸与长宽比；[br]
## - 优雅跳过交互：基于 [member VideoPlayOptions.min_watch_seconds] 控制跳过按钮淡入时机。

## 当玩家触发跳过交互（点击跳过按钮或触发跳过热键）时触发
signal skip_requested()

var _background: ColorRect
var _texture_rect: TextureRect
var _skip_button: Button

var _allow_skip: bool = true
var _min_watch_seconds: float = 0.0
var _is_skip_revealed: bool = false
var _fade_tween: Tween = null


func _init() -> void:
	layer = 95
	_build_ui()


func _exit_tree() -> void:
	_kill_fade_tween()


## 配置并初始化遮罩层表现行为
func setup(options: VideoPlayOptions) -> void:
	if options == null:
		return
	_allow_skip = options.allow_skip
	_min_watch_seconds = maxf(0.0, options.min_watch_seconds)
	
	if not _allow_skip:
		_skip_button.visible = false
	elif _min_watch_seconds > 0.0:
		_skip_button.visible = false
		_skip_button.modulate.a = 0.0
		_is_skip_revealed = false
	else:
		_skip_button.visible = true
		_skip_button.modulate.a = 1.0
		_is_skip_revealed = true


## 动态刷新当前帧视频纹理输出
func update_texture(texture: Texture2D) -> void:
	if _texture_rect != null and texture != null:
		if _texture_rect.texture != texture:
			_texture_rect.texture = texture


## 检查并更新当前视频播放流逝进度（用于触发强制观看倒计时完成后的跳过按钮淡入）
func update_progress(current_seconds: float) -> void:
	if not _allow_skip or _is_skip_revealed:
		return
	
	if current_seconds >= _min_watch_seconds:
		_is_skip_revealed = true
		_skip_button.visible = true
		_kill_fade_tween()
		_fade_tween = create_tween()
		_fade_tween.tween_property(_skip_button, "modulate:a", 1.0, 0.4)


## 优雅关闭并释放遮罩层
func close() -> void:
	_kill_fade_tween()
	queue_free()


#region Internal UI Construction
func _build_ui() -> void:
	# 1. 纯黑背景遮罩
	_background = ColorRect.new()
	_background.name = "Background"
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.color = Color.BLACK
	_background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_background)
	
	# 2. 视频画幅纹理显示
	_texture_rect = TextureRect.new()
	_texture_rect.name = "VideoTextureView"
	_texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_texture_rect)
	
	# 3. 现代悬浮跳过按钮
	_skip_button = Button.new()
	_skip_button.name = "SkipButton"
	_skip_button.text = "跳过 >>"
	_skip_button.anchor_left = 1.0
	_skip_button.anchor_top = 0.0
	_skip_button.anchor_right = 1.0
	_skip_button.anchor_bottom = 0.0
	_skip_button.offset_left = -130
	_skip_button.offset_top = 32
	_skip_button.offset_right = -32
	_skip_button.offset_bottom = 74
	_skip_button.focus_mode = Control.FOCUS_NONE
	_skip_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
	# 轻量内联圆角样式
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.14, 0.75)
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_left = 18
	style.corner_radius_bottom_right = 18
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(1.0, 1.0, 1.0, 0.25)
	_skip_button.add_theme_stylebox_override("normal", style)
	
	var hover_style := style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color(0.2, 0.2, 0.24, 0.9)
	hover_style.border_color = Color(1.0, 1.0, 1.0, 0.5)
	_skip_button.add_theme_stylebox_override("hover", hover_style)
	
	_skip_button.pressed.connect(_on_skip_pressed)
	add_child(_skip_button)


func _on_skip_pressed() -> void:
	skip_requested.emit()


func _kill_fade_tween() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
#endregion
