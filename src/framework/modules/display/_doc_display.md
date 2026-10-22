# Display 系统 (显示硬件控制、安全区与全局画布分层)

## 核心

提供游戏中显示设备管理、窗口/全屏状态机、分辨率钳制、宽高比拉伸策略（Stretch Mode & Aspect）、异形屏安全区（Notch Safe Area）逆矩阵投影以及五大全局画布分层（CanvasLayer）的统一门面（`App.display`）。

> **职责划分原则**：
> - `framework/modules/display`（`App.display`）统一掌管有状态的**显示与视口舞台系统**：五大 `CanvasLayer` 挂载容器、窗口模式（窗口化/无边框/全屏/独占全屏）、分辨率钳制与多显示器居中、宽高比拉伸配置、VSync 帧率上限、异形屏 Safe Area 几何投影以及 `BaseView` 视图根基类；
> - 具体的交互动效与弹窗堆栈（`BaseDialog`、`DialogManager`、`ToastManager`、`BaseTextureButton`）收敛在业务共享层 `src/game/shared/component/`（其中 `BaseDialog` 直接继承自 `BaseView`）。

---

## 细节

### 1. 全局显示与舞台门面 (`BaseDisplaySystem` / `DisplaySystem`)
- **五大标准 CanvasLayer 分层 (`App.display.get_layer`)**：
  - `BACKGROUND` (Layer 10)：动态背景、暗角。
  - `MAIN` (Layer 20)：HUD、主场景全屏 UI。
  - `POPUP` (Layer 30)：模态弹窗层、升级选卡、结算面板。
  - `TOAST` (Layer 40)：轻量飘字提醒、系统成就通知。
  - `TOP` (Layer 50)：全局 Loading 转圈、新手引导高亮、Debug 控制台。
- **窗口显示模式状态机 (`App.display.set_window_mode` / `toggle_fullscreen`)**：
  - 支持 `WINDOWED`、`BORDERLESS_WINDOWED`、`FULLSCREEN`、`EXCLUSIVE_FULLSCREEN` 四态切换，切回窗口化时自动恢复边框并居中。
- **分辨率钳制与多显示器居中 (`App.display.set_resolution` / `get_available_resolutions`)**：
  - 窗口化模式下自动将目标分辨率钳制在当前显示器可用工作区（扣除任务栏）内并居中，防止低分屏误设高分辨率导致窗口越界。
- **宽高比与拉伸策略 (`App.display.configure_stretch`)**：
  - 动态配置根窗口的 `content_scale_mode`、`content_scale_aspect`、设计基准尺寸与整体缩放倍率。
- **异形屏安全区与全局安全比例逆矩阵投影 (`App.display.get_safe_area_rect` / `apply_safe_area` / `set_safe_area_scale` / `set_lock_design_aspect`)**：
  - 移动端将物理屏幕刘海/手势条安全区与当前窗口矩形求交，再通过 `Viewport.get_final_transform().affine_inverse()` 逆矩阵映射回逻辑画布坐标（桌面端自动忽略操作系统任务栏工作区裁剪，避免全屏/贴边窗口底部出现灰边）。
  - 支持全局默认安全区缩放比例（`set_safe_area_scale(0.80 ~ 1.00)`，四周对称向内留白）与全局默认设计宽高比锁定（`set_lock_design_aspect(bool)`，超宽屏居中锁定项目基准设计宽高比安全框），变更时发射 `safe_area_changed` 信号驱动所有活动 `BaseView` 实时重排。
- **VSync、帧率与硬件诊断 (`App.display.set_vsync_mode` / `set_max_fps`)**：
  - 提供垂直同步、最大帧率上限、显示器刷新率、DPI 与高分屏缩放系数读写。
- **视口渲染管线原子控制与幂等防卡死保护 (`App.display.set_msaa_2d` / `set_screen_space_aa` / `set_scaling_3d_scale`)**：
  - 提供 `msaa_2d`、`msaa_3d`、`screen_space_aa`、`scaling_3d_scale` 与 `canvas_texture_filter` 五组原子级渲染管线读写接口。
  - **幂等短路保护**：窗口模式、分辨率、VSync 与抗锯齿设置均内置当前值比对短路，若目标值未变则直接返回，杜绝底层操作系统窗口重建与 Vulkan/D3D12 交换链/帧缓冲重复分配引发的主线程卡顿。

### 2. 统一视图根基类 (`BaseView`)
- 与 MSVP 架构中的 `View` 层精准对齐，作为业务场景内画面承载者或面板根基类。
- 提供统一生命周期 `open(params: BaseParams = null)` / `close()` / `_on_open(params)` / `_on_close()` / `get_params()` 与信号 `opened` / `closed`。
- 内置 `task_scope: TaskScope` 异步任务作用域与移动端异形屏安全区自动适配（随视口尺寸旋转变化实时重排）。

```text
src/framework/modules/display/
├── _doc_display.md           # 本文档
├── base_display_system.gd    # 显示与画布门面抽象基类 BaseDisplaySystem (App.display)
├── base_view.gd              # [业务基类] 视图根基类 BaseView (带统一生命周期、TaskScope 与安全区自动适配)
└── impl/                     # [私有实现]
    └── display_system.gd     # 显示控制与画布分层实现 (extends BaseDisplaySystem)

# 业务表现层交互控件库（位于业务共享层二级子域）：
src/game/shared/component/
├── button/base_texture_button.gd # 业务贴图按钮 (缩放/音效/震动/滑动中继)
├── dialog/base_dialog.gd         # 模态弹窗业务基类 (extends BaseView，进退场补间/点击遮罩关闭)
├── dialog/dialog_manager.gd      # 业务弹窗调度器 (暗色遮罩/后入先出堆栈/返回键监听)
└── toast/toast_manager.gd        # 业务轻量飘字提示 (渐入渐出与浮动)
```

---

## 样例

### 1. 切换窗口模式、分辨率与 VSync
```gdscript
# 切换无边框全屏或窗口化
App.display.set_window_mode(BaseDisplaySystem.WindowMode.WINDOWED)
App.display.set_resolution(Vector2i(1920, 1080), true)
App.display.set_vsync_mode(DisplayServer.VSYNC_ENABLED)
```

### 2. 获取画布层级与适配异形屏安全区
```gdscript
# 获取弹窗挂载层
var popup_layer := App.display.get_layer(BaseDisplaySystem.Layer.POPUP)

# 手动对自定义全屏容器应用异形屏安全区（锁定设计宽高比）
App.display.apply_safe_area($HUDRoot, true)
```
