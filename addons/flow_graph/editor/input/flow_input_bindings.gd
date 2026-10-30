@tool
extends RefCounted

## FlowGraph 编辑器物理鼠键默认绑定表（Declarative Physical Mouse & Keyboard Binding Table）。[br]
##
## [b]架构铁律：[/b][br]
## 本文件是 `addons/flow_graph/editor/` 内唯一允许直接出现 `KEY_*` 与 `MOUSE_BUTTON_*` 物理常量的声明层；所有视图与交互控制器必须通过 [`FlowEditorInput`](flow_editor_input.gd) 查询语义动作。


#region 视口缩放与触控板手势物理参数

const WHEEL_ZOOM_STEP: float = 1.12
const TRACKPAD_PAN_SPEED: float = 18.0

const POINTER_BUTTONS: Dictionary = {
	&"ptr.primary": MOUSE_BUTTON_LEFT,
	&"ptr.pan_dedicated": MOUSE_BUTTON_MIDDLE,
	&"ptr.context_or_pan": MOUSE_BUTTON_RIGHT,
	&"ptr.wheel_zoom_in": MOUSE_BUTTON_WHEEL_UP,
	&"ptr.wheel_zoom_out": MOUSE_BUTTON_WHEEL_DOWN,
}

## 点击画布时应触发收起原位改名框并抢占焦点的鼠标按键集合
const CANVAS_FOCUS_BUTTONS: Array[MouseButton] = [
	MOUSE_BUTTON_LEFT,
	MOUSE_BUTTON_MIDDLE,
	MOUSE_BUTTON_RIGHT,
]

#endregion


#region 作用域优先级顺序与默认键盘绑定

const WORKBENCH_ORDER: Array[StringName] = [
	&"wb.save",
	&"wb.redo",
	&"wb.undo",
]

const CANVAS_ORDER: Array[StringName] = [
	&"canvas.redo",
	&"canvas.undo",
	&"canvas.select_all",
	&"canvas.duplicate",
	&"canvas.delete",
	&"canvas.rename",
	&"canvas.append_downstream",
	&"canvas.quick_add",
	&"canvas.space_hand_or_picker",
	&"canvas.fit_or_frame",
	&"canvas.toggle_breakpoint",
	&"canvas.cancel_or_clear",
]

const MODAL_ORDER: Array[StringName] = [
	&"modal.confirm",
	&"modal.cancel",
	&"modal.nav_next",
	&"modal.nav_prev",
]


static func build_default_key_bindings() -> Dictionary:
	return {
		# ── 工作台全局级快捷键 ──
		&"wb.save": [_chord(KEY_S, true, false, false)],
		&"wb.undo": [_chord(KEY_Z, true, false, false)],
		&"wb.redo": [
			_chord(KEY_Y, true, false, false),
			_chord(KEY_Z, true, true, false),
		],

		# ── 画布编辑、选取、视野与断点快捷键 ──
		&"canvas.undo": [_chord(KEY_Z, true, false, false)],
		&"canvas.redo": [
			_chord(KEY_Y, true, false, false),
			_chord(KEY_Z, true, true, false),
		],
		&"canvas.select_all": [_chord(KEY_A, true, false, false)],
		&"canvas.duplicate": [_chord(KEY_D, true, false, false)],
		&"canvas.delete": [
			_chord(KEY_DELETE, false, false, false),
			_chord(KEY_BACKSPACE, false, false, false),
		],
		&"canvas.rename": [_chord(KEY_F2, false, false, false)],
		&"canvas.append_downstream": [_chord(KEY_TAB, false, false, false)],
		&"canvas.quick_add": [_chord(KEY_A, false, true, false)],
		&"canvas.space_hand_or_picker": [_chord(KEY_SPACE, false, false, false)],
		&"canvas.fit_or_frame": [
			_chord(KEY_F, false, false, false),
			_chord(KEY_HOME, false, false, false),
		],
		&"canvas.toggle_breakpoint": [_chord(KEY_F9, false, false, false)],
		&"canvas.cancel_or_clear": [_chord(KEY_ESCAPE, false, false, false)],

		# ── 模态搜索弹窗与原位重命名框快捷键 ──
		&"modal.confirm": [
			_chord(KEY_ENTER, false, false, false),
			_chord(KEY_KP_ENTER, false, false, false),
		],
		&"modal.cancel": [_chord(KEY_ESCAPE, false, false, false)],
		&"modal.nav_next": [_chord(KEY_DOWN, false, false, false)],
		&"modal.nav_prev": [_chord(KEY_UP, false, false, false)],
	}


static func _chord(keycode: Key, cmd_or_ctrl: bool, shift: bool, alt: bool) -> Dictionary:
	return {
		"key": int(keycode),
		"cmd_or_ctrl": cmd_or_ctrl,
		"shift": shift,
		"alt": alt,
	}

#endregion
