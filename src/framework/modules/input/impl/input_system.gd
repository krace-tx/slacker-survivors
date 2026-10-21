class_name InputSystem
extends BaseInputSystem

## 输入与键位映射系统核心实现（Input & Keybinding System Implementation）。[br]
##
## 汇聚四大子组件能力：[br]
## 1. [InputDeviceTracker]：硬件输入嗅探、0.5 唤醒阈值防抖切换与手柄型号识别；[br]
## 2. [InputMapAdapter]：出厂基线快照、键鼠/手柄双轨双槽隔离、同域冲突互换与增量序列化；[br]
## 3. [InputRebindCapturer]：二段式免勾选录制状态机（按住修饰等主键、松开修饰算单键）；[br]
## 4. 高阶组合键优先消费管线（Highest-Order Chord Consumption）+ 双帧号（Process/Physics）独立对齐。

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
## { StringName: { "pressed": bool, "strength": float, "jp_proc": int, "jr_proc": int, "jp_phys": int, "jr_phys": int } }
var _action_states: Dictionary = {}

## 防穿透抬起解锁集合：记录从 UI/REBIND 切回 GAMEPLAY 时仍处于按住状态的物理触发键签名
var _wait_release_triggers: Dictionary = {}

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
	if is_inside_tree():
		queue_free()


func _input(event: InputEvent) -> void:
	if event == null:
		return

	# 1. 若处于交互式按键录制中，或处于录制刚结束的防穿透冷却帧，优先拦截并吞没输入
	if _capturer.is_capturing():
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
	for act in _adapter.get_managed_actions():
		if InputMap.has_action(act) and Input.is_action_pressed(act):
			Input.action_release(act)
		if _action_states.has(act):
			var st: Dictionary = _action_states[act]
			st["pressed"] = false
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

	push_context(InputContextType.Context.REBIND)
	rebind_started.emit(action, device_type, slot)

	var capture_res: Result = await _capturer.rebind_finished
	_rebind_cooldown_frames = 2
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

	# 2. 第一遍扫描：评估所有高阶组合键（order >= 1），将已触发组合键的主键与修饰键记入同帧消费池
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
			if chord.are_modifiers_pressed_now(active_joy_id, dz) and chord.is_trigger_pressed_now(active_joy_id, dz):
				if not consumed_triggers_by_ctx.has(ctx):
					consumed_triggers_by_ctx[ctx] = {}
				consumed_triggers_by_ctx[ctx][trig_sig] = true
				for mod_ev in chord.modifiers:
					consumed_triggers_by_ctx[ctx][InputChord.get_single_event_signature(mod_ev)] = true

	# 3. 第二遍扫描：结算每个 Action 的最终按压态并更新双帧边沿时间戳
	for act in _adapter.get_managed_actions():
		_ensure_action_state_entry(act)
		var st: Dictionary = _action_states[act]
		var was_pressed := bool(st["pressed"])
		var ctx := _adapter.get_action_context(act)

		if not _is_context_allowed(ctx):
			_apply_action_frame_transition(st, was_pressed, false, 0.0, proc_frame, phys_frame)
			continue

		if _adapter.is_axis_action(act):
			var axis_strength := _compute_axis_action_strength(act, dz)
			_apply_action_frame_transition(st, was_pressed, axis_strength > 0.25, axis_strength, proc_frame, phys_frame)
			continue

		var ctx_consumed: Dictionary = consumed_triggers_by_ctx.get(ctx, {})
		var now_pressed := false
		var best_strength := 0.0

		for chord in _adapter.get_all_chords(act):
			var trig_sig := chord.get_trigger_signature()
			if _wait_release_triggers.has(trig_sig):
				continue
			if chord.is_chord():
				if chord.are_modifiers_pressed_now(active_joy_id, dz) and chord.is_trigger_pressed_now(active_joy_id, dz):
					now_pressed = true
					best_strength = maxf(best_strength, chord.get_strength_now(active_joy_id, dz, false))
			else:
				# 单键绑定：若触发键在本帧已被同域高阶组合键消费，则自动抑制单键触发
				if ctx_consumed.has(trig_sig):
					continue
				if chord.is_trigger_pressed_now(active_joy_id, dz):
					now_pressed = true
					best_strength = maxf(best_strength, chord.get_strength_now(active_joy_id, dz, true))

		_apply_action_frame_transition(st, was_pressed, now_pressed, best_strength, proc_frame, phys_frame)


func _compute_axis_action_strength(action: StringName, dz: float) -> float:
	if not _adapter.has_action(action):
		return Input.get_action_strength(action) if InputMap.has_action(action) else 0.0
	var best := 0.0
	for chord in _adapter.get_all_chords(action):
		# 连续轴向动作强制 ignore_modifiers = true，保证按住 Shift/Ctrl 时 WASD 移动不断触
		var s := chord.get_strength_now(active_joy_id, dz, true)
		if s > best:
			best = s
	return best


func _apply_action_frame_transition(
	st: Dictionary,
	was_pressed: bool,
	now_pressed: bool,
	strength: float,
	proc_frame: int,
	phys_frame: int
) -> void:
	st["pressed"] = now_pressed
	st["strength"] = strength if now_pressed else 0.0
	if now_pressed and not was_pressed:
		st["jp_proc"] = proc_frame
		st["jp_phys"] = phys_frame
	elif not now_pressed and was_pressed:
		st["jr_proc"] = proc_frame
		st["jr_phys"] = phys_frame


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
	for act in _adapter.get_managed_actions(target_ctx):
		if InputMap.has_action(act) and Input.is_action_pressed(act):
			Input.action_release(act)
		if _action_states.has(act):
			var st: Dictionary = _action_states[act]
			st["pressed"] = false
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
			"strength": 0.0,
			"jp_proc": -1,
			"jr_proc": -1,
			"jp_phys": -1,
			"jr_phys": -1,
		}


func _sync_ime_state() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# 桌面端战斗态自动关闭输入法候选框，防止中文输入法拦截 WASD
	var allow_ime := not _is_context_allowed(InputContextType.Context.GAMEPLAY)
	DisplayServer.window_set_ime_active(allow_ime)


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
