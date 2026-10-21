# Test · Input (输入与键位映射系统验证)

> 验证 `App.input`（`src/framework/modules/input/`）的自动化契约自检与交互式可视化面板。支持在编辑器中直接按 `F6` 独立运行。

## 验证清单

1. **自动化契约自检（启动时自动运行并输出至 `App.logger` 与面板）**：
   - 键鼠与手柄双轨双槽隔离（修改键盘主键不影响手柄绑定）；
   - `InputChord` 组合键签名归一化（`Shift + Ctrl + Q` 与 `Ctrl + Shift + Q` 等价）；
   - 同作用域改键冲突 `SWAP` 无感互换与 `REJECT` 拦截；
   - 增量补丁序列化（`export_bindings()` 仅输出变更项，`import_bindings()` 精准还原，`reset_to_default()` 恢复零差异）；
   - 四大设备品牌（Keyboard / Xbox / PlayStation / Switch）按键提示（`InputGlyphInfo`）动态转译；
   - `InputContextType` 上下文栈压栈屏蔽与出栈恢复。
2. **实时交互验证面板**：
   - **移动 + 组合键防污染验证**：按住 `WASD` 移动虚拟角色的同时按 `Shift + Q` 释放大招，验证移动不断触且单键 `Q`（小技能）被高阶组合键消费不误触；
   - **二段式免勾选交互录制**：点击任意槽位按钮，测试单按绑定、按住 `Shift` 实时预览 `"Shift + ..."` 并绑定组合键、松开单 `Shift` 绑定独立修饰键、按 `ESC` 取消录制。
