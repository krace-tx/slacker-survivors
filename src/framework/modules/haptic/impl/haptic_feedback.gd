class_name HapticFeedback
extends BaseHapticFeedback

## 跨平台触觉反馈调度器实现。
##
## 核心设计（第一性原理）：
## 1. 统一语义输入，三端硬件差异化翻译（Mobile 短促线性脉冲 / Gamepad 双马达独立配比与起振惯性补偿 / PC 键鼠防空震隔离与视觉脉冲信号）；
## 2. 优先级防打断（Priority Preemption）：高优序列（如 HEAVY）未播完前，低优请求（如 LIGHT）自动让路；
## 3. 高频节流窗（Throttle Guard）：同优先级请求在最小冷却窗（25ms）内自动合并防抖，抵御幸存者怪潮期同帧高频调用风暴；
## 4. 后台生命周期守卫：关联 [signal EventBus.app_paused] 与 [method stop]，切后台或关闭开关时立即递增令牌并急停马达。

#region Module Dependency Manifest
const MODULE_ID: StringName = &"haptic"
const REQUIRED_MODULES: Array[StringName] = []
const OPTIONAL_MODULES: Array[StringName] = [&"input"]
#endregion

#region Hardware Profile Constants
## 同级/低级震动高频节流最小间隔（毫秒），防止同帧拾取数十颗宝石导致马达嗡鸣与 Timer 泛滥
const _MIN_THROTTLE_MS: int = 25
## 手柄转子马达最小物理有效起振时长（毫秒，低于此值转子无法克服惯性）
const _JOY_MIN_SPINUP_MS: int = 35

## 手机端（Mobile）三档预设参数
const _MOBILE_LIGHT_STEPS: Array[int] = [12]
const _MOBILE_LIGHT_AMP: float = 0.35

const _MOBILE_MEDIUM_STEPS: Array[int] = [28]
const _MOBILE_MEDIUM_AMP: float = 0.70

const _MOBILE_HEAVY_STEPS: Array[int] = [40, 35, 60]
const _MOBILE_HEAVY_AMPS: Array[float] = [1.0, 0.85]

## 手柄端（Gamepad）三档预设参数（独立控制 Weak 高频小转子与 Strong 低频大配重）
const _JOY_LIGHT_STEPS: Array[int] = [40]
const _JOY_LIGHT_WEAK: float = 0.35
const _JOY_LIGHT_STRONG: float = 0.0

const _JOY_MEDIUM_STEPS: Array[int] = [75]
const _JOY_MEDIUM_WEAK: float = 0.70
const _JOY_MEDIUM_STRONG: float = 0.45

const _JOY_HEAVY_STEPS: Array[int] = [110, 40, 130]
const _JOY_HEAVY_WEAK_1: float = 0.85
const _JOY_HEAVY_STRONG_1: float = 1.00
const _JOY_HEAVY_WEAK_2: float = 0.50
const _JOY_HEAVY_STRONG_2: float = 0.80
#endregion

#region Dependencies & State
var _input_system: BaseInputSystem = null
## 播放序列令牌：递增即令所有旧的延迟回调在下一拍自动失效
var _token: int = 0
## 当前正在执行的震动序列优先级（取值 [HapticIntensity]）
var _active_priority: int = 0
## 当前正在执行的震动序列预计结束的单调时钟毫秒数（Time.get_ticks_msec）
var _active_end_tick_ms: int = 0
## 上一次成功触发震动的单调时钟毫秒数（用于高频节流防抖）
var _last_trigger_tick_ms: int = -1000
#endregion

#region Lifecycle
func _init(input_system: BaseInputSystem = null) -> void:
	_input_system = input_system


func set_input_system(input_system: BaseInputSystem) -> void:
	_input_system = input_system


func initialize() -> Result:
	if Bus != null and not Bus.app_paused.is_connected(_on_app_paused):
		Bus.app_paused.connect(_on_app_paused)
	return Result.ok()


func dispose() -> void:
	if Bus != null and Bus.app_paused.is_connected(_on_app_paused):
		Bus.app_paused.disconnect(_on_app_paused)
	stop()
	_input_system = null
#endregion

#region 1. Switch & Lifecycle Control
func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		stop()


func stop() -> void:
	_token += 1
	_active_priority = 0
	_active_end_tick_ms = 0
	for joy_id in Input.get_connected_joypads():
		Input.stop_joy_vibration(joy_id)


func _on_app_paused() -> void:
	stop()
#endregion

