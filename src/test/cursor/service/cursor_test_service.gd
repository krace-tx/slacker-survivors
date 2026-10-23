class_name CursorTestService
extends RefCounted

## 自定义鼠标教学与契约验证领域服务（位于 src/test/cursor/service/，遵循 MSVP 的 `Service` 规范）。[br]
##
## [b]核心教学职责：[/b][br]
## 1. [b]演示如何从零构建自定义鼠标主题（[method build_crimson_tactical_theme]）[/b]：
##    展示如何实例化 [CursorThemeConfig]、配置各语义状态的 [CursorStyleEntry]（常态贴图、按压态贴图、热点坐标、软件光标偏好）及拖尾/点击粒子配色；[br]
## 2. [b]演示如何切换与卸载鼠标主题（[method apply_theme_preset]）[/b]：
##    支持在「系统原生鼠标 (`null`)」、「赛博青白主题」与「绯红战术自定义主题」间一键切换；[br]
## 3. [b]演示五层交互优先级漏斗绑定（L1 ~ L5）[/b]：
##    封装控件绑定（`bind_control`）、世界交互物绑定（`bind_hover_node`）、强锁覆盖栈（`push_override` / `pop_override`）与射击脉冲（`pulse`）；[br]
## 4. [b]内置 6 项自动化契约验证套件（[method run_verification_suite]）[/b]。


#region 常量与依赖

const _LOG_TAG: String = "CursorTest"
const _WAIT_OVERRIDE_TOKEN: StringName = &"playground_wait_lock"

var _state: CursorTestState = null

#endregion


#region 生命周期

func _init(state: CursorTestState) -> void:
	_state = state


func get_state() -> CursorTestState:
	return _state


## 退出测试场景时清理所有覆盖栈并恢复系统原生默认鼠标，防止污染其它测试场景。
func cleanup_on_exit() -> void:
	if App == null or App.cursor == null:
		return
	App.cursor.clear_overrides()
	App.cursor.set_gameplay_cursor(CursorShapeType.Shape.DEFAULT)
	App.cursor.set_software_cursor_preferred(false)
	App.cursor.set_confined(false)
	App.cursor.set_theme(null)

#endregion


#region 教学模块 1：如何构建与切换自定义鼠标主题 (Custom Theme Construction & Switching)

## 切换鼠标主题预设档位：[br]
## - `OS_NATIVE (0)`：调用 `App.cursor.set_theme(null)` 恢复操作系统原生默认鼠标；[br]
## - `CYBER_PROCEDURAL (1)`：应用框架内置的 `CursorThemeConfig.create_procedural_default()`；[br]
## - `CRIMSON_TACTICAL (2)`：应用业务侧自定义组装的绯红战术主题 [method build_crimson_tactical_theme]。
func apply_theme_preset(preset: int) -> void:
	if App == null or App.cursor == null:
		return

	_state.theme_preset = preset
	match preset:
		CursorTestState.ThemePreset.OS_NATIVE:
			# 传入 null 即可卸载自定义鼠标主题，恢复系统原生光标并关闭拖尾/点击粒子
			App.cursor.set_theme(null)
			_state.append_log("已切换为 [b][color=gray]系统原生鼠标 (set_theme(null))[/color][/b]：自定义贴图与粒子已卸载")

		CursorTestState.ThemePreset.CYBER_PROCEDURAL:
			var cyber_theme := CursorThemeConfig.create_procedural_default()
			App.cursor.set_theme(cyber_theme)
			_state.append_log("已应用 [b][color=cyan]赛博青白主题[/color][/b]（启用星尘拖尾 + 琥珀点击波）")

		CursorTestState.ThemePreset.CRIMSON_TACTICAL:
			var tactical_theme := build_crimson_tactical_theme()
			App.cursor.set_theme(tactical_theme)
			_state.append_log("已应用 [b][color=coral]绯红战术自定义主题[/color][/b]（演示自定义构建 CursorThemeConfig）")

	_state.sync_from_cursor_system()


