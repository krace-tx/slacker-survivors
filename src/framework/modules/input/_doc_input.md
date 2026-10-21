# Framework · Input (双轨键位映射与复合输入系统)

> 统一接管 PC 键鼠与手柄控制器（Xbox / PlayStation / Switch / SteamDeck）的设备嗅探、上下文作用域栈、单键/组合键（`InputChord`）求值管线、二段式免勾选交互改键与增量持久化。

```text
src/framework/modules/input/
├── _doc_input.md                       # 本文档
├── base_input_system.gd                # 公开门面契约 BaseInputSystem (App.input，详尽注释)
│
├── types/                              # [公开契约与数据对象] 脱离目录自解释
│   ├── input_device_type.gd            # 设备大类 (KEYBOARD_MOUSE / JOYPAD) 与手柄品牌枚举 (XBOX / PLAYSTATION / NINTENDO / STEAM_DECK)
│   ├── input_context_type.gd           # 输入上下文作用域枚举 (GAMEPLAY / UI / SYSTEM / REBIND)
│   ├── input_binding_slot.gd           # 绑定槽位枚举 (PRIMARY 主键 / SECONDARY 副键)
│   ├── input_conflict_policy.gd        # 改键冲突策略枚举 (SWAP 互换 / REJECT 拒绝 / CLEAR_EXISTING 清除旧项 / ALLOW 共存)
│   ├── input_error.gd                  # 标准错误码常量 (Input.ActionNotFound / Input.BindingConflict / Input.RebindCanceled 等)
│   ├── input_chord.gd                  # 统一复合键契约 (modifiers + trigger、规范化签名、硬件直读判定、Dictionary 编解码)
│   └── input_glyph_info.gd             # UI 展示数据对象 (is_chord、glyph_keys 图标数组、key_labels、display_text)
│
└── impl/                               # [私有实现收敛] 外部不可见，严禁业务层直接引用
    ├── input_system.gd                 # 核心编排实现 (InputSystem extends BaseInputSystem)
    ├── input_device_tracker.gd         # 硬件嗅探器 (0.5 唤醒迟滞防抖、手柄型号 GUID 识别、热插拔追踪)
    ├── input_rebind_capturer.gd        # 二段式交互录制状态机 (按住修饰等主键、松开修饰算单键、吞没穿透输入)
    └── input_map_adapter.gd            # Godot InputMap 引擎适配器 (出厂基线快照、键鼠/手柄双轨隔离、Delta 增量序列化)
```

---

## 一、 四大行业级设计机制

1. **键鼠与手柄双轨双槽物理隔离 (`InputMapAdapter`)**：
   - 每个受管 Action 独立维护 `kb_0`（键鼠主）、`kb_1`（键鼠副）、`joy_0`（手柄主）、`joy_1`（手柄副）四个 [`InputChord`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/modules/input/types/input_chord.gd) 槽位。
   - 修改键盘按键绝不会洗掉同动作的手柄按键；重置默认时支持按单动作、单设备轨道或全量恢复。
2. **统一复合键（`InputChord`）与高阶优先消费管线**：
   - 最小绑定单元为 `0~2 个前置修饰键 + 1 个触发主键`，统一表达键盘组合键（`Shift + Q`）与手柄肩键组合技（`LB + Y`、`LT + A`）。
   - **高阶优先消费（Highest-Order Chord Consumption）**：同帧内优先求值组合键，命中后将该帧的触发主键与修饰键记入消费池，自动抑制同作用域下的低阶单键（如按 `Shift + Q` 放大招时绝不误触单键 `Q` 的小技能）。
   - **连续轴向豁免修饰锁**：[`App.input.get_vector()`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/modules/input/base_input_system.gd) 强制忽略修饰键状态，边按 `Shift` 边按 `WASD` 走位绝不卡顿。
   - **双帧戳对齐**：内部同时追踪 `Engine.get_process_frames()` 与 `Engine.get_physics_frames()`，无论业务在 `_process` 还是 `_physics_process` 调用 `is_action_just_pressed()` 均 100% 精确。
3. **输入上下文栈（Context Stack）与防关弹窗穿透（Wait-For-Release）**：
   - 弹窗打开时调用 `App.input.push_context(InputContextType.Context.UI)`（或设 `set_gameplay_input_enabled(false)`），自动释放战斗按压态；
   - 弹窗关闭切回 `GAMEPLAY` 时，对仍处于按住状态的离散触发键自动启用 **Wait-For-Release（松开解锁）**，彻底杜绝按手柄 `A` 或 `Space` 关弹窗的同一帧误放技能。
4. **二段式免勾选交互录制 (`InputRebindCapturer`)**：
   - 调用 `await App.input.rebind_interactive_async(action, device_type, slot)`：
     - 玩家直接按下非修饰键（如 `E` 或手柄 `A`）$\rightarrow$ **0ms 立即完成单键绑定**；
     - 玩家按下候选修饰键（`Ctrl/Shift/Alt/Meta` 或手柄 `LB/RB/LT/RT`）$\rightarrow$ 实时发射 `rebind_preview`（UI 显示 `"Shift + ..."`）：
       - 未松开期间再按主键（如 `Q`）$\rightarrow$ **立即完成组合键绑定 `[Shift + Q]`**；
       - 未按其它键直接松开该修饰键 $\rightarrow$ **确认为独立单键绑定 `[Shift]`**。

---

## 二、 使用范式

### 1. 局内角色移动与技能触发
```gdscript
func _physics_process(_delta: float) -> void:
	# 1. 四向移动（自动应用摇杆死区，且按住 Shift 放组合技时移动不断触）
	var move_dir := App.input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	velocity = move_dir * move_speed

	# 2. 离散动作与组合技触发（无需关心底层是键盘单键、Shift+Q 还是手柄 LB+Y）
	if App.input.is_action_just_pressed(&"ultimate"):
		_cast_ultimate()
	elif App.input.is_action_just_pressed(&"skill_1"):
		_cast_skill_1()
```

### 2. UI 按键图标随键鼠/手柄无缝热切
```gdscript
func _ready() -> void:
	Bus.input_device_changed.connect(_on_input_prompt_dirty)
	Bus.input_bindings_changed.connect(_on_input_prompt_dirty)
	_refresh_skill_prompts()

func _refresh_skill_prompts() -> void:
	var glyph: InputGlyphInfo = App.input.get_action_glyph(&"ultimate")
	# 键盘下显示 "Shift + Q"，Xbox 手柄显示 "LB + Y"，PS5 手柄显示 "L1 + △"
	ultimate_key_label.text = glyph.display_text
```

### 3. 设置界面交互式改键与存档落盘
```gdscript
func _on_rebind_button_pressed(action: StringName, device_type: int, slot: int) -> void:
	key_btn.text = "请按键..."
	var res := await App.input.rebind_interactive_async(
		action,
		device_type,
		slot,
		InputConflictPolicy.Policy.SWAP
	)
	if res.is_ok():
		var glyph := res.value as InputGlyphInfo
		key_btn.text = glyph.display_text
		# 导出增量字典存入设置模型
		settings_model.input_bindings = App.input.export_bindings()
	else:
		# 取消或超时，恢复原显示
		key_btn.text = App.input.get_action_glyph(action, device_type, slot).display_text
```
