class_name InputTest
extends BaseScene

## Input 模块可视化与自动化综合测试场景（继承 [BaseScene]，支持 F6 独立启动）。

#region Constants & State
const DISPLAY_ACTIONS: Array[StringName] = [
	&"move_up",
	&"move_down",
	&"move_left",
	&"move_right",
	&"dash",
	&"attack",
	&"skill_1",
	&"skill_2",
	&"ultimate",
	&"interact",
]

var _status_label: Label = null
var _device_label: Label = null
var _trigger_log_label: Label = null
var _test_summary_label: Label = null
var _live_hud_label: Label = null
var _avatar_dot: ColorRect = null
var _avatar_center: Vector2 = Vector2(180.0, 110.0)
var _slot_buttons: Dictionary = {}
var _action_flash_timers: Dictionary = {}
var _recent_triggers: Array[String] = []
#endregion


#region Scene & Engine Lifecycle


func _on_enter(_params: BaseParams = null) -> void:
	_build_test_ui()
	Bus.input_device_changed.connect(_on_device_or_binding_changed)
	Bus.input_bindings_changed.connect(_on_binding_changed)
	App.input.rebind_preview.connect(_on_rebind_preview)

	var pass_count := _run_automated_suite()
	_refresh_all_ui()
	App.logger.info("InputTest", "Automated verification suite completed: %d/6 passed." % pass_count)


func _on_exit() -> void:
	if Bus.input_device_changed.is_connected(_on_device_or_binding_changed):
		Bus.input_device_changed.disconnect(_on_device_or_binding_changed)
	if Bus.input_bindings_changed.is_connected(_on_binding_changed):
		Bus.input_bindings_changed.disconnect(_on_binding_changed)
	if App.input != null and App.input.rebind_preview.is_connected(_on_rebind_preview):
		App.input.rebind_preview.disconnect(_on_rebind_preview)


func _process(delta: float) -> void:
	if App.input == null or _avatar_dot == null:
		return

	# 1. 验证连续移动向量（按住 Shift 放组合技时移动不断触）
	var dir := App.input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	_avatar_center += dir * 200.0 * delta
	_avatar_center.x = clampf(_avatar_center.x, 20.0, 340.0)
	_avatar_center.y = clampf(_avatar_center.y, 20.0, 190.0)
	_avatar_dot.position = _avatar_center - _avatar_dot.size * 0.5

	# 2. 检验当前鼠标是否正点击在 UI 按钮上（避免点击左侧改键按钮时误记为右侧沙盒 LMB 攻击）
	var vp := get_viewport()
	var hovered_ctrl: Control = vp.gui_get_hovered_control() if vp != null else null
	var is_clicking_ui_btn := (hovered_ctrl is BaseButton) and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

	# 3. 实时监测全部 10 个展示动作的按下边沿、持续按压态与左侧行高亮反馈
	var held_list: PackedStringArray = []
	for act in DISPLAY_ACTIONS:
		var act_str := String(act)
		var flash_rem: float = maxf(float(_action_flash_timers.get(act, 0.0)) - delta, 0.0)

		if App.input.is_action_just_pressed(act):
			if not (act == &"attack" and is_clicking_ui_btn):
				flash_rem = 0.22
				var glyph := App.input.get_action_glyph(act)
				_append_trigger_log("Triggered [%s] via (%s)" % [act_str, glyph.display_text])

		_action_flash_timers[act] = flash_rem
		var is_held := App.input.is_action_pressed(act) and not (act == &"attack" and is_clicking_ui_btn)
		if is_held:
			held_list.append(act_str)

		var is_highlighted := is_held or flash_rem > 0.0
		var name_lbl: Label = _slot_buttons.get("%s_name" % act_str, null)
		if name_lbl != null:
			name_lbl.text = ("● %s" % act_str) if is_highlighted else act_str
			name_lbl.add_theme_color_override(
				"font_color",
				Color(0.30, 1.0, 0.55) if is_highlighted else Color(0.92, 0.94, 0.98)
			)
		var prompt_lbl: Label = _slot_buttons.get("%s_prompt" % act_str, null)
		if prompt_lbl != null:
			prompt_lbl.add_theme_color_override(
				"font_color",
				Color(0.30, 1.0, 0.55) if is_highlighted else Color(1.0, 0.88, 0.40)
			)

	if _live_hud_label != null:
		var held_str := ", ".join(held_list) if not held_list.is_empty() else "无"
		_live_hud_label.text = "移动向量: (%.2f, %.2f) | 当前按住: %s" % [dir.x, dir.y, held_str]