## 【核心教学示例】如何用代码（或在编辑器 Inspector 中配置 `.tres`）构建一套自定义鼠标主题。[br]
## 在正式项目中，只需将下方程序化生成的 `Texture2D` 替换为 `preload("res://src/assets/textures/.../ico_xxx.png")` 即可。
static func build_crimson_tactical_theme() -> CursorThemeConfig:
	# 第 1 步：以基础模板起步（或新建 CursorThemeConfig.new()）
	var theme := CursorThemeConfig.create_procedural_default()

	# 第 2 步：配置 DPI 高分屏自适应缩放与粒子特效参数
	theme.enable_dpi_scaling = true
	theme.prefer_software_cursor = false
	theme.enable_trail_vfx = true
	theme.enable_click_vfx = true
	theme.trail_color = Color(1.0, 0.38, 0.32, 0.88) # 绯红尾迹
	theme.click_color = Color(1.0, 0.65, 0.25, 0.95) # 烈焰橙点击扩散波

	# 第 3 步：覆盖核心语义形状的常态贴图、按压态贴图与热点坐标 (Hotspot)
	# 示例 A：替换 DEFAULT 默认箭头为暗金绯红双色箭头（热点在左上角尖端 (3, 3)）
	var default_entry := theme.get_style(CursorShapeType.Shape.DEFAULT)
	if default_entry != null:
		default_entry.normal_texture = CursorThemeConfig._build_arrow_tex(
			Color(1.0, 0.92, 0.82), Color(1.0, 0.32, 0.28), 1.0
		)
		default_entry.pressed_texture = CursorThemeConfig._build_arrow_tex(
			Color(1.0, 0.72, 0.45), Color(0.90, 0.18, 0.18), 0.86
		)
		default_entry.hotspot = Vector2(3.0, 3.0)

	# 示例 B：替换 POINTER 按钮悬停手型为绯红亮金手型（热点在食指指尖 (10, 4)）
	var pointer_entry := theme.get_style(CursorShapeType.Shape.POINTER)
	if pointer_entry != null:
		pointer_entry.normal_texture = CursorThemeConfig._build_pointer_tex(
			Color(1.0, 0.82, 0.55), Color(1.0, 0.30, 0.25), false
		)
		pointer_entry.pressed_texture = CursorThemeConfig._build_pointer_tex(
			Color(1.0, 0.55, 0.30), Color(0.85, 0.15, 0.15), true
		)
		pointer_entry.hotspot = Vector2(10.0, 4.0)

	return theme

#endregion


#region 教学模块 2：五层交互优先级绑定与动态特效控制 (5-Layer Bindings & Controls)

## 为指定 UI 控件声明式绑定悬停光标（L4 层：如可拖拽卡牌绑定 `GRAB`，按住左键自动变为 `GRABBED`）。
func bind_ui_control_cursor(control: Control, shape: int) -> void:
	if App != null and App.cursor != null and control != null:
		App.cursor.bind_control(control, shape)


## 切换 L2 局内基准光标（`DEFAULT` 默认箭头 <-> `CROSSHAIR` 战术准星）。
func toggle_gameplay_cursor() -> void:
	if App == null or App.cursor == null:
		return
	var next_shape: int = (
		CursorShapeType.Shape.CROSSHAIR
		if App.cursor.get_gameplay_cursor() == CursorShapeType.Shape.DEFAULT
		else CursorShapeType.Shape.DEFAULT
	)
	App.cursor.set_gameplay_cursor(next_shape)
	var shape_name := String(CursorShapeType.to_string_name(next_shape))
	_state.append_log("切换 [L2 局内基准光标] -> [b][color=cyan]%s[/color][/b]" % shape_name)
	_state.sync_from_cursor_system()


