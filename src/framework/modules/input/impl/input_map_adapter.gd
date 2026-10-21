class_name InputMapAdapter
extends RefCounted

## Godot InputMap 与双轨键位表引擎适配器（InputMap & Dual-Track Binding Adapter）。[br]
##
## 核心职责：[br]
## 1. [b]基线快照（Baseline Snapshot）[/b]：启动时自动扫描 [InputMap] 并确保核心游戏动作存在，建立不可变出厂默认快照 [member _default_bindings]；[br]
## 2. [b]键鼠/手柄双轨双槽隔离[/b]：每个 Action 独立维护 [code]kb_0 / kb_1 / joy_0 / joy_1[/code] 四个 [InputChord] 槽位，修改键盘绝不覆盖手柄；[br]
## 3. [b]同作用域冲突裁决[/b]：在同一 [InputContextType] 与同一设备轨道下执行 SWAP / REJECT / CLEAR_EXISTING 冲突处理；[br]
## 4. [b]增量补丁持久化（Delta Serialization）[/b]：仅导出与出厂基线不同的槽位，升级版本新增动作永不坏档。

const SCHEMA_VERSION: int = 1

## Action 元数据表：{ StringName: { "context": int, "rebindable": bool, "is_axis": bool } }
var _action_meta: Dictionary = {}

## 出厂默认基线快照：{ StringName: { "kb_0": InputChord, "kb_1": InputChord, "joy_0": InputChord, "joy_1": InputChord } }
var _default_bindings: Dictionary = {}

## 当前运行时生效绑定表（结构同 _default_bindings）
var _active_bindings: Dictionary = {}

## 全局手柄摇杆死区 (0.05 ~ 0.9)
var _joy_deadzone: float = 0.20


#region Initialization & Baseline Snapshot
## 初始化适配器：确保标准游戏动作就绪，提取出厂快照并同步至 Godot InputMap
func initialize() -> void:
	_ensure_builtin_game_actions()
	_snapshot_project_actions()
	_sync_all_to_engine()


## 释放内部持有的 InputEvent 资源引用，防止退出时 Resource 泄漏告警
func dispose() -> void:
	_default_bindings.clear()
	_active_bindings.clear()
	_action_meta.clear()


## 注册或更新单个 Action 的上下文作用域与改键权限规则
func register_action_meta(
	action: StringName,
	context: int = InputContextType.Context.GAMEPLAY,
	rebindable: bool = true,
	is_axis: bool = false
) -> void:
	_action_meta[action] = {
		"context": context,
		"rebindable": rebindable,
		"is_axis": is_axis,
	}
	if not _default_bindings.has(action):
		_default_bindings[action] = _create_empty_slots()
		_active_bindings[action] = _create_empty_slots()
	if not InputMap.has_action(action):
		InputMap.add_action(action, _joy_deadzone)


## 查询指定 Action 是否受本系统管理
func has_action(action: StringName) -> bool:
	return _active_bindings.has(action)


## 获取全部受管 Action 列表
func get_managed_actions(context_filter: int = -1) -> Array[StringName]:
	var out: Array[StringName] = []
	for k in _active_bindings.keys():
		var act := k as StringName
		if context_filter < 0 or get_action_context(act) == context_filter:
			out.append(act)
	return out


## 获取指定 Action 所属的 [enum InputContextType.Context]
func get_action_context(action: StringName) -> int:
	if _action_meta.has(action):
		return int(_action_meta[action].get("context", InputContextType.Context.GAMEPLAY))
	return InputContextType.Context.GAMEPLAY


## 判断指定 Action 是否允许玩家自定义改键
func is_action_rebindable(action: StringName) -> bool:
	if _action_meta.has(action):
		return bool(_action_meta[action].get("rebindable", true))
	return true


## 判断指定 Action 是否为移动/连续轴向动作（豁免组合键修饰锁）
func is_axis_action(action: StringName) -> bool:
	if _action_meta.has(action):
		return bool(_action_meta[action].get("is_axis", false))
	return false
