# Test · Input (输入与键位映射系统验证)

> 验证 `App.input`（[`src/framework/modules/input/`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/modules/input/_doc_input.md)）的自动化契约自检与交互式可视化沙盒面板（[`input_test.gd`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/test/input/input_test.gd)）。支持在编辑器中直接按 `F6` 独立运行。

```text
src/test/input/
├── _doc_input.md       # 本文档
├── input_test.gd       # 6 项自动化契约自检 + 双轨改键矩阵 + 实时移动/组合键沙盒 (extends BaseScene)
└── input_test.tscn     # 测试入口场景 (含 BaseView 根节点 $UI)
```

---

## 验证清单

1. **自动化契约自检（启动时自动运行并输出至 `App.logger` 与右侧报告面板）**：
   - **[1/6] `InputChord` 组合键签名归一化**：验证 `Shift + Ctrl + Q` 与 `Ctrl + Shift + Q` 生成完全一致的规范化签名（`KB:KEY_...`）且阶数 `order == 2`；
   - **[2/6] 键鼠与手柄双轨双槽物理隔离**：验证修改键盘主键（如 `skill_1`）绝不覆盖或清空同动作的手柄槽位绑定；
   - **[3/6] 同作用域冲突裁决策略**：验证 `SWAP` 策略下的无感双向互换（`skill_1` 与 `skill_2` 互换按键）与 `REJECT` 策略下的 `InputError.BINDING_CONFLICT` 精准拦截；
   - **[4/6] `Baseline + Delta` 增量补丁序列化**：验证 `export_bindings()` 仅输出与出厂默认不同的槽位增量，`import_bindings()` 精准还原，且 `reset_to_default()` 后恢复零差异空字典；
   - **[5/6] 四大设备品牌按键提示（`InputGlyphInfo`）动态转译**：验证同一动作（如 `ultimate`）在 `Keyboard ("Shift + Q")`、`Xbox ("LB + Y")`、`PlayStation ("L1 + △")` 与 `Switch ("L + X")` 下的实时语义转译；
   - **[6/6] `InputContextType` 上下文栈门控**：验证 `push_context(UI)` 压栈屏蔽与 `pop_context(UI)` 出栈恢复 `GAMEPLAY`。
2. **实时交互验证沙盒**：
   - **移动向量与按压态实时 HUD 监控（`_live_hud_label`）**：实时显示归一化四向移动向量 `(x, y)` 与当前所有处于按住状态的动作列表；
   - **全部 10 个动作边沿闪烁与行高亮反馈**：触发任意受管动作时，左侧动作名与按键提示实时点亮绿色指示标（`● <action>`，含 `0.22s` 脉冲余晖），并记入右侧最近 6 条触发时间戳日志（自动过滤点击左侧改键 UI 按钮时的鼠标左键 `attack` 误触）；
   - **移动 + 高阶组合键防污染验证**：按住 `WASD` 移动虚拟角色的同时按 `Shift + Q` 释放大招（`ultimate`），验证移动不断触，且无论同时松开还是先松开 `Shift` 均不会误触单键 `Q`（`skill_1`）；
   - **二段式免勾选交互录制与跨按钮切换**：点击任意槽位按钮，验证单按即绑、按住 `Shift` 实时预览 `"Shift + ..."` 并合成组合键、单松开 `Shift` 绑定独立修饰键、按 `ESC` 取消，以及录制途中直接点击其它槽位按钮时的无缝切换。