## 切换 L5 最高优先级强锁覆盖（`WAIT` 动态旋转等待环，开启期间屏蔽一切下层按钮悬停变态）。
func toggle_wait_override() -> void:
	if App == null or App.cursor == null:
		return
	if not _state.is_wait_override_active:
		App.cursor.push_override(_WAIT_OVERRIDE_TOKEN, CursorShapeType.Shape.WAIT)
		_state.is_wait_override_active = true
		_state.append_log("压入 [L5 强锁覆盖栈] -> [b][color=yellow]WAIT (旋转沙漏)[/color][/b]（屏蔽沿途所有按钮悬停）")
	else:
		App.cursor.pop_override(_WAIT_OVERRIDE_TOKEN)
		_state.is_wait_override_active = false
		_state.append_log("弹出 [L5 强锁覆盖栈] -> 恢复下层交互光标")
	_state.sync_from_cursor_system()


## 切换硬件光标 / 画布软件光标偏好模式。
func toggle_software_cursor_mode() -> void:
	if App == null or App.cursor == null:
		return
	_state.software_preferred = not _state.software_preferred
	App.cursor.set_software_cursor_preferred(_state.software_preferred)
	_state.append_log(
		"切换渲染驱动 -> [b]%s[/b]" % ("画布软件动态光标 (支持脉冲缩放)" if _state.software_preferred else "OS 硬件光标优先 (0帧延迟)")
	)
	_state.sync_from_cursor_system()


## 触发一次射击/释放技能准星扩散回弹脉冲（`App.cursor.pulse`）。
func trigger_recoil_pulse() -> void:
	if App == null or App.cursor == null:
		return
	# 若当前未开启软件光标模式，自动开启以便观察平滑缩放脉冲
	if not App.cursor.is_using_software_cursor():
		_state.software_preferred = true
		App.cursor.set_software_cursor_preferred(true)
	App.cursor.pulse(1.50, 0.18)
	_state.append_log("触发准星后坐力脉冲 [b]App.cursor.pulse(1.50, 0.18)[/b]")
	_state.sync_from_cursor_system()


## 切换移动星尘拖尾粒子开关。
func toggle_trail_vfx() -> void:
	if App == null or App.cursor == null:
		return
	var next_trail: bool = not App.cursor.is_trail_vfx_enabled()
	App.cursor.set_vfx_enabled(next_trail, App.cursor.is_click_vfx_enabled())
	_state.append_log("移动星尘拖尾特效 -> [b]%s[/b]" % ("开启" if next_trail else "关闭"))
	_state.sync_from_cursor_system()


## 切换左键点击爆裂波纹特效开关。
func toggle_click_vfx() -> void:
	if App == null or App.cursor == null:
		return
	var next_click: bool = not App.cursor.is_click_vfx_enabled()
	App.cursor.set_vfx_enabled(App.cursor.is_trail_vfx_enabled(), next_click)
	_state.append_log("点击水波纹爆裂特效 -> [b]%s[/b]" % ("开启" if next_click else "关闭"))
	_state.sync_from_cursor_system()


## 切换双显示器战斗期窗口锁边（`MOUSE_MODE_CONFINED`）。
func toggle_confinement() -> void:
	if App == null or App.cursor == null:
		return
	var next_confined: bool = not App.cursor.is_confined()
	App.cursor.set_confined(next_confined)
	_state.append_log("双屏窗口边界锁边 (set_confined) -> [b]%s[/b]" % ("开启" if next_confined else "关闭"))
	_state.sync_from_cursor_system()

#endregion


#region 教学模块 3：6 项自动化契约自检套件 (Automated Verification Suite)

