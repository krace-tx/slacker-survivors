# UI 系统 (分层画布与安全区适配)

## 核心

提供游戏中所有界面呈现与分层渲染的基础架构。
确立全局 UI 统一门面（`App.ui`），规范五大分层 CanvasLayer（Background / Main / Popup / Toast / Top），并提供异形屏安全区（Safe Area）适配计算工具。

> 💡 **职责划分原则**：
> - `framework/modules/ui` **只做纯基建**：CanvasLayer 画布容器管理与屏幕安全区几何计算；
> - 具体的交互动效与弹窗堆栈（`BaseDialog`、`DialogManager`、`ToastManager`、`BaseTextureButton`）收敛在业务共享层 `src/game/shared/components/ui/`。

---

## 细节

### 1. 全局 UI 门面 (`BaseUISystem` / `UISystem`)
- **五大标准 CanvasLayer 分层**：
  - `BACKGROUND` (Layer 10)：动态背景、暗角。
  - `MAIN` (Layer 20)：HUD、主场景全屏 UI。
  - `POPUP` (Layer 30)：模态弹窗层、升级选卡、结算面板。
  - `TOAST` (Layer 40)：轻量飘字提醒、系统成就通知。
  - `TOP` (Layer 50)：全局 Loading 转圈、新手引导高亮、Debug 控制台。
- **获取画布层级**：
  - `App.ui.get_layer(BaseUISystem.Layer.POPUP)` 获取指定挂载目标。

### 2. 屏幕安全区适配 (`SafeArea`)
- 提供 `App.ui.get_safe_area_margins()` 获取当前硬件的安全区内边距（针对刘海屏、灵动岛、底部 Home 指示条）。
- 提供 `App.ui.apply_safe_area(control)` 直接为 Control 节点注入 Margin。

### 3. 场景顶级 UI (`BaseUIView`)
- 作为业务场景内的画面承载者，固定挂载在场景根节点下且节点名推荐为 `UI`。
- 内置移动端异形屏与安全区边距自动适配。

```text
src/framework/modules/ui/
├── _doc_ui.md                # 本文档
├── base_ui_system.gd         # UI 门面抽象基类 BaseUISystem (App.ui，画布分层与安全区)
├── base_ui_view.gd           # [业务基类] 场景视图根基类 (带安全区适配)
└── impl/                     # [私有实现]
    └── ui_system.gd          # 画布层级与安全区实现 (extends BaseUISystem)

# 业务表现层交互控件库（位于业务共享层）：
src/game/shared/components/ui/
├── base_texture_button.gd    # 业务贴图按钮 (缩放/音效/震动/滑动中继)
├── base_dialog.gd            # 模态弹窗业务基类 (进退场补间/点击遮罩关闭)
├── dialog_manager.gd         # 业务弹窗调度器 (暗色遮罩/后入先出堆栈/返回键监听)
└── toast_manager.gd          # 业务轻量飘字提示 (渐入渐出与浮动)
```

---

## 样例

### 1. 弹出模态对话框 (使用 DialogManager)
```gdscript
# 打开选卡升级弹窗
var dialog := await DialogManager.open("res://src/game/features/battle/upgrade_selection/upgrade_selection_dialog.tscn", {
    "options": cards
})
```

### 2. 发送飘字通知 (使用 ToastManager)
```gdscript
ToastManager.show("战斗胜利！")
```
