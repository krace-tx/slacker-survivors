class_name InputSystem
extends BaseInputSystem

## 输入与键位映射系统核心实现（Input & Keybinding System Implementation）。[br]
##
## 汇聚四大子组件能力：[br]
## 1. [InputDeviceTracker]：硬件输入嗅探、0.5 唤醒阈值防抖切换与手柄型号识别；[br]
## 2. [InputMapAdapter]：出厂基线快照、键鼠/手柄双轨双槽隔离、同域冲突互换与增量序列化；[br]
## 3. [InputRebindCapturer]：二段式免勾选录制状态机（按住修饰等主键、松开修饰算单键）；[br]
## 4. 高阶组合键优先消费管线（Highest-Order Chord Consumption）+ 双帧号（Process/Physics）独立对齐。

#region Module Dependency Manifest
const MODULE_ID: StringName = &"input"
const REQUIRED_MODULES: Array[StringName] = []
const OPTIONAL_MODULES: Array[StringName] = [&"logger"]
#endregion

#region Dependencies & Subcomponents
var _logger: BaseFrameworkLogger
var _tracker: InputDeviceTracker
var _adapter: InputMapAdapter
var _capturer: InputRebindCapturer
#endregion

#region Runtime State
## 输入上下文作用域栈（栈底固定为 GAMEPLAY）
var _context_stack: Array[int] = [InputContextType.Context.GAMEPLAY]

## 每个 Action 的双帧精确状态缓存：
## { StringName: { "pressed": bool, "pressed_proc": bool, "pressed_phys": bool, "strength": float, "jp_proc": int, "jr_proc": int, "jp_phys": int, "jr_phys": int } }
var _action_states: Dictionary = {}

## 防穿透抬起解锁集合：记录从 UI/REBIND 切回 GAMEPLAY 时仍处于按住状态的物理触发键签名
var _wait_release_triggers: Dictionary = {}

## 高阶组合键消费抑制表：记录被组合键消费后尚未松开的物理键签名，防止先松开修饰键时误触单键动作
var _chord_consumed_triggers: Dictionary = {}

## 帧内瞬时按压脉冲锁存表：捕获两次 _process 或 _physics_process 之间极速按下并抬起的按键/触控板轻点
var _pending_press_proc: Dictionary = {}
var _pending_press_phys: Dictionary = {}

## 启动当前按键录制的 UI 按钮引用（用于识别用户点击其它按钮时的无缝切换与取消）
var _rebind_initiator_control: Control = null

## 录制结束后的 1 帧输入屏蔽冷却计数（防止松开录制键或按 ESC 取消时穿透至 UI）
var _rebind_cooldown_frames: int = 0

## 已完成求值的最近渲染帧与物理帧号（确保每帧无论何时调用均精确求值一次）
var _last_eval_process_frame: int = -1
var _last_eval_physics_frame: int = -1
#endregion


#region Lifecycle
func _init(logger: BaseFrameworkLogger = null) -> void:
	_logger = logger
	_tracker = InputDeviceTracker.new()
	_adapter = InputMapAdapter.new()
	_capturer = InputRebindCapturer.new()
	# 强制常驻运行，确保 SceneTree.paused = true（升级弹窗/暂停菜单）期间仍能正常切设备与改键
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000
	process_physics_priority = -1000


func initialize() -> Result:
	_tracker.initialize()
	_adapter.initialize()

	_tracker.device_changed.connect(_on_tracker_device_changed)
	_tracker.joypad_connection_changed.connect(_on_tracker_joypad_connection_changed)
	_capturer.rebind_preview_changed.connect(_on_capturer_preview_changed)

	if Bus != null and not Bus.app_paused.is_connected(flush_all_states):
		Bus.app_paused.connect(flush_all_states)

	current_device = _tracker.current_device
	current_joy_brand = _tracker.current_joy_brand
	active_joy_id = _tracker.active_joy_id

	for act in _adapter.get_managed_actions():
		_ensure_action_state_entry(act)

	_sync_ime_state()

	_log_info("InputSystem initialized (%d managed actions, device=%s)." % [
		_adapter.get_managed_actions().size(),
		InputDeviceType.type_to_string(current_device),
	])
	return Result.ok()