## 运行全部 6 项自动化契约验证用例（验证完成后恢复当前选中的主题档位）。
func run_verification_suite(host_node: Node) -> bool:
	_state.clear_logs()
	_state.append_log("[b][color=cyan]=== 开始执行 App.cursor 自动化契约验证 (共 6 项) ===[/color][/b]")

	var saved_preset: int = _state.theme_preset
	# 确保在验证期间挂载完整主题以校验全部 11 种语义形状
	App.cursor.set_theme(CursorThemeConfig.create_procedural_default())

	_verify_case_1_theme_and_11_shapes()
	_verify_case_2_priority_funnel_and_press_morph(host_node)
	_verify_case_3_world_hover_auto_cleanup(host_node)
	_verify_case_4_software_cursor_and_pulse()
	_verify_case_5_vfx_trail_and_ring_buffer_pool()
	_verify_case_6_joypad_hide_and_confinement()

	# 恢复用户当前选中的主题档位
	apply_theme_preset(saved_preset)
	if _state.is_wait_override_active:
		App.cursor.push_override(_WAIT_OVERRIDE_TOKEN, CursorShapeType.Shape.WAIT)

	var summary := "=== 验证完成：%d 项通过，%d 项失败 ===" % [_state.passed_cases, _state.failed_cases]
	if _state.failed_cases == 0:
		_state.append_log("[b][color=green]%s[/color][/b]" % summary)
		if App.logger != null:
			App.logger.info(_LOG_TAG, summary)
	else:
		_state.append_log("[b][color=red]%s[/color][/b]" % summary)
		if App.logger != null:
			App.logger.error(_LOG_TAG, summary)

	_state.sync_from_cursor_system()
	return _state.failed_cases == 0


func _verify_case_1_theme_and_11_shapes() -> void:
	var theme := App.cursor.get_theme()
	var has_theme := theme != null
	var all_entries_valid: bool = has_theme and theme.styles.size() == CursorShapeType.ALL_SHAPES.size()
	if has_theme:
		for shape: int in CursorShapeType.ALL_SHAPES:
			var entry: CursorStyleEntry = theme.get_style(shape)
			if entry == null or entry.normal_texture == null:
				all_entries_valid = false
				break
	_record_assertion(
		all_entries_valid,
		"CASE 1: CursorThemeConfig 完整包含全部 11 种语义光标形状与常态/按压态贴图"
	)


func _verify_case_2_priority_funnel_and_press_morph(host_node: Node) -> void:
	App.cursor.clear_overrides()
	var resolver := CursorStateResolver.new()
	resolver.set_gameplay_cursor(CursorShapeType.Shape.CROSSHAIR)

	var eval_l1 := resolver.evaluate(null, InputContextType.Context.UI, false)
	var ok_l1 := int(eval_l1["shape"]) == CursorShapeType.Shape.DEFAULT

	var eval_l2 := resolver.evaluate(null, InputContextType.Context.GAMEPLAY, false)
	var ok_l2 := int(eval_l2["shape"]) == CursorShapeType.Shape.CROSSHAIR

	var mock_entity := Node2D.new()
	host_node.add_child(mock_entity)
	resolver.set_world_hover(mock_entity.get_instance_id(), CursorShapeType.Shape.INTERACT)
	var eval_l3 := resolver.evaluate(null, InputContextType.Context.GAMEPLAY, false)
	var ok_l3 := int(eval_l3["shape"]) == CursorShapeType.Shape.INTERACT

	var eval_l3_ui := resolver.evaluate(null, InputContextType.Context.UI, false)
	var ok_l3_suppressed := int(eval_l3_ui["shape"]) == CursorShapeType.Shape.DEFAULT

	resolver.push_override(&"test_grab", CursorShapeType.Shape.GRAB)
	var eval_l5_unpressed := resolver.evaluate(null, InputContextType.Context.GAMEPLAY, false)
	var eval_l5_pressed := resolver.evaluate(null, InputContextType.Context.GAMEPLAY, true)
	var ok_l5 := (
		int(eval_l5_unpressed["shape"]) == CursorShapeType.Shape.GRAB
		and int(eval_l5_pressed["shape"]) == CursorShapeType.Shape.GRABBED
	)
	resolver.pop_override(&"test_grab")
	resolver.clear_world_hover(mock_entity.get_instance_id())
	mock_entity.free()

	_record_assertion(
		ok_l1 and ok_l2 and ok_l3 and ok_l3_suppressed and ok_l5,
		"CASE 2: 五层优先级漏斗 (L5 > L4 > L3 > L2 > L1) 与 GRAB -> GRABBED 按压形变裁决正确"
	)


