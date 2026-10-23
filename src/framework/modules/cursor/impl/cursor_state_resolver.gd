class_name CursorStateResolver
extends RefCounted

## 微内核 ①：五层优先级纯逻辑光标状态裁决器（Five-Layer Priority Cursor State Resolver）。[br]
##
## [b]单一职责：[/b][br]
## 仅负责根据 5 层输入源实时裁决当前应当显示的 `(shape, is_pressed, winning_layer)`，零渲染与零引擎 DisplayServer 耦合：[br]
## - [b]Layer 5 (Override Stack)[/b]：拖拽中、技能选点、网络等待等强锁覆盖；[br]
## - [b]Layer 4 (UI Control Hover)[/b]：自动嗅探 `Viewport.gui_get_hovered_control()`（含自定义绑定、`disabled` 禁用按钮自动转 `FORBIDDEN`、可用按钮转 `POINTER`、输入框转 `IBEAM`）；[br]
## - [b]Layer 3 (World Entity Hover)[/b]：局内 NPC / 宝箱 / 敌人悬停（仅在未被 UI 遮挡且处于 `GAMEPLAY` 上下文时生效）；[br]
## - [b]Layer 2 (Context Base)[/b]：`UI` 上下文强制回退 `DEFAULT`，`GAMEPLAY` 上下文使用 `gameplay_cursor`；[br]
## - [b]Layer 1 (Fallback)[/b]：全局默认 `DEFAULT`。

#region Constants & State
const META_CURSOR_SHAPE: StringName = &"_fw_cursor_shape"
const META_CURSOR_PRESSED_SHAPE: StringName = &"_fw_cursor_pressed_shape"

var _gameplay_shape: int = CursorShapeType.Shape.DEFAULT
var _overrides: Array[Dictionary] = []    ## [{token: StringName, shape: int, priority: int, seq: int}]
var _world_hovers: Array[Dictionary] = [] ## [{id: Variant, shape: int, priority: int, seq: int}]
var _seq_counter: int = 0
#endregion


#region Configuration & Stack Mutations
func set_gameplay_cursor(shape: int) -> void:
	_gameplay_shape = shape


func get_gameplay_cursor() -> int:
	return _gameplay_shape


func push_override(token: StringName, shape: int, priority: int = 100) -> void:
	if token.is_empty():
		return
	pop_override(token)
	_seq_counter += 1
	_overrides.append({
		"token": token,
		"shape": shape,
		"priority": priority,
		"seq": _seq_counter,
	})
	_sort_stack(_overrides)


func pop_override(token: StringName) -> void:
	for i in range(_overrides.size() - 1, -1, -1):
		if _overrides[i]["token"] == token:
			_overrides.remove_at(i)


func clear_overrides() -> void:
	_overrides.clear()


func get_override_count() -> int:
	return _overrides.size()


func bind_control(control: Control, hover_shape: int, pressed_shape: int = -1) -> void:
	if not is_instance_valid(control):
		return
	control.set_meta(META_CURSOR_SHAPE, hover_shape)
	if pressed_shape >= 0:
		control.set_meta(META_CURSOR_PRESSED_SHAPE, pressed_shape)
	elif control.has_meta(META_CURSOR_PRESSED_SHAPE):
		control.remove_meta(META_CURSOR_PRESSED_SHAPE)


func unbind_control(control: Control) -> void:
	if not is_instance_valid(control):
		return
	if control.has_meta(META_CURSOR_SHAPE):
		control.remove_meta(META_CURSOR_SHAPE)
	if control.has_meta(META_CURSOR_PRESSED_SHAPE):
		control.remove_meta(META_CURSOR_PRESSED_SHAPE)


func set_world_hover(source_id: Variant, shape: int, priority: int = 0) -> void:
	if source_id == null:
		return
	clear_world_hover(source_id)
	_seq_counter += 1
	_world_hovers.append({
		"id": source_id,
		"shape": shape,
		"priority": priority,
		"seq": _seq_counter,
	})
	_sort_stack(_world_hovers)


func clear_world_hover(source_id: Variant) -> void:
	for i in range(_world_hovers.size() - 1, -1, -1):
		if _world_hovers[i]["id"] == source_id:
			_world_hovers.remove_at(i)


func get_world_hover_count() -> int:
	return _world_hovers.size()
#endregion