#endregion


#region Automated Contract Verification Suite
func _run_automated_suite() -> int:
	var passed := 0
	var logs: PackedStringArray = []

	# Case 1: 组合键规范化签名一致性 (Ctrl+Shift+Q == Shift+Ctrl+Q)
	var c1 := InputChord.from_chord(
		[InputChord.make_key_event(KEY_SHIFT), InputChord.make_key_event(KEY_CTRL)],
		InputChord.make_key_event(KEY_Q)
	)
	var c2 := InputChord.from_chord(
		[InputChord.make_key_event(KEY_CTRL), InputChord.make_key_event(KEY_SHIFT)],
		InputChord.make_key_event(KEY_Q)
	)
	if c1.get_signature() == c2.get_signature() and c1.get_order() == 2:
		passed += 1
		logs.append("✅ [1/6] InputChord 组合键签名归一化通过 (%s)" % c1.get_signature())
	else:
		logs.append("❌ [1/6] InputChord 签名不一致")

	# Case 2: 键鼠与手柄双轨隔离（修改键盘 skill_1 不影响手柄 skill_1）
	var orig_joy := App.input.get_action_chord(&"skill_1", InputDeviceType.Type.JOYPAD, InputBindingSlot.Slot.PRIMARY)
	var bind_res := App.input.bind_event(&"skill_1", InputChord.make_key_event(KEY_K), InputBindingSlot.Slot.PRIMARY)
	var after_joy := App.input.get_action_chord(&"skill_1", InputDeviceType.Type.JOYPAD, InputBindingSlot.Slot.PRIMARY)
	if bind_res.is_ok() and orig_joy.get_signature() == after_joy.get_signature():
		passed += 1
		logs.append("✅ [2/6] 键鼠与手柄双轨物理隔离通过")
	else:
		logs.append("❌ [2/6] 双轨隔离校验失败")

	# Case 3: 同作用域冲突互换 (SWAP) 与冲突拒绝 (REJECT)
	# 当前 skill_1 键盘主键为 K，skill_2 键盘主键为 E；将 skill_2 绑为 K 应自动把 skill_1 换为 E
	var swap_res := App.input.bind_event(
		&"skill_2",
		InputChord.make_key_event(KEY_K),
		InputBindingSlot.Slot.PRIMARY,
		InputConflictPolicy.Policy.SWAP
	)
	var s1_after := App.input.get_action_chord(&"skill_1", InputDeviceType.Type.KEYBOARD_MOUSE, InputBindingSlot.Slot.PRIMARY)
	var s2_after := App.input.get_action_chord(&"skill_2", InputDeviceType.Type.KEYBOARD_MOUSE, InputBindingSlot.Slot.PRIMARY)
	var reject_res := App.input.bind_event(
		&"skill_1",
		InputChord.make_key_event(KEY_K),
		InputBindingSlot.Slot.PRIMARY,
		InputConflictPolicy.Policy.REJECT
	)
	if swap_res.is_ok() and s1_after.get_signature() == "KB:KEY_%d" % int(KEY_E) and s2_after.get_signature() == "KB:KEY_%d" % int(KEY_K) and reject_res.is_err() and reject_res.error_code() == InputError.BINDING_CONFLICT:
		passed += 1
		logs.append("✅ [3/6] SWAP 无感互换与 REJECT 冲突拦截通过")
	else:
		logs.append("❌ [3/6] 冲突裁决策略校验失败")

	# Case 4: 增量补丁序列化 (Delta Serialization) 与恢复
	var exported := App.input.export_bindings()
	var deltas: Dictionary = exported.get("deltas", {})
	App.input.reset_to_default()
	var clean_export := App.input.export_bindings()
	var import_res := App.input.import_bindings(exported)
	var restored_s2 := App.input.get_action_chord(&"skill_2", InputDeviceType.Type.KEYBOARD_MOUSE, InputBindingSlot.Slot.PRIMARY)
	App.input.reset_to_default()
	if deltas.has("skill_1") and deltas.has("skill_2") and (clean_export.get("deltas", {}) as Dictionary).is_empty() and import_res.is_ok() and restored_s2.get_signature() == "KB:KEY_%d" % int(KEY_K):
		passed += 1
		logs.append("✅ [4/6] Baseline+Delta 增量序列化与自愈导入通过")
	else:
		logs.append("❌ [4/6] 增量序列化校验失败")

	# Case 5: 四大设备品牌图标语义转译 (Keyboard / Xbox / PlayStation / Switch)
	App.input.simulate_device(InputDeviceType.Type.KEYBOARD_MOUSE)
	var kb_ult := App.input.get_action_glyph(&"ultimate").display_text
	App.input.simulate_device(InputDeviceType.Type.JOYPAD, InputDeviceType.JoyBrand.XBOX)
	var xbox_ult := App.input.get_action_glyph(&"ultimate").display_text
	App.input.simulate_device(InputDeviceType.Type.JOYPAD, InputDeviceType.JoyBrand.PLAYSTATION)
	var ps_ult := App.input.get_action_glyph(&"ultimate").display_text
	App.input.simulate_device(InputDeviceType.Type.JOYPAD, InputDeviceType.JoyBrand.NINTENDO)
	var ns_ult := App.input.get_action_glyph(&"ultimate").display_text
	App.input.simulate_device(InputDeviceType.Type.KEYBOARD_MOUSE)
	if kb_ult == "Shift + Q" and xbox_ult == "LB + Y" and ps_ult == "L1 + △" and ns_ult == "L + X":
		passed += 1
		logs.append("✅ [5/6] 多设备组合键文案转译通过 (KB:%s | Xbox:%s | PS:%s | NS:%s)" % [kb_ult, xbox_ult, ps_ult, ns_ult])
	else:
		logs.append("❌ [5/6] 文案转译异常: %s / %s / %s / %s" % [kb_ult, xbox_ult, ps_ult, ns_ult])

	# Case 6: InputContextType 上下文栈门控
	App.input.push_context(InputContextType.Context.UI)
	var active_ui := App.input.get_active_context() == InputContextType.Context.UI
	App.input.pop_context(InputContextType.Context.UI)
	var active_gp := App.input.get_active_context() == InputContextType.Context.GAMEPLAY
	if active_ui and active_gp:
		passed += 1
		logs.append("✅ [6/6] InputContextType 上下文压栈与出栈隔离通过")
	else:
		logs.append("❌ [6/6] 上下文栈状态异常")

	if _test_summary_label != null:
		_test_summary_label.text = "\n".join(logs)
	return passed
