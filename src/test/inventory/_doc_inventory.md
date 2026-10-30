# Inventory Test Playground (`src/test/inventory/`)

> 针对 `src/framework/infra/inventory/` 通用容器与原子事务基建的 **声明式 `.tscn` 组件化 MSVP 演练场 + 无头自动化契约验证模块**。

---

## 一、 模块分层与声明式 `.tscn` 组件树 (MSVP)

严格遵循 [`_doc_game.md`](../../game/_doc_game.md)「`view/scene/<domain>/` 与 `view/component/<domain>/` 单元文件夹包裹（`1 .tscn + N .gd`）」规范，所有 UI 结构、布局容器、`StyleBoxFlat` 样式及子预制体组合均静态声明在 `.tscn` 中（编辑器打开所见即所得，零 `_ready()` 动态拼节点）：

```text
src/test/inventory/
├── _doc_inventory.md                                       # 本说明文档
├── inventory_test.tscn                                     # 测试快捷启动入口（场景继承自 inventory_playground_scene.tscn）
├── model/
│   ├── inventory_item_visual_config.gd                     # 物品视觉色板、矢量图标枚举与 ItemSpec 映射 (*Config)
│   └── inventory_demo_state.gd                             # 选中容器/槽位/UID 与自检状态模型 (*State)
├── service/
│   └── inventory_demo_service.gd                           # 四类容器实例编排、跨拓扑拖拽/穿脱/锻造事务与 10 项内核自检
├── presenter/
│   └── inventory_demo_presenter.gd                         # 视图意图与容器 changed 信号双向胶水层
└── view/
	├── component/
	│   ├── art/                                            # [组件单元] 拖拽跟随卡片预制体与矢量图标辅助
	│   │   ├── inventory_drag_badge.tscn                   # 声明式拖拽预览悬浮卡片 (.tscn)
	│   │   ├── inventory_drag_badge.gd                     # InventoryDragBadge
	│   │   ├── inventory_mini_icon.gd                      # InventoryMiniIcon (@export 可配置图标控件)
	│   │   └── inventory_icon_painter.gd                   # InventoryIconPainter (抗锯齿几何矢量绘制工具)
	│   ├── header/                                         # [组件单元] 顶部状态、货币胶囊与全局操作栏
	│   │   ├── inventory_header_bar.tscn                   # 声明式顶栏预制体 (.tscn)
	│   │   └── inventory_header_bar.gd                     # InventoryHeaderBar
	│   ├── slot/                                           # [组件单元] 通用单格槽位卡片预制体
	│   │   ├── inventory_slot_card.tscn                    # 声明式单格槽位 (.tscn，含 6 态 StyleBoxFlat 与角标节点)
	│   │   └── inventory_slot_card.gd                      # InventorySlotCard
	│   ├── equip/                                          # [组件单元] 左栏规则装备槽与物品聚焦展台
	│   │   ├── inventory_equip_panel.tscn                  # 声明式左栏预制体 (.tscn，内嵌实例化 3 个 inventory_slot_card.tscn)
	│   │   └── inventory_equip_panel.gd                    # InventoryEquipPanel
	│   ├── bag/                                            # [组件单元] 中栏 16 格主背包面板
	│   │   ├── inventory_bag_panel.tscn                    # 声明式中栏预制体 (.tscn，4×4 GridContainer 预实例化 16 个槽位)
	│   │   └── inventory_bag_panel.gd                      # InventoryBagPanel
	│   └── grid/                                           # [组件单元] 右栏 6×5 二维空间战术箱面板
	│       ├── inventory_grid_panel.tscn                   # 声明式右栏预制体 (.tscn，挂载矩阵画布与导出样式资源)
	│       ├── inventory_grid_panel.gd                     # InventoryGridPanel
	│       └── inventory_grid_board.gd                     # InventoryGridBoard (6×5 占地渲染、实时预览与正交邻接桥)
	└── scene/
		└── playground/                                     # [主场景单元] 顶层路由舞台
			├── inventory_playground_scene.tscn             # 声明式主场景 (.tscn，组合 HeaderBar + EquipPanel + BagPanel + GridPanel)
			├── inventory_playground_scene.gd               # InventoryPlaygroundScene (extends BaseScene)
			└── inventory_playground_view.gd                # InventoryPlaygroundView (extends BaseView)
```

---

## 二、 运行方式

- **编辑器交互体验**：打开 `res://src/test/inventory/inventory_test.tscn`（或任意子组件 `.tscn` 单独预览布局），按 `F6` 直接运行。
- **命令行无头自检**：
  ```powershell
  & "D:/software/Godot/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe" --headless --path . res://src/test/inventory/inventory_test.tscn -- --inventory-test-auto-quit
  ```