#endregion


#region Query & Mutation
## 获取指定动作在特定设备轨道与槽位下的 [InputChord]
func get_chord(action: StringName, device_type: int, slot: int = InputBindingSlot.Slot.PRIMARY) -> InputChord:
	if not _active_bindings.has(action):
		return InputChord.empty()
	var slot_key := InputBindingSlot.make_slot_key(device_type, slot)
	var chord: InputChord = _active_bindings[action].get(slot_key, null)
	return chord.duplicate_chord() if chord != null else InputChord.empty()


## 获取指定动作在特定设备轨道下的全部非空 [InputChord]（主槽位 + 副槽位）
func get_device_chords(action: StringName, device_type: int) -> Array[InputChord]:
	var list: Array[InputChord] = []
	if not _active_bindings.has(action):
		return list
	for slot in [InputBindingSlot.Slot.PRIMARY, InputBindingSlot.Slot.SECONDARY]:
		var sk := InputBindingSlot.make_slot_key(device_type, slot)
		var c: InputChord = _active_bindings[action].get(sk, null)
		if c != null and not c.is_empty():
			list.append(c)
	return list


## 获取指定动作在全部设备轨道下的非空 [InputChord]
func get_all_chords(action: StringName) -> Array[InputChord]:
	var list: Array[InputChord] = []
	if not _active_bindings.has(action):
		return list
	for sk in ["kb_0", "kb_1", "joy_0", "joy_1"]:
		var c: InputChord = _active_bindings[action].get(sk, null)
		if c != null and not c.is_empty():
			list.append(c)
	return list


## 将一个 [InputChord] 绑定到目标动作槽位，并根据 [enum InputConflictPolicy.Policy] 执行同域冲突裁决。[br]
## 成功时返回 [code]Result.ok(affected_actions: Array[StringName])[/code]。
func bind_chord(
	action: StringName,
	chord: InputChord,
	slot: int = InputBindingSlot.Slot.PRIMARY,
	conflict_policy: int = InputConflictPolicy.Policy.SWAP
) -> Result:
	if not has_action(action):
		return Result.err_code(InputError.ACTION_NOT_FOUND, "Action '%s' is not registered." % String(action))
	if not is_action_rebindable(action):
		return Result.err_code(InputError.ACTION_LOCKED, "Action '%s' is locked and cannot be rebound." % String(action))
	if chord == null or chord.is_empty():
		return Result.err_code(InputError.INVALID_EVENT, "Cannot bind an empty InputChord to '%s'." % String(action))

	var device_type := chord.get_device_type()
	var target_slot_key := InputBindingSlot.make_slot_key(device_type, slot)
	var new_sig := chord.get_signature()
	var previous_chord: InputChord = _active_bindings[action].get(target_slot_key, InputChord.empty())

	# 若与自身当前槽位完全一致，直接幂等成功
	if previous_chord != null and previous_chord.get_signature() == new_sig:
		return Result.ok([action])

	# 若与同一 Action 的另一个槽位（如主副键互绑）重复，自动对调本 Action 的主副槽
	var sibling_slot := InputBindingSlot.Slot.SECONDARY if slot == InputBindingSlot.Slot.PRIMARY else InputBindingSlot.Slot.PRIMARY
	var sibling_key := InputBindingSlot.make_slot_key(device_type, sibling_slot)
	var sibling_chord: InputChord = _active_bindings[action].get(sibling_key, InputChord.empty())
	if sibling_chord != null and sibling_chord.get_signature() == new_sig:
		_active_bindings[action][sibling_key] = previous_chord.duplicate_chord()
		_active_bindings[action][target_slot_key] = chord.duplicate_chord()
		_sync_action_to_engine(action)
		return Result.ok([action])

	# 查找同一 Context + 同一设备轨道下的冲突动作槽位
	var target_ctx := get_action_context(action)
	var conflict_action: StringName = &""
	var conflict_slot_key: String = ""

	if conflict_policy != InputConflictPolicy.Policy.ALLOW:
		for other_key in _active_bindings.keys():
			var other_act := other_key as StringName
			if other_act == action:
				continue
			if get_action_context(other_act) != target_ctx:
				continue
			for s_idx in [InputBindingSlot.Slot.PRIMARY, InputBindingSlot.Slot.SECONDARY]:
				var sk := InputBindingSlot.make_slot_key(device_type, s_idx)
				var other_chord: InputChord = _active_bindings[other_act].get(sk, null)
				if other_chord != null and other_chord.get_signature() == new_sig:
					conflict_action = other_act
					conflict_slot_key = sk
					break
			if not conflict_action.is_empty():
				break

	var affected: Array[StringName] = [action]
	if not conflict_action.is_empty():
		match conflict_policy:
			InputConflictPolicy.Policy.REJECT:
				return Result.err_code(
					InputError.BINDING_CONFLICT,
					"Binding '%s' conflicts with action '%s'." % [new_sig, String(conflict_action)]
				)
			InputConflictPolicy.Policy.SWAP:
				if is_action_rebindable(conflict_action):
					_active_bindings[conflict_action][conflict_slot_key] = previous_chord.duplicate_chord()
					_sync_action_to_engine(conflict_action)
					affected.append(conflict_action)
				else:
					return Result.err_code(
						InputError.BINDING_CONFLICT,
						"Binding conflicts with locked system action '%s'." % String(conflict_action)
					)
			InputConflictPolicy.Policy.CLEAR_EXISTING:
				if is_action_rebindable(conflict_action):
					_active_bindings[conflict_action][conflict_slot_key] = InputChord.empty()
					_sync_action_to_engine(conflict_action)
					affected.append(conflict_action)
				else:
					return Result.err_code(
						InputError.BINDING_CONFLICT,
						"Binding conflicts with locked system action '%s'." % String(conflict_action)
					)

	_active_bindings[action][target_slot_key] = chord.duplicate_chord()
	_sync_action_to_engine(action)
	return Result.ok(affected)