#region 2. Semantic Tier APIs
func light() -> void:
	if not _try_acquire_slot(HapticIntensity.LIGHT, _estimate_tier_duration(HapticIntensity.LIGHT)):
		return
	if _is_joypad_active():
		_start_sequence(_JOY_LIGHT_STEPS, [_JOY_LIGHT_WEAK], [_JOY_LIGHT_STRONG], HapticIntensity.LIGHT)
	else:
		_start_sequence(_MOBILE_LIGHT_STEPS, [_MOBILE_LIGHT_AMP], [0.0], HapticIntensity.LIGHT)


func medium() -> void:
	if not _try_acquire_slot(HapticIntensity.MEDIUM, _estimate_tier_duration(HapticIntensity.MEDIUM)):
		return
	if _is_joypad_active():
		_start_sequence(_JOY_MEDIUM_STEPS, [_JOY_MEDIUM_WEAK], [_JOY_MEDIUM_STRONG], HapticIntensity.MEDIUM)
	else:
		_start_sequence(_MOBILE_MEDIUM_STEPS, [_MOBILE_MEDIUM_AMP], [0.45], HapticIntensity.MEDIUM)


func heavy() -> void:
	if not _try_acquire_slot(HapticIntensity.HEAVY, _estimate_tier_duration(HapticIntensity.HEAVY)):
		return
	if _is_joypad_active():
		_start_sequence(
			_JOY_HEAVY_STEPS,
			[_JOY_HEAVY_WEAK_1, _JOY_HEAVY_WEAK_2],
			[_JOY_HEAVY_STRONG_1, _JOY_HEAVY_STRONG_2],
			HapticIntensity.HEAVY
		)
	else:
		_start_sequence(
			_MOBILE_HEAVY_STEPS,
			_MOBILE_HEAVY_AMPS,
			[1.0, 0.80],
			HapticIntensity.HEAVY
		)
#endregion

#region 3. Custom Parameterized APIs
func vibrate(
	duration_ms: int = 15,
	amplitude: float = -1.0,
	priority: int = HapticIntensity.LIGHT
) -> void:
	if duration_ms <= 0:
		return
	# 默认无参调用 vibrate() 直接走三端自适应 light() 预设
	if duration_ms == 15 and amplitude < 0.0 and priority == HapticIntensity.LIGHT:
		light()
		return
	pattern([duration_ms], amplitude, priority)


func pattern(
	steps: Array[int],
	amplitude: float = -1.0,
	priority: int = HapticIntensity.MEDIUM
) -> void:
	if steps.is_empty():
		return
	var resolved_priority := priority
	# 兼容业务层传入预设常量数组 BaseHapticFeedback.HEAVY / LIGHT 时自动识别优先级
	if steps == HEAVY and priority == HapticIntensity.MEDIUM:
		resolved_priority = HapticIntensity.HEAVY
	elif steps == LIGHT and priority == HapticIntensity.MEDIUM:
		resolved_priority = HapticIntensity.LIGHT

	var total_ms := _sum_steps_duration(steps)
	if total_ms <= 0 or not _try_acquire_slot(resolved_priority, total_ms):
		return

	var resolved_amp := clampf(amplitude, 0.0, 1.0) if amplitude >= 0.0 else _default_amp_for_priority(resolved_priority)
	var strong_amp := _default_strong_for_priority(resolved_priority, resolved_amp)
	_start_sequence(steps, [resolved_amp], [strong_amp], resolved_priority)


func rumble_joypad(
	weak_magnitude: float,
	strong_magnitude: float,
	duration_ms: int,
	priority: int = HapticIntensity.CUSTOM
) -> void:
	if duration_ms <= 0:
		return
	var effective_ms := maxi(duration_ms, _JOY_MIN_SPINUP_MS) if _is_joypad_active() else duration_ms
	if not _try_acquire_slot(priority, effective_ms):
		return
	var weak := clampf(weak_magnitude, 0.0, 1.0)
	var strong := clampf(strong_magnitude, 0.0, 1.0)
	if weak <= 0.0 and strong <= 0.0:
		return
	_start_sequence([effective_ms], [weak], [strong], priority)
#endregion

#region Internal Arbitration & Execution
## 裁决当前请求是否允许执行（负责总开关短路、高优防打断保护、同级高频节流防抖）。
func _try_acquire_slot(priority: int, duration_ms: int) -> bool:
	if not enabled or duration_ms <= 0:
		return false

	var now_tick := Time.get_ticks_msec()
	var is_busy := now_tick < _active_end_tick_ms

	if is_busy:
		# 1. 低优先级请求绝不打断正在执行的高优先级序列（如拾取经验球不打断 Boss 重击）
		if priority < _active_priority:
			return false
		# 2. 同优先级请求在最小节流窗口（25ms）内自动合并防抖
		if priority == _active_priority and (now_tick - _last_trigger_tick_ms) < _MIN_THROTTLE_MS:
			return false
	else:
		# 即使上一段刚播完，同级高频请求仍受最小节流间隔约束
		if priority <= _active_priority and (now_tick - _last_trigger_tick_ms) < _MIN_THROTTLE_MS:
			return false

	_token += 1
	_active_priority = priority
	_last_trigger_tick_ms = now_tick
	_active_end_tick_ms = now_tick + duration_ms
	return true