func _verify_case_3_world_hover_auto_cleanup(host_node: Node) -> void:
	App.cursor.set_gameplay_cursor(CursorShapeType.Shape.CROSSHAIR)
	var temp_node := Area2D.new()
	host_node.add_child(temp_node)
	App.cursor.bind_hover_node(temp_node, CursorShapeType.Shape.ATTACK, 10)
	temp_node.mouse_entered.emit()
	var count_before := int(App.cursor.get_diagnostics().get("world_hover_count", 0))

	temp_node.free()
	var count_after := int(App.cursor.get_diagnostics().get("world_hover_count", -1))
	App.cursor.set_gameplay_cursor(CursorShapeType.Shape.DEFAULT)

	_record_assertion(
		count_before == 1 and count_after == 0,
		"CASE 3: 世界交互节点 (bind_hover_node) 销毁退树时自动解绑悬停状态，零幽灵残留"
	)


func _verify_case_4_software_cursor_and_pulse() -> void:
	App.cursor.set_software_cursor_preferred(true)
	var soft_on := App.cursor.is_using_software_cursor()
	App.cursor.push_override(&"test_recoil", CursorShapeType.Shape.CROSSHAIR)
	App.cursor.pulse(1.45, 0.15)
	var active_ok := App.cursor.get_current_shape() == CursorShapeType.Shape.CROSSHAIR
	App.cursor.pop_override(&"test_recoil")
	App.cursor.set_software_cursor_preferred(_state.software_preferred)
	var restored_ok := App.cursor.get_current_shape() == CursorShapeType.Shape.DEFAULT

	_record_assertion(
		soft_on and active_ok and restored_ok,
		"CASE 4: 软件画布光标切换、强锁覆盖与射击后坐力脉冲 pulse(1.45, 0.15) 正常生效"
	)


func _verify_case_5_vfx_trail_and_ring_buffer_pool() -> void:
	App.cursor.set_vfx_enabled(false, false)
	var both_off := not App.cursor.is_trail_vfx_enabled() and not App.cursor.is_click_vfx_enabled()
	App.cursor.set_vfx_enabled(true, true)
	var both_on := App.cursor.is_trail_vfx_enabled() and App.cursor.is_click_vfx_enabled()

	for i in range(10):
		App.cursor.spawn_click_burst(Vector2(220.0 + float(i * 18), 220.0))
	var bursts := int(App.cursor.get_diagnostics().get("total_click_bursts", 0))

	_record_assertion(
		both_off and both_on and bursts >= 10,
		"CASE 5: 星尘拖尾开关与 8 槽位点击波环形对象池（连续触发 10 次溢出复用）验证通过"
	)


func _verify_case_6_joypad_hide_and_confinement() -> void:
	App.input.simulate_device(InputDeviceType.Type.JOYPAD, InputDeviceType.JoyBrand.XBOX)
	var hidden_on_joypad := not App.cursor.is_cursor_visible()
	App.input.simulate_device(InputDeviceType.Type.KEYBOARD_MOUSE, InputDeviceType.JoyBrand.GENERIC)
	var visible_on_mouse := App.cursor.is_cursor_visible()

	App.cursor.set_confined(true)
	var confined_on := App.cursor.is_confined()
	App.cursor.set_confined(false)
	var confined_off := not App.cursor.is_confined()

	_record_assertion(
		hidden_on_joypad and visible_on_mouse and confined_on and confined_off,
		"CASE 6: 切换手柄 (JOYPAD) 自动隐藏鼠标与双屏边界锁定 (set_confined) 状态机验证通过"
	)


func _record_assertion(condition: bool, title: String) -> void:
	if condition:
		_state.passed_cases += 1
		_state.append_log("[color=green][PASS][/color] %s" % title)
		if App.logger != null:
			App.logger.info(_LOG_TAG, "[PASS] %s" % title)
	else:
		_state.failed_cases += 1
		_state.append_log("[color=red][FAIL][/color] %s" % title)
		if App.logger != null:
			App.logger.error(_LOG_TAG, "[FAIL] %s" % title)

#endregion