## 清空指定动作槽位的绑定
func unbind_slot(action: StringName, device_type: int, slot: int = InputBindingSlot.Slot.PRIMARY) -> Result:
	if not has_action(action):
		return Result.err_code(InputError.ACTION_NOT_FOUND, "Action '%s' is not registered." % String(action))
	if not is_action_rebindable(action):
		return Result.err_code(InputError.ACTION_LOCKED, "Action '%s' is locked." % String(action))
	var sk := InputBindingSlot.make_slot_key(device_type, slot)
	_active_bindings[action][sk] = InputChord.empty()
	_sync_action_to_engine(action)
	return Result.ok([action])


## 恢复出厂默认键位。[br]
## - [param action] 为空时重置全部受管动作；非空时仅重置该动作；[br]
## - [param device_type] 为 -1 时同时重置键鼠与手柄；否则仅重置指定设备轨道。
func reset_to_default(action: StringName = &"", device_type: int = -1) -> Result:
	if not action.is_empty() and not has_action(action):
		return Result.err_code(InputError.ACTION_NOT_FOUND, "Action '%s' is not registered." % String(action))

	var targets: Array[StringName] = []
	if action.is_empty():
		for k in _default_bindings.keys():
			targets.append(k as StringName)
	else:
		targets.append(action)

	var slot_keys := _resolve_slot_keys(device_type)
	for act in targets:
		var def_slots: Dictionary = _default_bindings[act]
		for sk in slot_keys:
			var def_chord: InputChord = def_slots.get(sk, InputChord.empty())
			_active_bindings[act][sk] = def_chord.duplicate_chord()
		_sync_action_to_engine(act)

	return Result.ok(targets)


## 设置统一摇杆死区并同步至 InputMap
func set_joy_deadzone(deadzone: float) -> void:
	_joy_deadzone = clampf(deadzone, 0.05, 0.90)
	for k in _active_bindings.keys():
		var act := k as StringName
		if InputMap.has_action(act):
			InputMap.action_set_deadzone(act, _joy_deadzone)


