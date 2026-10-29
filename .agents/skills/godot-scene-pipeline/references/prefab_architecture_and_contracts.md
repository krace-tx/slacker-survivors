# Skill Wiki · 声明式预制体分层与脚本解耦契约 (Prefab Architecture & Contracts)

> 📖 **Wiki 定位**：规范 Godot 场景如何拆分为高内聚、可复用的声明式 `.tscn` 预制体单元，以及 `.tscn` 与 GDScript 之间的通信与依赖注入边界。

---

## 1. `1 .tscn + N .gd` 预制体单元封装铁律

任何可视化场景或组件都必须以**独立单元子目录**形式组织，严禁多个 `.tscn` 混堆在同一扁平目录中：

```text
src/game/features/<feature>/view/
├── scene/
│   └── <stage_domain>/                       # 路由级顶层舞台单元（1 .tscn + N .gd）
│       ├── <feature>_<stage>_scene.tscn      # 根节点继承 BaseScene（仅编排子面板、环境与相机）
│       ├── <feature>_<stage>_scene.gd        # 生命周期钩子与 Presenter 装配
│       └── <feature>_<stage>_view.gd         # 根视图协调器（向 Presenter 暴露渲染 API 与交互信号）
└── component/
    ├── <panel_domain>/                       # 区域级复合面板单元（≤ 30 本地节点）
    │   ├── <feature>_<panel>_panel.tscn      # 内部通过 instantiate_scene 组合叶组件
    │   └── <feature>_<panel>_panel.gd
    └── <atom_domain>/                        # 叶级原子组件单元（≤ 15 本地节点）
        ├── <feature>_<atom>_card.tscn
        └── <feature>_<atom>_card.gd
```

- **跨模块复用升级**：若某组件被 **≥ 2 个 Feature** 共同使用，按 `framework-aware` 准入法则上提至 `src/game/shared/component/<unit>/`。
- **路由级注册**：新建正式路由级 `BaseScene` / `BaseDialog` 后，必须通过 `addons/scene_define_generator`（或 Headless `define_service.gd`）同步刷新 [`game_scenes.gd`](../../../../src/game/shared/model/config/game_scenes.gd)。

---

## 2. 三层节点预算与何时必须拆分组件

| 层级 | 本地节点预算 | 职责定义 | 强制拆分红线 |
| :--- | :---: | :--- | :--- |
| **Atom / Molecule（叶组件）** | `3 ~ 15` | 槽位卡、货币胶囊、属性词条、血条、交互道具 | 内部不含业务逻辑，输入纯展示 DTO/标量，输出语义化 `signal` |
| **Organism（区域面板）** | `10 ~ 30` | 顶栏、装备栏、背包网格面板、技能选择栏、关卡区块 | 同构子节点重复 **≥ 2 次**时，严禁复制粘贴子树，必须抽离叶组件 `.tscn` |
| **Stage（顶层舞台/弹窗）** | `8 ~ 25` | `BaseScene` 全屏舞台、`BaseDialog` 模态弹窗 | 本地节点数 **> 40** 时由 `audit_scene.gd` 告警拦截 |

---

## 3. 声明式 `.tscn` vs. 运行时 `.gd` 的绝对边界

### 必须写在 `.tscn` 中的内容（编辑器零运行可见）
1. **全部静态容器骨架**：`MarginContainer`、`VBoxContainer`、`HBoxContainer`、`GridContainer`、`PanelContainer`、`CanvasLayer`、`WorldEnvironment`、灯光与相机。
2. **默认占位态**：标题文本、按钮文案、图标默认尺寸（`custom_minimum_size`）、固定槽位数量的子预制体实例（例如固定 3 格装备栏或固定 16 格快捷背包，直接在 `.tscn` 中实例化好子槽位，打开编辑器即可直观看到完整矩阵）。
3. **样式与布局标志**：锚点预设、`size_flags`、边距与基础 `StyleBox`。

### 允许写在 `.gd` 中的内容（动态数据绑定与交互状态）
1. **唯一名引用绑定**：
   ```gdscript
   @onready var _title_label: Label = %TitleLabel
   @onready var _equip_panel: InventoryEquipPanel = %EquipPanel
   ```
2. **动态变长列表的预制体实例化**：当列表项数量由运行时存档/配置动态决定时，通过 `@export var item_card_scene: PackedScene` 在脚本中调用 `item_card_scene.instantiate()`（**实例化的是声明式 `.tscn` 预制体，而非手写 `PanelContainer.new()` 拼装十几个子节点！**）。
3. **状态态视觉切换**：根据选中/悬停/禁用/品质色动态切换 `modulate`、边框高亮或播放 `Tween` 微动效。
4. **自定义画布绘制**：网格底板线、技能范围指示扇形、曲线连线等纯几何图形，封装在专职小控件的 `_draw()` 中。

---

## 4. 父子组件通信铁律（下行调方法，上行发 `signal`）

- **严禁向上穿透**：子组件 `.gd` 内严禁出现 `get_parent()`、`owner.xxx()` 或跨级查找兄弟节点。
- **下行更新**：父面板调用子组件显式强类型公开方法（如 `slot_card.apply_item(view_data)`）。
- **上行通知**：子组件仅定义过去分词 `signal`（如 `signal slot_clicked(slot_idx: int, button: int)`），由父面板在 `_ready()`（或 `.tscn` 持久化连接）中统一监听并逐级收敛至 `Presenter`。
