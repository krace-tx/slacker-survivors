# UI 系统 (分层画布、弹窗堆栈与基础控件)

## 核心

提供游戏中所有界面呈现、分层渲染、模态弹窗与通用控件的基础架构。
确立全局 UI 统一门面（`App.ui`），规范分层 CanvasLayer（Background/Main/Popup/Toast/Top），收拢模态弹窗堆栈、暗色遮罩与点击空白自动关闭机制，并与物理返回键及安全区全面闭环。

---

## 细节

### 1. 全局 UI 门面 (`BaseUISystem` / `UISystem`)
- **五大标准 CanvasLayer 分层**：
  - `BACKGROUND` (Layer 10)：动态背景、暗角。
  - `MAIN` (Layer 20)：HUD、主场景全屏 UI。
  - `POPUP` (Layer 30)：模态弹窗、升级选卡、结算面板。
  - `TOAST` (Layer 40)：轻量飘字提醒、系统成就通知。
  - `TOP` (Layer 50)：全局 Loading 转圈、新手引导高亮、Debug 控制台。
- **弹窗堆栈（Modal Stack）与遮罩自愈**：
  - 自动维护黑色半透明遮罩（`BackdropMask`），动态调整到栈顶弹窗的正下方。
  - 支持多层弹窗连续压栈，后入先出，点击遮罩或物理返回键自动关闭顶层弹窗。
- **轻量飘字（Toast）**：
  - `App.ui.show_toast("消息文本")` 自动创建浮动动效并在播放完成后自动释放。

### 2. 模态弹窗基类 (`BaseDialog`)
- 继承 `Control`，提供标准参数绑定与打开/关闭生命周期钩子：
  - `_on_open(params: Dictionary)`：挂载数据与初始化。
  - `_on_close()`：注销监听与动效清理。
- 内置弹性缩放进退场补间动画与参数开关：`close_on_backdrop`、`close_on_back`、`enable_animation`。

### 3. 场景顶级 UI (`BaseUIView`)
- 作为业务场景内的画面承载者，固定挂载在场景根节点下且节点名推荐为 `UI`。
- 内置移动端异形屏与安全区边距适配（`DisplayServer.get_display_safe_area()`）。

### 4. 贴图按钮 (`BaseTextureButton`)
- 封装按压缩放补间、点击音效与设备振动反馈。
- 内置手势消抖与 `ScrollContainer` 滑动中继（Scroll Forwarding），杜绝列表卡片抢占触摸事件导致列表无法滚动的冲突，并在滑动释放时自动拦截误触。

```text
src/framework/modules/ui/
├── _doc_ui.md                # 本文档
├── base_ui_system.gd         # UI 门面抽象基类 BaseUISystem (App.ui，详尽注释)
├── base_dialog.gd            # [业务基类] 模态弹窗与对话框基类 (允许业务继承)
├── base_ui_view.gd           # [业务基类] 场景视图根基类 (允许业务继承)
└── impl/                     # [私有收敛]
    ├── ui_system.gd          # UI 分层与弹窗调度实现 (extends BaseUISystem)
    └── modal_stack.gd        # 模态弹窗栈与暗色遮罩管理

# 独立原子控件库：
src/framework/components/ui/
└── base_texture_button.gd    # 通用贴图按钮控件 (缩放/音效/震动/滑动中继)
```

---

## 样例

### 1. 弹出模态对话框
```gdscript
# 打开选卡升级弹窗
var res := await App.ui.open_popup("res://src/game/ui/upgrade_dialog.tscn", {
    "options": [card1, card2, card3]
})
if res.is_ok():
    App.log.info("UI", "Upgrade dialog opened.")
```

### 2. 实现自定义模态弹窗
```gdscript
class_name UpgradeDialog extends BaseDialog

@onready var title_label: Label = $Panel/Title

func _on_open(params: Dictionary) -> void:
    var options: Array = params.get("options", [])
    title_label.text = "选择一项升级能力"

func _on_close() -> void:
    # 自定义清理逻辑
    pass
```

### 3. 发送飘字通知
```gdscript
App.ui.show_toast("金币 +100")
```