func get_joy_deadzone() -> float:
	return _joy_deadzone
#endregion


#region Delta Serialization (Baseline + Diff Patch)
## 仅导出与出厂默认基线不同的增量键位补丁（Delta-Only Serialization）
func export_delta_dict() -> Dictionary:
	var deltas: Dictionary = {}
	for k in _active_bindings.keys():
		var act := k as StringName
		var act_str := String(act)
		var def_slots: Dictionary = _default_bindings.get(act, {})
		var cur_slots: Dictionary = _active_bindings.get(act, {})
		var act_diff: Dictionary = {}

		for sk in ["kb_0", "kb_1", "joy_0", "joy_1"]:
			var def_c: InputChord = def_slots.get(sk, InputChord.empty())
			var cur_c: InputChord = cur_slots.get(sk, InputChord.empty())
			if def_c.get_signature() != cur_c.get_signature():
				act_diff[sk] = cur_c.to_dict()

		if not act_diff.is_empty():
			deltas[act_str] = act_diff

	return {
		"schema_version": SCHEMA_VERSION,
		"joy_deadzone": _joy_deadzone,
		"deltas": deltas,
	}


## 从增量补丁字典恢复用户自定义键位（先还原基线快照，再叠加有效增量补丁）
func import_delta_dict(payload: Dictionary) -> Result:
	reset_to_default()
	if payload.is_empty():
		return Result.ok()

	if payload.has("joy_deadzone"):
		set_joy_deadzone(float(payload.get("joy_deadzone", 0.20)))

	var deltas_var: Variant = payload.get("deltas", payload)
	if not (deltas_var is Dictionary):
		return Result.err_code(InputError.DESERIALIZE_FAILED, "Invalid input bindings delta dictionary.")

	var deltas := deltas_var as Dictionary
	for act_str in deltas.keys():
		var act := StringName(str(act_str))
		if not has_action(act) or not is_action_rebindable(act):
			continue
		var slot_map_var: Variant = deltas[act_str]
		if not (slot_map_var is Dictionary):
			continue
		var slot_map := slot_map_var as Dictionary
		for sk in ["kb_0", "kb_1", "joy_0", "joy_1"]:
			if not slot_map.has(sk):
				continue
			var chord_dict_var: Variant = slot_map[sk]
			if chord_dict_var is Dictionary:
				_active_bindings[act][sk] = InputChord.from_dict(chord_dict_var as Dictionary)
		_sync_action_to_engine(act)

	return Result.ok()
#endregion