#region Five-Layer Evaluation Funnel
## 执行五层优先级漏斗求值，返回 `{"shape": int, "is_pressed": bool, "layer": String}`。
func evaluate(
	hovered_control: Control,
	input_context: int,
	is_mouse_left_pressed: bool
) -> Dictionary:
	# Layer 5: 强锁覆盖栈 (Override Stack)
	if not _overrides.is_empty():
		var top_ov: Dictionary = _overrides[0]
		var ov_shape: int = int(top_ov["shape"])
		if is_mouse_left_pressed:
			ov_shape = CursorShapeType.get_pressed_counterpart(ov_shape)
		return {
			"shape": ov_shape,
			"is_pressed": is_mouse_left_pressed,
			"layer": "L5_OVERRIDE:%s" % String(top_ov["token"]),
		}

	# Layer 4: UI 控件自动嗅探与声明式绑定 (UI Control Hover)
	if is_instance_valid(hovered_control):
		var ui_eval := _evaluate_hovered_control(hovered_control, is_mouse_left_pressed)
		if bool(ui_eval["matched"]):
			return {
				"shape": int(ui_eval["shape"]),
				"is_pressed": is_mouse_left_pressed,
				"layer": str(ui_eval["layer"]),
			}

	# Layer 3: 局内世界物体悬停 (仅当未被交互型 UI 控件遮挡且处于 GAMEPLAY 上下文时生效)
	var is_gameplay_ctx := (input_context == InputContextType.Context.GAMEPLAY)
	if is_gameplay_ctx and not _world_hovers.is_empty():
		var top_wh: Dictionary = _world_hovers[0]
		var wh_shape: int = int(top_wh["shape"])
		if is_mouse_left_pressed:
			wh_shape = CursorShapeType.get_pressed_counterpart(wh_shape)
		return {
			"shape": wh_shape,
			"is_pressed": is_mouse_left_pressed,
			"layer": "L3_WORLD_HOVER",
		}

	# Layer 2: 输入上下文基准层 (Context Base)
	if is_gameplay_ctx:
		var gp_shape := _gameplay_shape
		if is_mouse_left_pressed:
			gp_shape = CursorShapeType.get_pressed_counterpart(gp_shape)
		return {
			"shape": gp_shape,
			"is_pressed": is_mouse_left_pressed,
			"layer": "L2_GAMEPLAY_BASE",
		}

	# Layer 1: UI 上下文或全局默认兜底 (Default Fallback)
	return {
		"shape": CursorShapeType.Shape.DEFAULT,
		"is_pressed": is_mouse_left_pressed,
		"layer": "L1_DEFAULT",
	}
#endregion


#region Internal Control Sniffer
func _evaluate_hovered_control(ctrl: Control, is_pressed: bool) -> Dictionary:
	# 1. 向上追溯最多 3 层父 Control，查找是否绑定了声明式元数据 META_CURSOR_SHAPE
	var cursor_node: Node = ctrl
	var depth := 0
	while is_instance_valid(cursor_node) and cursor_node is Control and depth < 4:
		var c := cursor_node as Control
		if c.has_meta(META_CURSOR_SHAPE):
			var custom_shape := int(c.get_meta(META_CURSOR_SHAPE))
			if is_pressed:
				if c.has_meta(META_CURSOR_PRESSED_SHAPE):
					custom_shape = int(c.get_meta(META_CURSOR_PRESSED_SHAPE))
				else:
					custom_shape = CursorShapeType.get_pressed_counterpart(custom_shape)
			return {"matched": true, "shape": custom_shape, "layer": "L4_UI_META:%s" % c.name}
		cursor_node = c.get_parent()
		depth += 1

	# 2. 自动识别 BaseButton（可用 -> POINTER，disabled -> FORBIDDEN）
	var btn := _find_ancestor_button(ctrl)
	if is_instance_valid(btn):
		if btn.disabled:
			return {"matched": true, "shape": CursorShapeType.Shape.FORBIDDEN, "layer": "L4_UI_DISABLED_BTN"}
		return {"matched": true, "shape": CursorShapeType.Shape.POINTER, "layer": "L4_UI_BUTTON"}

	# 3. 自动识别文本输入控件（LineEdit / TextEdit -> IBEAM）
	if ctrl is LineEdit or ctrl is TextEdit:
		return {"matched": true, "shape": CursorShapeType.Shape.IBEAM, "layer": "L4_UI_TEXT_INPUT"}

	# 4. 自动识别滑块、标签栏、下拉框等可交互标准控件
	if ctrl is Slider or ctrl is ScrollBar or ctrl is TabBar:
		return {"matched": true, "shape": CursorShapeType.Shape.POINTER, "layer": "L4_UI_WIDGET"}

	# 5. 检查控件是否显式设置了非默认的 mouse_default_cursor_shape
	var raw_ctrl_shape := ctrl.mouse_default_cursor_shape
	if raw_ctrl_shape != Control.CURSOR_ARROW:
		return {
			"matched": true,
			"shape": CursorShapeType.from_control_cursor_shape(raw_ctrl_shape),
			"layer": "L4_UI_CURSOR_PROP",
		}

	return {"matched": false, "shape": CursorShapeType.Shape.DEFAULT, "layer": ""}


static func _find_ancestor_button(ctrl: Control) -> BaseButton:
	var cur: Node = ctrl
	var depth := 0
	while is_instance_valid(cur) and cur is Control and depth < 3:
		if cur is BaseButton:
			return cur as BaseButton
		cur = cur.get_parent()
		depth += 1
	return null


static func _sort_stack(stack: Array[Dictionary]) -> void:
	stack.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := int(a["priority"])
		var pb := int(b["priority"])
		if pa != pb:
			return pa > pb
		return int(a["seq"]) > int(b["seq"])
	)
#endregion