func _start_sequence(
	steps: Array[int],
	weak_or_mobile_amps: Array[float],
	strong_amps: Array[float],
	priority: int
) -> void:
	_play_step(steps, weak_or_mobile_amps, strong_amps, 0, priority, _token)


func _play_step(
	steps: Array[int],
	weak_or_mobile_amps: Array[float],
	strong_amps: Array[float],
	index: int,
	priority: int,
	token: int
) -> void:
	if token != _token or not enabled or index >= steps.size():
		return

	var duration_ms: int = steps[index]
	if duration_ms > 0:
		@warning_ignore("integer_division")
		var pulse_idx: int = index / 2
		var weak_amp: float = _pick_amp(weak_or_mobile_amps, pulse_idx, 0.5)
		var strong_amp: float = _pick_amp(strong_amps, pulse_idx, 0.0)
		var combined_amp: float = maxf(weak_amp, strong_amp)

		# 1. 移动端手持物理震动（仅在移动平台执行，传入 Godot 4 原生 amplitude）
		if _is_mobile_runtime():
			Input.vibrate_handheld(duration_ms, combined_amp)

		# 2. 手柄高低频双马达驱动（仅当玩家当前活跃设备为手柄时触发，防止键鼠游玩时桌面手柄空震噪音）
		if _is_joypad_active():
			var joy_id := _input_system.active_joy_id
			var joy_ms := maxi(duration_ms, _JOY_MIN_SPINUP_MS)
			Input.start_joy_vibration(joy_id, weak_amp, strong_amp, float(joy_ms) / 1000.0)

		# 3. 广播跨模态触觉脉冲信号（供 PC 键鼠端或全平台战斗镜头按需桥接微小震屏反馈）
		haptic_pulsed.emit(priority, combined_amp, duration_ms)

	if index + 1 >= steps.size():
		return

	var gap_ms: int = steps[index + 1]
	var wait_ms: int = maxi(0, duration_ms) + maxi(0, gap_ms)
	if wait_ms <= 0:
		_play_step(steps, weak_or_mobile_amps, strong_amps, index + 2, priority, token)
		return

	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	tree.create_timer(float(wait_ms) / 1000.0).timeout.connect(
		_play_step.bind(steps, weak_or_mobile_amps, strong_amps, index + 2, priority, token),
		CONNECT_ONE_SHOT
	)


func _is_joypad_active() -> bool:
	return (
		_input_system != null
		and is_instance_valid(_input_system)
		and _input_system.current_device == InputDeviceType.Type.JOYPAD
	)


static func _is_mobile_runtime() -> bool:
	if OS.has_feature("editor"):
		return false
	var os_name := OS.get_name()
	return os_name == "Android" or os_name == "iOS" or OS.has_feature("mobile")


func _estimate_tier_duration(tier: int) -> int:
	var use_joy := _is_joypad_active()
	match tier:
		HapticIntensity.LIGHT:
			return _sum_steps_duration(_JOY_LIGHT_STEPS if use_joy else _MOBILE_LIGHT_STEPS)
		HapticIntensity.MEDIUM:
			return _sum_steps_duration(_JOY_MEDIUM_STEPS if use_joy else _MOBILE_MEDIUM_STEPS)
		HapticIntensity.HEAVY:
			return _sum_steps_duration(_JOY_HEAVY_STEPS if use_joy else _MOBILE_HEAVY_STEPS)
		_:
			return 30


static func _sum_steps_duration(steps: Array[int]) -> int:
	var total: int = 0
	for s in steps:
		if s > 0:
			total += s
	return total


static func _pick_amp(amps: Array[float], pulse_idx: int, fallback: float) -> float:
	if amps.is_empty():
		return fallback
	var idx := mini(pulse_idx, amps.size() - 1)
	return clampf(amps[idx], 0.0, 1.0)


static func _default_amp_for_priority(priority: int) -> float:
	match priority:
		HapticIntensity.LIGHT:
			return _MOBILE_LIGHT_AMP
		HapticIntensity.HEAVY:
			return 1.0
		_:
			return _MOBILE_MEDIUM_AMP


static func _default_strong_for_priority(priority: int, weak_amp: float) -> float:
	match priority:
		HapticIntensity.LIGHT:
			return 0.0
		HapticIntensity.HEAVY:
			return 1.0
		_:
			return clampf(weak_amp * 0.65, 0.0, 1.0)
#endregion
