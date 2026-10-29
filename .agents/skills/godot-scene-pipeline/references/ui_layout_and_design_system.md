# Skill Wiki · 2D 响应式布局与极简设计系统规范 (UI Layout & Design System)

> 📖 **Wiki 定位**：消除 Godot 4 `Control` 布局常见的锚点失效、`0x0` 塌陷、文字截断与廉价高饱和配色问题，建立优雅克制的现代游戏 UI 视觉标准。

---

## 1. Godot 4 `Control` 布局黄金法则

本项目显示基准为 **`1920x1080` + `stretch/mode = "canvas_items"` + `stretch/aspect = "expand"`**（支持 16:9、16:10 与 21:9 超宽屏自适应）。

### 1.1 非容器子节点 vs. `Container` 子节点（最易踩坑点）
- **根节点 / 普通 `Control` 的直接子节点**：由 **Anchor Preset（锚点预设）** 控制定位：
  - 全屏铺满背景或根安全区：`ui.set_anchor_preset` 设为 `"full_rect"`；
  - 居中模态卡片或主舞台定宽容器：外包一层 `"full_rect"` 的 `CenterContainer` 或 `MarginContainer`，**不要**手算固定像素坐标硬摆在 `(360, 180)`，否则超宽屏下会偏左失衡！
- **`VBoxContainer` / `HBoxContainer` / `GridContainer` / `MarginContainer` 的直接子节点**：
  - 父容器会**接管**其位置与尺寸（`layout_mode = 2`），此时设置 `position` 或 `anchor_preset` 无效；
  - 必须通过 **`ui.set_size_flags`**（`fill` / `expand_fill` / `shrink_center`）与 **`custom_minimum_size`** 控制伸缩权重！

### 1.2 防塌陷与防溢出四条铁律
1. **交互热区底线**：所有 `Button`、槽位卡、图标节点的 `custom_minimum_size` 不得小于 `Vector2(32, 32)`（槽位卡建议 `64x64 ~ 88x88`），杜绝因空文本或异步贴图未加载导致控件塌陷成 `0x0`。
2. **弹性占位弹簧**：顶栏左右两端对齐时，在中间放入一个空 `Control` 并设 `size_flags_horizontal = "expand_fill"` 作为弹性弹簧，严禁写死几百像素的 `separation`。
3. **长文本防御**：动态名称/数值 `Label` 若处于固定宽度列中，根据语义开启 `autowrap_mode` 或 `text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS`（配合 `clip_text = true`），防止撑爆父面板。
4. **鼠标事件穿透（`mouse_filter`）**：装饰性背景 `ColorRect`、角标 `Label`、高亮遮罩框**必须**设置 `mouse_filter = Control.MOUSE_FILTER_IGNORE` (`2`)，防止拦截底层 `Button` 或拖拽槽位的点击事件！

---

## 2. 视觉审美与暗黑极简设计令牌 (Design Tokens)

遵循**“少文案、高信噪比、克制用色、呼吸留白”**原则，严禁堆砌冗长说明文字或刺眼纯红纯绿（`#FF0000` / `#00FF00`）：

### 2.1 推荐暗色系层级色板（Slate Dark 体系）
| 层级语义 | 推荐 Hex | 适用场景 |
| :--- | :---: | :--- |
| **画布底层背景** | `#0B0F17` | 全屏底色或模态半透明遮罩 `Color(0.04, 0.06, 0.09, 0.78)` |
| **一级面板底色** | `#111827` | 区域主面板（装备栏、背包窗体、弹窗主体），配 `1px` `#1F2937` 细边框 |
| **二级内嵌容器 / 槽位底色** | `#0D1320` / `#162032` | 物品槽位、详情内嵌卡、输入框底板 |
| **悬停 / 选中微高亮** | `#1E293B` + `#38BDF8` 边框 | 交互焦点态，边框提亮而非大面积铺满刺眼亮色 |
| **主标题 / 核心数值文本** | `#F1F5F9` | 标题、物品名、关键数量角标 |
| **次要标签 / 辅助维度文本** | `#94A3B8` / `#64748B` | 槽位部位标签、容量计数 `7 / 16`、快捷键轻提示 |
| **品质与状态语义色** | 普通 `#94A3B8` · 精良 `#34D399` · 稀有 `#38BDF8` · 史诗 `#A78BFA` · 传说 `#FBBF24` · 警示 `#F87171` | 仅用于顶部 `2px` 品质细条、徽章描边或关键状态点缀（面积占比 ≤ 10%） |

### 2.2 间距与圆角阶梯（8pt 栅格体系）
- **舞台外边距**：上下 `36~48px`，左右 `48~80px`（或使用 `CenterContainer` 限宽 `1280~1480px` 保持超宽屏视觉聚拢）。
- **面板内边距（`content_margin`）**：主面板 `18~22px`，子卡片 `10~14px`，胶囊徽章 `[12, 6, 12, 6]`。
- **组件间距（`separation`）**：主区域间 `18~24px`，卡片网格间 `8~12px`，紧凑图文行 `6~8px`。
- **圆角阶梯（`corner_radius`）**：外层大面板 `12~14px`，内部槽位卡 `8~10px`，按钮/胶囊 `6~8px`（外圆角 ≥ 内圆角，保持同心视觉和谐）。
- **字阶规范**：主标题 `18~22px`、区块标题 `15~16px`、正文/按钮 `13~14px`、角标/辅助注记 `11~12px`。

---

## 3. 主题资源（`.tres`）复用原则

当同一模块内多个组件共享相同的卡片底板或按钮样式时：
1. 优先通过 Godot MCP `resource.create` 将 `StyleBoxFlat` 保存为模块或共享目录下的 `.tres` 资源；
2. 各 `.tscn` 通过 `ui.set_theme_override` 传入 `"res://...tres"` 路径直接引用，避免在十几个 `.tscn` 中重复拷贝内联样式。