#endregion


#region Visual Dashboard Construction
func _build_test_ui() -> void:
	var root_ui := get_node_or_null("UI") as Control
	if root_ui == null:
		return

	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.10, 0.13, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ui.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	root_ui.add_child(margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 14)
	margin.add_child(main_vbox)

	# 顶部标题与设备模拟栏
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 12)
	main_vbox.add_child(top_bar)

	var title := Label.new()
	title.text = "🎮 App.input 双轨映射 & 组合键验证中心"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(title)

	_device_label = Label.new()
	_device_label.add_theme_font_size_override("font_size", 16)
	top_bar.add_child(_device_label)

	for preset in [
		{"label": "模拟键鼠", "dev": InputDeviceType.Type.KEYBOARD_MOUSE, "brand": InputDeviceType.JoyBrand.XBOX},
		{"label": "模拟 Xbox", "dev": InputDeviceType.Type.JOYPAD, "brand": InputDeviceType.JoyBrand.XBOX},
		{"label": "模拟 PS5", "dev": InputDeviceType.Type.JOYPAD, "brand": InputDeviceType.JoyBrand.PLAYSTATION},
		{"label": "模拟 Switch", "dev": InputDeviceType.Type.JOYPAD, "brand": InputDeviceType.JoyBrand.NINTENDO},
	]:
		var btn := Button.new()
		btn.text = preset["label"]
		btn.focus_mode = Control.FOCUS_NONE
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		var d: int = preset["dev"]
		var b: int = preset["brand"]
		btn.pressed.connect(func() -> void: App.input.simulate_device(d, b))
		top_bar.add_child(btn)

	var reset_btn := Button.new()
	reset_btn.text = "恢复出厂默认"
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	reset_btn.pressed.connect(func() -> void:
		App.input.reset_to_default()
		_status_label.text = "已恢复全部出厂默认键位。"
	)
	top_bar.add_child(reset_btn)

	# 中部左右分栏：左侧键位表，右侧实时测试沙盒与自动化报告
	var content_hbox := HBoxContainer.new()
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_theme_constant_override("separation", 20)
	main_vbox.add_child(content_hbox)

	# 左侧：双轨双槽改键矩阵
	var left_panel := PanelContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 1.35
	content_hbox.add_child(left_panel)

	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 8)
	left_panel.add_child(left_vbox)

	_status_label = Label.new()
	_status_label.text = "点击任意槽位按钮开始录制（支持单键、按住 Shift/Ctrl/Alt + 主键组合、或按住手柄 LB/LT + 主键组合，按 ESC 取消）"
	_status_label.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	left_vbox.add_child(_status_label)

	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	left_vbox.add_child(grid)

	for header_text in ["动作 Action", "当前设备提示", "键盘主键", "键盘副键", "手柄主键", "手柄副键"]:
		var h_lbl := Label.new()
		h_lbl.text = header_text
		h_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
		grid.add_child(h_lbl)

	for act in DISPLAY_ACTIONS:
		var name_lbl := Label.new()
		name_lbl.text = String(act)
		name_lbl.custom_minimum_size = Vector2(110, 0)
		grid.add_child(name_lbl)
		_slot_buttons["%s_name" % String(act)] = name_lbl

		var active_prompt_lbl := Label.new()
		active_prompt_lbl.custom_minimum_size = Vector2(120, 0)
		active_prompt_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.4))
		grid.add_child(active_prompt_lbl)
		_slot_buttons["%s_prompt" % String(act)] = active_prompt_lbl

		for slot_cfg in [
			{"dev": InputDeviceType.Type.KEYBOARD_MOUSE, "slot": InputBindingSlot.Slot.PRIMARY, "tag": "kb_0"},
			{"dev": InputDeviceType.Type.KEYBOARD_MOUSE, "slot": InputBindingSlot.Slot.SECONDARY, "tag": "kb_1"},
			{"dev": InputDeviceType.Type.JOYPAD, "slot": InputBindingSlot.Slot.PRIMARY, "tag": "joy_0"},
			{"dev": InputDeviceType.Type.JOYPAD, "slot": InputBindingSlot.Slot.SECONDARY, "tag": "joy_1"},
		]:
			var slot_btn := Button.new()
			slot_btn.custom_minimum_size = Vector2(125, 32)
			slot_btn.focus_mode = Control.FOCUS_NONE
			slot_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
			var dev_val: int = slot_cfg["dev"]
			var slot_val: int = slot_cfg["slot"]
			var btn_key := "%s_%s" % [String(act), slot_cfg["tag"]]
			slot_btn.pressed.connect(_on_slot_rebind_clicked.bind(act, dev_val, slot_val, slot_btn))
			grid.add_child(slot_btn)
			_slot_buttons[btn_key] = slot_btn

	# 右侧：自动化自检结果 + 实时移动与组合技沙盒
	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 12)
	content_hbox.add_child(right_vbox)

	var suite_title := Label.new()
	suite_title.text = "📋 自动化契约自检报告 (6 项核心能力)"
	suite_title.add_theme_font_size_override("font_size", 16)
	right_vbox.add_child(suite_title)

	_test_summary_label = Label.new()
	_test_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_vbox.add_child(_test_summary_label)

	var sandbox_title := Label.new()
	sandbox_title.text = "🕹️ 实时移动与组合键防污染沙盒 (按 WASD 移动 + Shift+Q 放觉醒)"
	sandbox_title.add_theme_font_size_override("font_size", 16)
	right_vbox.add_child(sandbox_title)

	_live_hud_label = Label.new()
	_live_hud_label.text = "移动向量: (0.00, 0.00) | 当前按住: 无"
	_live_hud_label.add_theme_color_override("font_color", Color(0.55, 0.92, 0.72))
	right_vbox.add_child(_live_hud_label)

	var arena := ColorRect.new()
	arena.custom_minimum_size = Vector2(360, 210)
	arena.color = Color(0.14, 0.16, 0.22, 1.0)
	right_vbox.add_child(arena)

	_avatar_dot = ColorRect.new()
	_avatar_dot.size = Vector2(24, 24)
	_avatar_dot.color = Color(0.3, 0.95, 0.55)
	_avatar_dot.position = _avatar_center - _avatar_dot.size * 0.5
	arena.add_child(_avatar_dot)

	_trigger_log_label = Label.new()
	_trigger_log_label.text = "等待动作触发...（试着按 WASD/方向键移动，按 Q 触发 skill_1，按 Shift+Q 触发 ultimate）"
	_trigger_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_vbox.add_child(_trigger_log_label)


