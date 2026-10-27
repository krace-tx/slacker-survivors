# 08 · 设置系统 (Settings)

> **模块定位**：全生命周期随处可呼出的系统偏好弹窗（`SettingsDialog extends BaseDialog`，挂载于 `POPUP` 层）。
> **架构复用**：底层数据模型 [`GameSettingsModel`](../../src/game/shared/model/save/game_settings_model.gd) 与硬件控制服务 [`GameSettingsService`](../../src/game/shared/service/settings/game_settings_service.gd) **已在 `src/game/shared/` 完整实现**；本模块仅专注构建 UI 交互表现层，严禁重复造轮子。

---

## 一、 跨场景呼出与上下文规则

- **三大唤起入口**：`03_login`（右上快捷栏）、`04_lobby`（主菜单/右上快捷栏）、`07_gameplay`（在 `PauseDialog` 之上通过 `DialogManager.open()` 叠栈弹出，按 `ESC` 或手柄 `B` 逐层退栈归还焦点）。
- **场景差异裁剪**：局内打开设置时，若某项极端配置（如切换语言导致动态拼接战斗日志重置、或退出当前账号）不宜热改，自动置灰并气泡提示“请返回大厅后修改”；分辨率、音量、改键、震动等 95% 选项支持**局内实时热生效**。

---

## 二、 五大标准页签与核心功能契约

| 页签 | 配置项清单 | 底层对接门面与交互铁律 |
| :--- | :--- | :--- |
| **1. 显示 (`Display`)** | 显示器选择、窗口模式（窗口/无边框/全屏/独占全屏）、分辨率、垂直同步（VSync）、前台帧率上限、后台失焦降帧、安全区缩放、锁定设计宽高比 | 对接 `GameSettingsService` ➔ `App.display`。<br>**必选保护**：切换窗口模式或分辨率时，必须启用 **15 秒确认倒计时事务**（`begin_display_transaction` ➔ 确认 `commit` / 超时黑屏自动 `rollback`）。 |
| **2. 画质 (`Graphics`)** | 画质总预设（`LOW / MEDIUM / HIGH / ULTRA / CUSTOM`）、渲染缩放比例、2D/3D MSAA、屏幕空间抗锯齿、阴影质量、特效粒子密度 | 切换预设档位一键展开子项；玩家手动微调任一单项时，预设下拉框自动切为 `CUSTOM`。 |
| **3. 音频 (`Audio`)** | 主音量、BGM、SFX、语音（VOX）、环境音（AMB）五路滑块 + 独立静音开关 + **切后台自动静音** | 对接 `App.audio`。<br>**防磁盘抖动铁律**：拖动滑块时传 `auto_save = false` 实时听音反馈，仅在滑块 `drag_ended` 松手或关窗时调用一次 `save_async()` 落盘。 |
| **4. 操控 (`Control`)** | **键鼠 / 手柄双轨双槽（主/副键）交互式改键**、手柄摇杆死区、鼠标灵敏度、震动开关与强度 | 对接 `App.input` 与 `App.haptic`。<br>• 改键调用 `rebind_interactive_async()` 支持单键与 `Shift+Q` / `LB+Y` 组合键免勾选录制，默认采用 `SWAP` 互换冲突策略；<br>• 支持单设备轨道独立「恢复默认键位」，改键绝不洗掉另一设备按键。 |
| **5. 通用 (`General`)** | 游戏语言（`App.locale` 即时热切）、当前账号与 Steam Cloud 同步状态展示、**打开本地日志/存档目录**（PC 排障必备）、一键恢复当前页默认 | PC/Steam 端提供「打开日志目录」按钮（定位 `user://logs/`），极大降低线上玩家反馈 Bug 的沟通成本。 |

---

## 三、 Steam 多设备隔离铁律（防跨设备污染）

- **设备配置严禁上云**：`GameSettingsModel` 固定通过 `StorageItem.for_config(&"shared", "game_settings", ...)` 落盘至 `user://config/shared/game_settings.json`（读写策略锁定 `LOCAL_ONLY`）。
- **核心原因**：确保玩家在 **PC 台式机（4K 独占全屏 + 高画质）** 与 **Steam Deck 掌机（1280×800 无边框 + 中画质 + 60Hz 锁帧）** 切换游玩同一账号时，各自的硬件显示与画质配置互不覆盖污染。

---

## 四、 工程架构与契约映射 (`MSVP`)

- **共享层内核（已就绪，直接调用）**：
  - `src/game/shared/model/save/game_settings_model.gd`（及 `data/*_settings_data.gd` 五大子数据块）
  - `src/game/shared/service/settings/game_settings_service.gd`
- **业务视图切片落点**：`src/game/features/settings/`
  - `model/`：`SettingsDialogParams` (`BaseParams`，如指定初始激活页签、是否处于局内受限上下文 `is_in_gameplay`)。
  - `presenter/`：`SettingsPresenter`（绑定五大页签控件事件 ➔ 调用 `GameSettingsService` / `App.input` API；处理 15 秒切屏回滚确认框状态）。
  - `view/`：
    - `component/settings_dialog/`：`SettingsDialog` (`extends BaseDialog`) 主框架与页签导航。
    - `component/tabs/`：按职责拆分的五个子面板预制体（`DisplayTabPanel`、`GraphicsTabPanel`、`AudioTabPanel`、`ControlTabPanel`、`GeneralTabPanel`）及 `DisplayConfirmDialog`（15 秒回滚确认小弹窗）。
