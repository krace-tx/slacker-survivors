# Scene Define Generator (`addons/scene_define_generator`)

Godot 4 编辑器底部栏交互插件：自动扫描 `res://src/game/` 下的路由级场景（`BaseScene` 顶层场景、`BaseDialog` 模态弹窗、`shared/component` 通用组件），支持可视化预览与一键注入到 `res://src/game/shared/define/generated/game_scenes.gd`。

---

## 一、 插件目录架构

对齐 `addons/locate_in_filesystem` 的三层职责分离规范（`plugin.gd` 门面 + `core/` 纯逻辑服务 + `ui/` 纯表现面板）：

```text
addons/scene_define_generator/
├── plugin.cfg                  # 插件元数据配置 (入口指向 plugin.gd)
├── plugin.gd                   # [门面] EditorPlugin：组装 core 与 ui，挂载底部栏，桥接 EditorInterface
├── README.md                   # 本文档
├── core/                       # [核心层] 零 UI 依赖的扫描与代码生成服务（支持编辑器与 Headless CLI 双模调用）
│   ├── scene_scanner.gd        # 递归扫描 .tscn 并自省根节点脚本基类 (BaseScene / BaseDialog / Component)
│   └── define_service.gd       # 组装确定性 GameScenes 代码、对比磁盘同步态 (preview) 与幂等写盘 (inject)
└── ui/                         # [表现层] 编辑器底部栏交互面板
    └── define_bottom_panel.gd  # 渲染工具栏按钮、三列状态树与代码预览框，纯信号向外通信
```

---

## 二、 核心能力与防膨胀规则

1. **三级路由准入过滤（防膨胀）**：
   - `GameScenes.Scene`：根节点脚本继承自 `BaseScene` 或文件名以 `_scene.tscn` 结尾；
   - `GameScenes.Dialog`：根节点脚本继承自 `BaseDialog` 或文件名以 `_dialog.tscn` 结尾；
   - `GameScenes.Component`：位于 `res://src/game/shared/component/` 下的通用预制件；
   - 各业务模块内部的局部私有子控件及 `res://src/test/` 测试场景自动忽略。
2. **底部栏（Bottom Bar）交互工作流**：
   - **扫描刷新 (Scan)**：只读预览并检测当前内存契约与磁盘 `game_scenes.gd` 是否一致；
   - **一键注入 Define (Inject)**：幂等写入 `res://src/game/shared/define/generated/game_scenes.gd` 并触发 `EditorFileSystem.scan()`；
   - **双击树节点跳转**：在左侧列表中双击任意已就绪场景，自动在 FileSystem 定位并打开该场景。