func _on_slot_rebind_clicked(action: StringName, device_type: int, slot: int, btn: Button) -> void:
	if App.input.is_rebinding():
		return
	btn.text = "等待输入..."
	_status_label.text = "正在录制 [%s] (%s)... 按下目标键或组合键，按 ESC 取消" % [
		String(action),
		InputDeviceType.type_to_string(device_type),
	]
	var res := await App.input.rebind_interactive_async(action, device_type, slot)
	if res.is_ok():
		var glyph := res.value as InputGlyphInfo
		_status_label.text = "绑定成功：[%s] -> %s" % [String(action), glyph.display_text]
	else:
		_status_label.text = "录制未生效：[%s] %s" % [res.error_code(), res.error_message()]
	_refresh_all_ui()


func _on_rebind_preview(preview_glyph: InputGlyphInfo) -> void:
	if _status_label != null:
		_status_label.text = "检测到修饰键：%s （继续按下主键完成组合键，或直接松开绑定为独立单键）" % preview_glyph.display_text


func _on_device_or_binding_changed(_a: Variant = null, _b: Variant = null) -> void:
	_refresh_all_ui()


func _on_binding_changed(_action: StringName) -> void:
	_refresh_all_ui()


func _refresh_all_ui() -> void:
	if App.input == null or _device_label == null:
		return
	_device_label.text = "当前设备: %s (%s)" % [
		InputDeviceType.type_to_string(App.input.current_device),
		InputDeviceType.brand_to_string(App.input.current_joy_brand),
	]
	for act in DISPLAY_ACTIONS:
		var prompt_lbl: Label = _slot_buttons.get("%s_prompt" % String(act), null)
		if prompt_lbl != null:
			prompt_lbl.text = "[%s]" % App.input.get_action_glyph(act).display_text

		for slot_cfg in [
			{"dev": InputDeviceType.Type.KEYBOARD_MOUSE, "slot": InputBindingSlot.Slot.PRIMARY, "tag": "kb_0"},
			{"dev": InputDeviceType.Type.KEYBOARD_MOUSE, "slot": InputBindingSlot.Slot.SECONDARY, "tag": "kb_1"},
			{"dev": InputDeviceType.Type.JOYPAD, "slot": InputBindingSlot.Slot.PRIMARY, "tag": "joy_0"},
			{"dev": InputDeviceType.Type.JOYPAD, "slot": InputBindingSlot.Slot.SECONDARY, "tag": "joy_1"},
		]:
			var btn_key := "%s_%s" % [String(act), slot_cfg["tag"]]
			var btn: Button = _slot_buttons.get(btn_key, null)
			if btn != null:
				var chord := App.input.get_action_chord(act, slot_cfg["dev"], slot_cfg["slot"])
				var glyph := InputGlyphInfo.from_chord(chord, act, slot_cfg["dev"], App.input.current_joy_brand)
				btn.text = glyph.display_text


func _append_trigger_log(line: String) -> void:
	_recent_triggers.push_front("%s  %s" % [TimeUtils.now_string(), line])
	if _recent_triggers.size() > 6:
		_recent_triggers.resize(6)
	if _trigger_log_label != null:
		_trigger_log_label.text = "\n".join(_recent_triggers)
#endregion
