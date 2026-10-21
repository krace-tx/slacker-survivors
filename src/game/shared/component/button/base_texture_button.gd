class_name BaseTextureButton
extends TextureButton

## 通用贴图按钮基类（位于 src/game/shared/component/button/）。[br]
## 封装通用按压缩放补间、点击音效与设备振动反馈；[br]
## 内置【手势消抖与滚动协同中继（Scroll Forwarding）】机制：[br]
## 1. 自动感知祖先 [ScrollContainer]，当手指在按钮区域滑动距离超出阈值时，自动驱动列表平滑滚动；[br]
## 2. 滑动确认后立刻复原按钮缩放态，并在手指抬起时拦截释放事件，杜绝误触 [signal pressed]；[br]
## 3. 普通点击（位移未超标）正常触发业务响应与交互动效。[br]
## 做：按下/抬起/滑出时的缩放、音效与振动、滚动事件中继。[br]
## 不做：换场、广告、业务回调；那些由上层业务场景连接 [signal pressed]。

#region Exports
@export_group("Scale")
## 按下时的缩放。大于 1 外扩，小于 1 内缩。
@export var press_scale: float = 1.05
## 抬起 / 滑出后回到的缩放。
@export var idle_scale: float = 1.0
## 缩放补间时长（秒）。
@export var scale_duration: float = 0.1

@export_group("Feedback")
## 点击时是否播音效。
@export var play_sfx: bool = true
## 点击音效路径。空则使用 App.audio.default_button_sfx（若配置）。
@export_file("*.wav", "*.mp3", "*.ogg") var sfx_path: String = ""
## 点击音效音量（分贝）。[method BaseAudioSystem.play_sfx] 的 volume。
@export var sfx_volume_db: int = 0
## 点击时是否振动。
@export var play_vibrate: bool = true

@export_group("Scroll Forwarding")
## 是否开启手势消抖与滚动中继（置于 ScrollContainer 内时拖拽卡片直接驱动列表滚动）。
@export var enable_scroll_forwarding: bool = true
## 判定为滚动的像素位移阈值（单位：像素），小于此值判定为点击，超出则转为滚动。
@export var drag_threshold: float = 12.0
## 滚动灵敏度系数（1.0 为 1:1 跟手移动）。
@export var scroll_speed_factor: float = 1.0
#endregion

#region State
var _tween: Tween = null								## 缩放补间动画实例
var _press_pos: Vector2 = Vector2.ZERO					## 触摸/鼠标按下时的屏幕绝对坐标
var _is_scrolling: bool = false							## 当前触摸会话是否已被确认为滚动行为
var _is_pointer_down: bool = false						## 当前指针（手指/鼠标左键）是否正按在按钮上
var _original_button_mask: int = MOUSE_BUTTON_MASK_LEFT	## 初始设定的响应掩码（用于滑动时临时置空防误触）
var _parent_scroll: ScrollContainer = null				## 祖先节点链条上最近的 ScrollContainer 缓存
#endregion


#region Lifecycle
func _ready() -> void:
	# 缓存初始掩码与中心锚点
	_original_button_mask = button_mask
	pivot_offset = size * 0.5
	resized.connect(func(): pivot_offset = size * 0.5)

	# 基础交互信号连接
	button_down.connect(_on_base_button_down)
	button_up.connect(_on_base_button_up)
	mouse_exited.connect(_on_base_mouse_exited)
	pressed.connect(_on_base_pressed)

	# 预先寻址最近的滚动容器（若此时尚未进入完整父树，后续按下时还会惰性查找一次）
	if enable_scroll_forwarding:
		_parent_scroll = _find_scroll_container()


## 拦截 GUI 输入事件，实现手势消抖判定与滚动位移中继转发
func _gui_input(event: InputEvent) -> void:
	if not enable_scroll_forwarding:
		return

	# 1. 桌面端 / 鼠标事件处理
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_handle_pointer_down(mb.global_position)
			else:
				var was_scrolling := _is_scrolling
				_handle_pointer_up()
				if was_scrolling:
					# 若抬起前处于滑动状态，立即消费此事件，阻止底层 BaseButton 发射 pressed 信号
					accept_event()
					return

	# 2. 移动端真机 / 模拟触摸事件处理
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_handle_pointer_down(st.position)
		else:
			var was_scrolling := _is_scrolling
			_handle_pointer_up()
			if was_scrolling:
				accept_event()
				return

	# 3. 鼠标位移拖动
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_handle_pointer_motion(mm.global_position, mm.relative)

	# 4. 触屏拖拽滑动
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_handle_pointer_motion(sd.position, sd.relative)
#endregion