#region Internal Default Setup & Engine Sync
func _ensure_builtin_game_actions() -> void:
	# 1. 四向连续移动动作（标记 is_axis = true，豁免修饰键锁，支持边按 Shift 边移动）
	_setup_default_action(
		&"move_left",
		InputContextType.Context.GAMEPLAY,
		true,
		true,
		InputChord.from_event(InputChord.make_key_event(KEY_A)),
		InputChord.from_event(InputChord.make_key_event(KEY_LEFT)),
		InputChord.from_event(InputChord.make_joy_axis_event(JOY_AXIS_LEFT_X, -1.0)),
		InputChord.from_event(InputChord.make_joy_button_event(JOY_BUTTON_DPAD_LEFT))
	)
	_setup_default_action(
		&"move_right",
		InputContextType.Context.GAMEPLAY,
		true,
		true,
		InputChord.from_event(InputChord.make_key_event(KEY_D)),
		InputChord.from_event(InputChord.make_key_event(KEY_RIGHT)),
		InputChord.from_event(InputChord.make_joy_axis_event(JOY_AXIS_LEFT_X, 1.0)),
		InputChord.from_event(InputChord.make_joy_button_event(JOY_BUTTON_DPAD_RIGHT))
	)
	_setup_default_action(
		&"move_up",
		InputContextType.Context.GAMEPLAY,
		true,
		true,
		InputChord.from_event(InputChord.make_key_event(KEY_W)),
		InputChord.from_event(InputChord.make_key_event(KEY_UP)),
		InputChord.from_event(InputChord.make_joy_axis_event(JOY_AXIS_LEFT_Y, -1.0)),
		InputChord.from_event(InputChord.make_joy_button_event(JOY_BUTTON_DPAD_UP))
	)
	_setup_default_action(
		&"move_down",
		InputContextType.Context.GAMEPLAY,
		true,
		true,
		InputChord.from_event(InputChord.make_key_event(KEY_S)),
		InputChord.from_event(InputChord.make_key_event(KEY_DOWN)),
		InputChord.from_event(InputChord.make_joy_axis_event(JOY_AXIS_LEFT_Y, 1.0)),
		InputChord.from_event(InputChord.make_joy_button_event(JOY_BUTTON_DPAD_DOWN))
	)

	# 2. 战斗核心离散动作（包含单键与默认组合键范例）
	_setup_default_action(
		&"dash",
		InputContextType.Context.GAMEPLAY,
		true,
		false,
		InputChord.from_event(InputChord.make_key_event(KEY_SPACE)),
		InputChord.from_event(InputChord.make_mouse_button_event(MOUSE_BUTTON_RIGHT)),
		InputChord.from_event(InputChord.make_joy_button_event(JOY_BUTTON_A)),
		InputChord.from_event(InputChord.make_joy_button_event(JOY_BUTTON_RIGHT_SHOULDER))
	)
	_setup_default_action(
		&"attack",
		InputContextType.Context.GAMEPLAY,
		true,
		false,
		InputChord.from_event(InputChord.make_mouse_button_event(MOUSE_BUTTON_LEFT)),
		InputChord.from_event(InputChord.make_key_event(KEY_J)),
		InputChord.from_event(InputChord.make_joy_button_event(JOY_BUTTON_X)),
		InputChord.from_event(InputChord.make_joy_axis_event(JOY_AXIS_TRIGGER_RIGHT, 1.0))
	)
	_setup_default_action(
		&"skill_1",
		InputContextType.Context.GAMEPLAY,
		true,
		false,
		InputChord.from_event(InputChord.make_key_event(KEY_Q)),
		InputChord.empty(),
		InputChord.from_event(InputChord.make_joy_button_event(JOY_BUTTON_Y)),
		InputChord.empty()
	)
	_setup_default_action(
		&"skill_2",
		InputContextType.Context.GAMEPLAY,
		true,
		false,
		InputChord.from_event(InputChord.make_key_event(KEY_E)),
		InputChord.empty(),
		InputChord.from_event(InputChord.make_joy_button_event(JOY_BUTTON_B)),
		InputChord.empty()
	)
	# 觉醒大招：默认演示组合键（键盘 Shift + Q，手柄 LB + Y）
	_setup_default_action(
		&"ultimate",
		InputContextType.Context.GAMEPLAY,
		true,
		false,
		InputChord.from_chord([InputChord.make_key_event(KEY_SHIFT)], InputChord.make_key_event(KEY_Q)),
		InputChord.from_event(InputChord.make_key_event(KEY_R)),
		InputChord.from_chord(
			[InputChord.make_joy_button_event(JOY_BUTTON_LEFT_SHOULDER)],
			InputChord.make_joy_button_event(JOY_BUTTON_Y)
		),
		InputChord.empty()
	)
	_setup_default_action(
		&"interact",
		InputContextType.Context.GAMEPLAY,
		true,
		false,
		InputChord.from_event(InputChord.make_key_event(KEY_F)),
		InputChord.empty(),
		InputChord.from_event(InputChord.make_joy_button_event(JOY_BUTTON_A)),
		InputChord.empty()
	)
	_setup_default_action(
		&"pause",
		InputContextType.Context.SYSTEM,
		false,
		false,
		InputChord.from_event(InputChord.make_key_event(KEY_ESCAPE)),
		InputChord.empty(),
		InputChord.from_event(InputChord.make_joy_button_event(JOY_BUTTON_START)),
		InputChord.empty()
	)