func dispose() -> void:
	if _capturer != null and _capturer.is_capturing():
		_capturer.cancel_capture()
	if _tracker != null:
		_tracker.dispose()
	if Bus != null and Bus.app_paused.is_connected(flush_all_states):
		Bus.app_paused.disconnect(flush_all_states)
	flush_all_states()
	if _adapter != null:
		_adapter.dispose()
	_action_states.clear()
	_wait_release_triggers.clear()
	_chord_consumed_triggers.clear()
	_pending_press_proc.clear()
	_pending_press_phys.clear()
	_rebind_initiator_control = null
	if is_inside_tree():
		queue_free()


func _input(event: InputEvent) -> void:
	if event == null:
		return

	# 1. 若处于交互式按键录制中，优先处理跨按钮切换取消或拦截吞没输入
	if _capturer.is_capturing():
		if event is InputEventMouseButton and event.is_pressed():
			var vp_check := get_viewport()
			var hovered: Control = vp_check.gui_get_hovered_control() if vp_check != null else null
			var target_dev := _capturer.get_target_device()
			# (a) 正在录制手柄槽位时若玩家用鼠标点击界面：立即取消手柄录制；若点在其它按钮上则放行该次点击
			if target_dev == InputDeviceType.Type.JOYPAD:
				var clicked_same_btn := (hovered != null and hovered == _rebind_initiator_control)
				_capturer.cancel_capture()
				if clicked_same_btn and vp_check != null:
					vp_check.set_input_as_handled()
				return
			# (b) 正在录制键鼠槽位时若玩家用左键点击了【另一个】UI 按钮：取消当前录制并让新按钮立即响应点击
			if (
				(event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
				and hovered is BaseButton
				and hovered != _rebind_initiator_control
			):
				_capturer.cancel_capture()
				return

		var consumed := _capturer.handle_input_event(event, current_joy_brand)
		if consumed:
			var vp := get_viewport()
			if vp != null:
				vp.set_input_as_handled()
		return

	if _rebind_cooldown_frames > 0:
		if not (event is InputEventMouseMotion):
			var vp := get_viewport()
			if vp != null:
				vp.set_input_as_handled()
		return

	# 2. 驱动硬件设备嗅探器（键鼠 <-> 手柄热切）
	_tracker.process_input_event(event)

	# 3. 锁存本帧瞬时按压脉冲（确保极速轻敲按键或 macOS 触控板同帧按下抬起时 100% 被 _process 与 _physics_process 捕获）
	_record_pending_press_from_event(event)


func _process(delta: float) -> void:
	if _capturer.is_capturing():
		_capturer.tick(delta)
	elif _rebind_cooldown_frames > 0:
		_rebind_cooldown_frames -= 1
	_evaluate_for_current_frame(false)


func _physics_process(_delta: float) -> void:
	_evaluate_for_current_frame(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		flush_all_states()
#endregion


#region Gameplay & Action Polling APIs
func get_vector(
	negative_x: StringName,
	positive_x: StringName,
	negative_y: StringName,
	positive_y: StringName,
	deadzone: float = -1.0
) -> Vector2:
	_ensure_evaluated()
	if not _is_context_allowed(InputContextType.Context.GAMEPLAY):
		return Vector2.ZERO

	var dz := deadzone if deadzone >= 0.0 else _adapter.get_joy_deadzone()
	var raw_vec := Vector2(
		_compute_axis_action_strength(positive_x, dz) - _compute_axis_action_strength(negative_x, dz),
		_compute_axis_action_strength(positive_y, dz) - _compute_axis_action_strength(negative_y, dz)
	)
	var len := raw_vec.length()
	if len <= 0.001:
		return Vector2.ZERO
	if len > 1.0:
		return raw_vec / len
	return raw_vec


func is_action_pressed(action: StringName) -> bool:
	_ensure_evaluated()
	if not _action_states.has(action):
		return Input.is_action_pressed(action) if gameplay_input_enabled and InputMap.has_action(action) else false
	return bool(_action_states[action]["pressed"])


func is_action_just_pressed(action: StringName) -> bool:
	_ensure_evaluated()
	if not _action_states.has(action):
		return Input.is_action_just_pressed(action) if gameplay_input_enabled and InputMap.has_action(action) else false
	var st: Dictionary = _action_states[action]
	if Engine.is_in_physics_frame():
		return int(st["jp_phys"]) == Engine.get_physics_frames()
	return int(st["jp_proc"]) == Engine.get_process_frames()


func is_action_just_released(action: StringName) -> bool:
	_ensure_evaluated()
	if not _action_states.has(action):
		return Input.is_action_just_released(action) if gameplay_input_enabled and InputMap.has_action(action) else false
	var st: Dictionary = _action_states[action]
	if Engine.is_in_physics_frame():
		return int(st["jr_phys"]) == Engine.get_physics_frames()
	return int(st["jr_proc"]) == Engine.get_process_frames()


func get_action_strength(action: StringName) -> float:
	_ensure_evaluated()
	if not _action_states.has(action):
		return Input.get_action_strength(action) if gameplay_input_enabled and InputMap.has_action(action) else 0.0
	return float(_action_states[action]["strength"])
#endregion


#region Input Context & State Management
func set_gameplay_input_enabled(enabled: bool) -> void:
	if gameplay_input_enabled == enabled:
		return
	gameplay_input_enabled = enabled
	if not enabled:
		_release_context_actions(InputContextType.Context.GAMEPLAY)
		_sync_ime_state()
	else:
		_arm_wait_for_release_on_gameplay_actions()
		_sync_ime_state()


func push_context(context: int) -> void:
	var was_gameplay_allowed := _is_context_allowed(InputContextType.Context.GAMEPLAY)
	_context_stack.append(context)
	var now_gameplay_allowed := _is_context_allowed(InputContextType.Context.GAMEPLAY)
	if was_gameplay_allowed and not now_gameplay_allowed:
		_release_context_actions(InputContextType.Context.GAMEPLAY)
	_sync_ime_state()


func pop_context(context: int) -> void:
	var was_gameplay_allowed := _is_context_allowed(InputContextType.Context.GAMEPLAY)
	for i in range(_context_stack.size() - 1, 0, -1):
		if _context_stack[i] == context:
			_context_stack.remove_at(i)
			break
	var now_gameplay_allowed := _is_context_allowed(InputContextType.Context.GAMEPLAY)
	if not was_gameplay_allowed and now_gameplay_allowed:
		_arm_wait_for_release_on_gameplay_actions()
	_sync_ime_state()


func get_active_context() -> int:
	return _context_stack[_context_stack.size() - 1] if not _context_stack.is_empty() else InputContextType.Context.GAMEPLAY


func flush_all_states() -> void:
	_wait_release_triggers.clear()
	_chord_consumed_triggers.clear()
	_pending_press_proc.clear()
	_pending_press_phys.clear()
	for act in _adapter.get_managed_actions():
		if InputMap.has_action(act) and Input.is_action_pressed(act):
			Input.action_release(act)
		if _action_states.has(act):
			var st: Dictionary = _action_states[act]
			st["pressed"] = false
			st["pressed_proc"] = false
			st["pressed_phys"] = false
			st["strength"] = 0.0


func register_action(
	action: StringName,
	context: int = InputContextType.Context.GAMEPLAY,
	rebindable: bool = true,
	is_axis: bool = false
) -> void:
	_adapter.register_action_meta(action, context, rebindable, is_axis)
	_ensure_action_state_entry(action)
#endregion


#region Keybinding & Interactive Capture APIs
func rebind_interactive_async(
	action: StringName,
	device_type: int,
	slot: int = InputBindingSlot.Slot.PRIMARY,
	conflict_policy: int = InputConflictPolicy.Policy.SWAP,
	timeout_sec: float = 5.0
) -> Result:
	if not _adapter.has_action(action):
		return Result.err_code(InputError.ACTION_NOT_FOUND, "Action '%s' is not registered." % String(action))
	if not _adapter.is_action_rebindable(action):
		return Result.err_code(InputError.ACTION_LOCKED, "Action '%s' is locked and cannot be rebound." % String(action))

	var start_res := _capturer.start_capture(action, device_type, timeout_sec)
	if start_res.is_err():
		return start_res

	var vp := get_viewport()
	_rebind_initiator_control = vp.gui_get_hovered_control() if vp != null else null

	push_context(InputContextType.Context.REBIND)
	rebind_started.emit(action, device_type, slot)

	var capture_res: Result = await _capturer.rebind_finished
	_rebind_initiator_control = null
	_rebind_cooldown_frames = 0
	pop_context(InputContextType.Context.REBIND)

	if capture_res.is_err():
		rebind_completed.emit(action, capture_res)
		return capture_res

	var captured_chord := capture_res.value as InputChord
	var bind_res := bind_chord(action, captured_chord, slot, conflict_policy)
	if bind_res.is_err():
		rebind_completed.emit(action, bind_res)
		return bind_res

	var glyph := get_action_glyph(action, device_type, slot)
	var final_res := Result.ok(glyph)
	rebind_completed.emit(action, final_res)
	return final_res


func cancel_rebind() -> void:
	_capturer.cancel_capture()


func is_rebinding() -> bool:
	return _capturer.is_capturing()


func bind_chord(
	action: StringName,
	chord: InputChord,
	slot: int = InputBindingSlot.Slot.PRIMARY,
	conflict_policy: int = InputConflictPolicy.Policy.SWAP
) -> Result:
	flush_all_states()
	var res := _adapter.bind_chord(action, chord, slot, conflict_policy)
	if res.is_ok():
		var affected: Array = res.value if res.value is Array else [action]
		for act in affected:
			var act_name := act as StringName
			bindings_changed.emit(act_name)
			if Bus != null:
				Bus.input_bindings_changed.emit(act_name)
	return res


func bind_event(
	action: StringName,
	event: InputEvent,
	slot: int = InputBindingSlot.Slot.PRIMARY,
	conflict_policy: int = InputConflictPolicy.Policy.SWAP
) -> Result:
	return bind_chord(action, InputChord.from_event(event), slot, conflict_policy)


func unbind_slot(action: StringName, device_type: int, slot: int = InputBindingSlot.Slot.PRIMARY) -> Result:
	flush_all_states()
	var res := _adapter.unbind_slot(action, device_type, slot)
	if res.is_ok():
		bindings_changed.emit(action)
		if Bus != null:
			Bus.input_bindings_changed.emit(action)
	return res


func reset_to_default(action: StringName = &"", device_type: int = -1) -> Result:
	flush_all_states()
	var res := _adapter.reset_to_default(action, device_type)
	if res.is_ok():
		bindings_changed.emit(action)
		if Bus != null:
			Bus.input_bindings_changed.emit(action)
	return res
#endregion


#region Glyph Prompts, Deadzone & Persistence APIs
func get_action_glyph(
	action: StringName,
	device_type: int = -1,
	slot: int = InputBindingSlot.Slot.PRIMARY
) -> InputGlyphInfo:
	var target_device := device_type if device_type >= 0 else current_device
	var chord := _adapter.get_chord(action, target_device, slot)
	# 若主槽位为空且调用方请求主槽位展示，自动回退尝试副槽位
	if chord.is_empty() and slot == InputBindingSlot.Slot.PRIMARY:
		var fallback := _adapter.get_chord(action, target_device, InputBindingSlot.Slot.SECONDARY)
		if not fallback.is_empty():
			chord = fallback
	return InputGlyphInfo.from_chord(chord, action, target_device, current_joy_brand)


func get_action_chord(
	action: StringName,
	device_type: int,
	slot: int = InputBindingSlot.Slot.PRIMARY
) -> InputChord:
	return _adapter.get_chord(action, device_type, slot)


func get_managed_actions(context_filter: int = -1) -> Array[StringName]:
	return _adapter.get_managed_actions(context_filter)


func set_joy_deadzone(deadzone: float) -> void:
	_adapter.set_joy_deadzone(deadzone)


func get_joy_deadzone() -> float:
	return _adapter.get_joy_deadzone()


func simulate_device(device_type: int, joy_brand: int = -1) -> void:
	_tracker.set_Simulated_device(device_type, joy_brand, active_joy_id)


func export_bindings() -> Dictionary:
	return _adapter.export_delta_dict()


func import_bindings(payload: Dictionary) -> Result:
	flush_all_states()
	var res := _adapter.import_delta_dict(payload)
	if res.is_ok():
		bindings_changed.emit(&"")
		if Bus != null:
			Bus.input_bindings_changed.emit(&"")
	return res
#endregion


#region Internal Chord Evaluation Pipeline
func _record_pending_press_from_event(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		return
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	if event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		if absf(jm.axis_value) >= 0.50:
			var clean_axis := InputChord.make_joy_axis_event(jm.axis, 1.0 if jm.axis_value >= 0.0 else -1.0)
			var axis_sig := InputChord.get_single_event_signature(clean_axis)
			_pending_press_proc[axis_sig] = true
			_pending_press_phys[axis_sig] = true
		return
	if not event.is_pressed():
		return
	var clean_ev := InputChord.clean_single_event(event)
	if clean_ev != null:
		var sig := InputChord.get_single_event_signature(clean_ev)
		_pending_press_proc[sig] = true
		_pending_press_phys[sig] = true
	if event is InputEventWithModifiers:
		var mod_ev := event as InputEventWithModifiers
		if mod_ev.shift_pressed:
			var s_sig := "KEY_%d" % int(KEY_SHIFT)
			_pending_press_proc[s_sig] = true
			_pending_press_phys[s_sig] = true
		if mod_ev.ctrl_pressed:
			var c_sig := "KEY_%d" % int(KEY_CTRL)
			_pending_press_proc[c_sig] = true
			_pending_press_phys[c_sig] = true
		if mod_ev.alt_pressed:
			var a_sig := "KEY_%d" % int(KEY_ALT)
			_pending_press_proc[a_sig] = true
			_pending_press_phys[a_sig] = true
		if mod_ev.meta_pressed:
			var m_sig := "KEY_%d" % int(KEY_META)
			_pending_press_proc[m_sig] = true
			_pending_press_phys[m_sig] = true


func _is_chord_active_in_frame(chord: InputChord, dz: float, pending_press: Dictionary) -> bool:
	if chord == null or chord.trigger == null:
		return false
	for m in chord.modifiers:
		var m_sig := InputChord.get_single_event_signature(m)
		if not InputChord.is_single_event_pressed_now(m, active_joy_id, dz) and not pending_press.has(m_sig):
			return false
	var trig_sig := chord.get_trigger_signature()
	return InputChord.is_single_event_pressed_now(chord.trigger, active_joy_id, dz) or pending_press.has(trig_sig)


func _ensure_evaluated() -> void:
	_evaluate_for_current_frame(Engine.is_in_physics_frame())


func _evaluate_for_current_frame(is_physics: bool) -> void:
	var proc_frame := Engine.get_process_frames()
	var phys_frame := Engine.get_physics_frames()
	if is_physics:
		if _last_eval_physics_frame == phys_frame:
			return
		_last_eval_physics_frame = phys_frame
	else:
		if _last_eval_process_frame == proc_frame:
			return
		_last_eval_process_frame = proc_frame

	var pending_press: Dictionary = _pending_press_phys if is_physics else _pending_press_proc
	var dz := _adapter.get_joy_deadzone()

	# 1. 更新防穿透抬起解锁表 (_wait_release_triggers)：已松开的物理键立即解除锁定
	if not _wait_release_triggers.is_empty():
		var to_remove: Array[String] = []
		for trig_sig in _wait_release_triggers.keys():
			var ev: InputEvent = _wait_release_triggers[trig_sig]
			if ev == null or not InputChord.is_single_event_pressed_now(ev, active_joy_id, dz):
				to_remove.append(trig_sig)
		for sig in to_remove:
			_wait_release_triggers.erase(sig)

	# 1b. 更新高阶组合键消费锁 (_chord_consumed_triggers)：已松开（或重新按下）的物理键解除单键抑制
	if not _chord_consumed_triggers.is_empty():
		var released_consumed: Array[String] = []
		for trig_sig in _chord_consumed_triggers.keys():
			var ev: InputEvent = _chord_consumed_triggers[trig_sig]
			if ev == null or not InputChord.is_single_event_pressed_now(ev, active_joy_id, dz) or pending_press.has(trig_sig):
				released_consumed.append(trig_sig)
		for sig in released_consumed:
			_chord_consumed_triggers.erase(sig)

	# 2. 第一遍扫描：评估所有高阶组合键（order >= 1），将已触发组合键的主键与修饰键记入同帧消费池与持续抑制表
	var consumed_triggers_by_ctx: Dictionary = {}
	for act in _adapter.get_managed_actions():
		if _adapter.is_axis_action(act):
			continue
		var ctx := _adapter.get_action_context(act)
		if not _is_context_allowed(ctx):
			continue
		for chord in _adapter.get_all_chords(act):
			if not chord.is_chord():
				continue
			var trig_sig := chord.get_trigger_signature()
			if _wait_release_triggers.has(trig_sig):
				continue
			if _is_chord_active_in_frame(chord, dz, pending_press):
				if not consumed_triggers_by_ctx.has(ctx):
					consumed_triggers_by_ctx[ctx] = {}
				consumed_triggers_by_ctx[ctx][trig_sig] = true
				_chord_consumed_triggers[trig_sig] = chord.trigger
				for mod_ev in chord.modifiers:
					var mod_sig := InputChord.get_single_event_signature(mod_ev)
					consumed_triggers_by_ctx[ctx][mod_sig] = true
					_chord_consumed_triggers[mod_sig] = mod_ev

	# 3. 第二遍扫描：结算每个 Action 的最终按压态并独立更新当前通道（Process 或 Physics）的边沿帧戳
	for act in _adapter.get_managed_actions():
		_ensure_action_state_entry(act)
		var st: Dictionary = _action_states[act]
		var was_pressed := bool(st["pressed_phys"]) if is_physics else bool(st["pressed_proc"])
		var ctx := _adapter.get_action_context(act)

		if not _is_context_allowed(ctx):
			_apply_action_frame_transition(st, is_physics, was_pressed, false, false, false, 0.0, proc_frame, phys_frame)
			continue

		if _adapter.is_axis_action(act):
			var axis_strength := _compute_axis_action_strength(act, dz, pending_press)
			var axis_active := axis_strength > 0.25
			var axis_hw_held := _compute_axis_action_strength(act, dz) > 0.25
			var axis_fresh := _has_any_chord_fresh_press(act, pending_press)
			_apply_action_frame_transition(
				st, is_physics, was_pressed, axis_active, axis_hw_held, axis_fresh, axis_strength, proc_frame, phys_frame
			)
			continue

		var ctx_consumed: Dictionary = consumed_triggers_by_ctx.get(ctx, {})
		var now_pressed := false
		var hw_held := false
		var fresh_press := false
		var best_strength := 0.0

		for chord in _adapter.get_all_chords(act):
			var trig_sig := chord.get_trigger_signature()
			if _wait_release_triggers.has(trig_sig):
				continue
			if chord.is_chord():
				if _is_chord_active_in_frame(chord, dz, pending_press):
					now_pressed = true
					if chord.are_modifiers_pressed_now(active_joy_id, dz) and chord.is_trigger_pressed_now(active_joy_id, dz):
						hw_held = true
					if pending_press.has(trig_sig):
						fresh_press = true
					best_strength = maxf(best_strength, maxf(chord.get_strength_now(active_joy_id, dz, false), 1.0))
			else:
				# 单键绑定：若触发键在本帧已被高阶组合键消费，或处于组合键消费后的未松开阶段，则自动抑制单键触发
				if ctx_consumed.has(trig_sig) or _chord_consumed_triggers.has(trig_sig):
					continue
				var trig_hw := chord.is_trigger_pressed_now(active_joy_id, dz)
				var trig_pending := pending_press.has(trig_sig)
				if trig_hw or trig_pending:
					now_pressed = true
					if trig_hw:
						hw_held = true
					if trig_pending:
						fresh_press = true
					best_strength = maxf(
						best_strength,
						maxf(chord.get_strength_now(active_joy_id, dz, true), 1.0 if trig_pending else 0.0)
					)

		_apply_action_frame_transition(
			st, is_physics, was_pressed, now_pressed, hw_held, fresh_press, best_strength, proc_frame, phys_frame
		)

	pending_press.clear()


func _compute_axis_action_strength(action: StringName, dz: float, pending_press: Dictionary = {}) -> float:
	if not _adapter.has_action(action):
		return Input.get_action_strength(action) if InputMap.has_action(action) else 0.0
	var best := 0.0
	for chord in _adapter.get_all_chords(action):
		# 连续轴向动作强制 ignore_modifiers = true，保证按住 Shift/Ctrl 时 WASD 移动不断触
		var s := chord.get_strength_now(active_joy_id, dz, true)
		if s < 1.0 and not pending_press.is_empty() and pending_press.has(chord.get_trigger_signature()):
			s = 1.0
		if s > best:
			best = s
	return best


func _has_any_chord_fresh_press(action: StringName, pending_press: Dictionary) -> bool:
	if pending_press.is_empty():
		return false
	for chord in _adapter.get_all_chords(action):
		if pending_press.has(chord.get_trigger_signature()):
			return true
	return false


func _apply_action_frame_transition(
	st: Dictionary,
	is_physics: bool,
	was_pressed: bool,
	now_pressed: bool,
	hw_held: bool,
	fresh_press: bool,
	strength: float,
	proc_frame: int,
	phys_frame: int
) -> void:
	st["pressed"] = now_pressed
	st["strength"] = strength if now_pressed else 0.0
	if is_physics:
		st["pressed_phys"] = hw_held if now_pressed else false
		if now_pressed and (not was_pressed or fresh_press):
			st["jp_phys"] = phys_frame
			if not hw_held:
				st["jr_phys"] = phys_frame
		elif not now_pressed and was_pressed:
			st["jr_phys"] = phys_frame
	else:
		st["pressed_proc"] = hw_held if now_pressed else false
		if now_pressed and (not was_pressed or fresh_press):
			st["jp_proc"] = proc_frame
			if not hw_held:
				st["jr_proc"] = proc_frame
		elif not now_pressed and was_pressed:
			st["jr_proc"] = proc_frame


func _is_context_allowed(action_ctx: int) -> bool:
	if action_ctx == InputContextType.Context.SYSTEM:
		return get_active_context() != InputContextType.Context.REBIND
	if action_ctx == InputContextType.Context.GAMEPLAY:
		if not gameplay_input_enabled:
			return false
		for stacked_ctx in _context_stack:
			if InputContextType.blocks_gameplay(stacked_ctx):
				return false
		return true
	return get_active_context() == action_ctx


func _release_context_actions(target_ctx: int) -> void:
	_pending_press_proc.clear()
	_pending_press_phys.clear()
	for act in _adapter.get_managed_actions(target_ctx):
		if InputMap.has_action(act) and Input.is_action_pressed(act):
			Input.action_release(act)
		if _action_states.has(act):
			var st: Dictionary = _action_states[act]
			st["pressed"] = false
			st["pressed_proc"] = false
			st["pressed_phys"] = false
			st["strength"] = 0.0


func _arm_wait_for_release_on_gameplay_actions() -> void:
	var dz := _adapter.get_joy_deadzone()
	for act in _adapter.get_managed_actions(InputContextType.Context.GAMEPLAY):
		if _adapter.is_axis_action(act):
			continue
		for chord in _adapter.get_all_chords(act):
			if chord.trigger != null and InputChord.is_single_event_pressed_now(chord.trigger, active_joy_id, dz):
				_wait_release_triggers[chord.get_trigger_signature()] = chord.trigger


func _ensure_action_state_entry(action: StringName) -> void:
	if not _action_states.has(action):
		_action_states[action] = {
			"pressed": false,
			"pressed_proc": false,
			"pressed_phys": false,
			"strength": 0.0,
			"jp_proc": -1,
			"jr_proc": -1,
			"jp_phys": -1,
			"jr_phys": -1,
		}


func _sync_ime_state() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# 桌面端战斗态与按键录制态强制关闭输入法候选框，防止中文输入法拦截 WASD 或改键按键
	if _is_context_allowed(InputContextType.Context.GAMEPLAY) or get_active_context() == InputContextType.Context.REBIND:
		DisplayServer.window_set_ime_active(false)


func _on_tracker_device_changed(device_type: int, joy_brand: int, joy_id: int) -> void:
	current_device = device_type
	current_joy_brand = joy_brand
	active_joy_id = joy_id
	device_changed.emit(device_type, joy_brand)
	if Bus != null:
		Bus.input_device_changed.emit(device_type, joy_brand)


func _on_tracker_joypad_connection_changed(device_id: int, connected: bool) -> void:
	active_joy_id = _tracker.active_joy_id
	current_joy_brand = _tracker.current_joy_brand
	if Bus != null:
		Bus.joypad_connection_changed.emit(device_id, connected)


func _on_capturer_preview_changed(preview_glyph: InputGlyphInfo) -> void:
	rebind_preview.emit(preview_glyph)


func _log_info(msg: String) -> void:
	if _logger != null:
		_logger.info("Input", msg)
	else:
		FrameworkLogger.print_raw(LogLevel.INFO, "Input", msg)
#endregion