#region Internal - Tween & Audio
## 执行缩放动画补间
func _scale_to(to_scale: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2(to_scale, to_scale), scale_duration) \
		.set_trans(Tween.TRANS_QUAD) \
		.set_ease(Tween.EASE_OUT)


## 按钮原生按下回调：仅在非滚动态时呈现按压缩放
func _on_base_button_down() -> void:
	if not _is_scrolling:
		_scale_to(press_scale)


## 按钮原生抬起回调：恢复原始缩放
func _on_base_button_up() -> void:
	_scale_to(idle_scale)


## 指针滑出按钮范围回调：恢复原始缩放
func _on_base_mouse_exited() -> void:
	_scale_to(idle_scale)


## 静态反馈提供者代理（可在启动期配置，方便无 Autoload 环境单元测试）
static var sfx_handler: Callable
static var haptic_handler: Callable


## 按钮原生触发点击回调：播放音效与设备振动（附加滚动安全防护门禁）
func _on_base_pressed() -> void:
	if _is_scrolling:
		return

	if play_sfx:
		if sfx_handler.is_valid():
			sfx_handler.call(sfx_path, sfx_volume_db)
		else:
			_fallback_play_sfx()

	if play_vibrate:
		if haptic_handler.is_valid():
			haptic_handler.call()
		else:
			_fallback_play_vibrate()


func _fallback_play_sfx() -> void:
	if App == null or App.audio == null:
		return
	var target_sfx := sfx_path if not sfx_path.is_empty() else App.audio.default_button_sfx
	if not target_sfx.is_empty():
		App.audio.play_sfx(target_sfx, sfx_volume_db)


func _fallback_play_vibrate() -> void:
	if App != null and App.haptic != null:
		App.haptic.light()
#endregion


#region Internal - Scroll Forwarding
## 向上遍历场景树，寻找最近的祖先 ScrollContainer
func _find_scroll_container() -> ScrollContainer:
	var curr: Node = get_parent()
	while curr != null:
		if curr is ScrollContainer:
			return curr as ScrollContainer
		curr = curr.get_parent()
	return null


## 记录指针按下初始状态与坐标
func _handle_pointer_down(pos: Vector2) -> void:
	_is_pointer_down = true
	_is_scrolling = false
	_press_pos = pos
	button_mask = _original_button_mask

	if _parent_scroll == null:
		_parent_scroll = _find_scroll_container()


## 处理指针滑动移动：判定拖拽阈值并中继滚动
func _handle_pointer_motion(pos: Vector2, relative: Vector2) -> void:
	if not _is_pointer_down:
		return

	# 1. 阈值判断：首次滑动超过 drag_threshold 时正式转入滚动模式
	if not _is_scrolling:
		if pos.distance_to(_press_pos) > drag_threshold:
			_is_scrolling = true
			# 核心防误触技巧：临时清空 button_mask 使 C++ 底层 BaseButton 立即解除按压捕获
			button_mask = 0
			_scale_to(idle_scale)

	# 2. 处于滚动中时，将相对位移注入父级 ScrollContainer 并消费事件
	if _is_scrolling:
		if _parent_scroll != null and is_instance_valid(_parent_scroll):
			_forward_scroll(relative)
		accept_event()


## 指针抬起：恢复按钮状态并安全重置滚动标记
func _handle_pointer_up() -> void:
	_is_pointer_down = false
	_scale_to(idle_scale)
	button_mask = _original_button_mask
	# 延迟至帧末重置 _is_scrolling，确保本轮后续释放分发完全消化后再放开点击门禁
	call_deferred("_reset_scrolling_flag")


## 惰性重置滚动标志
func _reset_scrolling_flag() -> void:
	_is_scrolling = false


## 将触摸滑动相对位移量同步更新到祖先 ScrollContainer
func _forward_scroll(relative: Vector2) -> void:
	if _parent_scroll == null or not is_instance_valid(_parent_scroll):
		return

	# 垂直滚动：手指向上移动（relative.y < 0）时，列表内容下滚，scroll_vertical 数值需递增
	if _parent_scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and absf(relative.y) > 0.001:
		_parent_scroll.scroll_vertical -= int(round(relative.y * scroll_speed_factor))

	# 水平滚动：手指向左移动（relative.x < 0）时，列表内容右滚，scroll_horizontal 数值需递增
	if _parent_scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and absf(relative.x) > 0.001:
		_parent_scroll.scroll_horizontal -= int(round(relative.x * scroll_speed_factor))
#endregion