func _setup_default_action(
	action: StringName,
	context: int,
	rebindable: bool,
	is_axis: bool,
	kb_primary: InputChord,
	kb_secondary: InputChord,
	joy_primary: InputChord,
	joy_secondary: InputChord
) -> void:
	_action_meta[action] = {
		"context": context,
		"rebindable": rebindable,
		"is_axis": is_axis,
	}
	if not InputMap.has_action(action):
		InputMap.add_action(action, _joy_deadzone)

	var def_slots := {
		"kb_0": kb_primary.duplicate_chord(),
		"kb_1": kb_secondary.duplicate_chord(),
		"joy_0": joy_primary.duplicate_chord(),
		"joy_1": joy_secondary.duplicate_chord(),
	}
	_default_bindings[action] = def_slots
	_active_bindings[action] = {
		"kb_0": kb_primary.duplicate_chord(),
		"kb_1": kb_secondary.duplicate_chord(),
		"joy_0": joy_primary.duplicate_chord(),
		"joy_1": joy_secondary.duplicate_chord(),
	}


## 扫描 project.godot 中用户额外声明的非 ui_* 内置 Action 并纳入双轨快照管理
func _snapshot_project_actions() -> void:
	for raw_act in InputMap.get_actions():
		var act := raw_act as StringName
		var s := String(act)
		if s.begins_with("ui_") or _default_bindings.has(act):
			continue
		var kb_list: Array[InputChord] = []
		var joy_list: Array[InputChord] = []
		for ev in InputMap.action_get_events(act):
			var c := InputChord.from_event(ev)
			if c.is_empty():
				continue
			if c.get_device_type() == InputDeviceType.Type.JOYPAD:
				if joy_list.size() < 2:
					joy_list.append(c)
			else:
				if kb_list.size() < 2:
					kb_list.append(c)
		_setup_default_action(
			act,
			InputContextType.Context.GAMEPLAY,
			true,
			false,
			kb_list[0] if kb_list.size() > 0 else InputChord.empty(),
			kb_list[1] if kb_list.size() > 1 else InputChord.empty(),
			joy_list[0] if joy_list.size() > 0 else InputChord.empty(),
			joy_list[1] if joy_list.size() > 1 else InputChord.empty()
		)


func _sync_all_to_engine() -> void:
	for k in _active_bindings.keys():
		_sync_action_to_engine(k as StringName)


## 将单个 Action 的当前槽位同步至 Godot InputMap（修改前强制释放按压态防止卡键）
func _sync_action_to_engine(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, _joy_deadzone)
	if Input.is_action_pressed(action):
		Input.action_release(action)
	InputMap.action_erase_events(action)
	InputMap.action_set_deadzone(action, _joy_deadzone)

	if not _active_bindings.has(action):
		return
	var slots: Dictionary = _active_bindings[action]
	for sk in ["kb_0", "kb_1", "joy_0", "joy_1"]:
		var chord: InputChord = slots.get(sk, null)
		if chord == null or chord.is_empty():
			continue
		# 手柄组合键由 InputSystem 复合管线直读硬件求值，不直接塞入原生 InputMap 以免单按触发
		if chord.get_device_type() == InputDeviceType.Type.JOYPAD and chord.is_chord():
			continue
		var godot_ev := chord.to_godot_input_event()
		if godot_ev != null:
			InputMap.action_add_event(action, godot_ev)


func _create_empty_slots() -> Dictionary:
	return {
		"kb_0": InputChord.empty(),
		"kb_1": InputChord.empty(),
		"joy_0": InputChord.empty(),
		"joy_1": InputChord.empty(),
	}


func _resolve_slot_keys(device_type: int) -> Array[String]:
	if device_type == InputDeviceType.Type.KEYBOARD_MOUSE:
		return ["kb_0", "kb_1"]
	if device_type == InputDeviceType.Type.JOYPAD:
		return ["joy_0", "joy_1"]
	return ["kb_0", "kb_1", "joy_0", "joy_1"]
#endregion
