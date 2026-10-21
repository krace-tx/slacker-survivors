# Game · Shared (跨模块业务共享内核)

> 游戏业务层全模块通用的共享内核（Shared Kernel）：承载跨多个 `features` 垂直模块共同依赖的全局常量、领域事件契约、共享持久化领域模型与通用业务交互控件。

```text
src/game/shared/
├── _doc_shared.md                  # 本文档
├── constants/
│   └── game_constants.gd           # 全局静态场景路径、存档 Key、音频分组常量 (GameConstants)
├── events/
│   └── game_events.gd              # 跨模块解耦事件名称常量 (GameEvents，配合 Bus.emit / Bus.on)
├── models/                         # 跨模块共享核心领域模型 (遵循 model/ 架构后缀规范)
│   ├── player_profile_model.gd     # 玩家全局持久化档案模型 (PlayerProfileModel，继承 BaseParams)
│   └── game_settings_model.gd      # 游戏全局偏好设置模型 (GameSettingsModel，继承 BaseParams)
└── components/                     # 业务通用可复用控件库 (直接扁平化管理，无多余二级目录)
	├── base_texture_button.gd      # 通用贴图按钮 (缩放/音效/震动/滑动消抖中继)
	├── base_dialog.gd              # 模态弹窗业务基类 (进退场补间/点击背景遮罩自闭)
	├── dialog_manager.gd           # 模态弹窗调度器 (暗色遮罩/LIFO堆栈/返回键监听)
	└── toast_manager.gd            # 轻量飘字提示组件 (居中浮动与渐变销毁)
```

---

## 核心设计原则

1. **为什么 `shared/` 不存放 MSVP 基类？**
   - **MSVP (`model/service/view/presenter`)** 与 **MES (`model/engine/service`)** 是 `src/game/features/<feature>/` 下垂直业务模块的**子目录组织范式**，而非靠继承空壳基类来约束（详见 [`_doc_game.md`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/game/_doc_game.md)）。
   - `shared/` 仅存放**真正具备跨模块业务复用价值的实体、常量、事件与组件**，拒绝无业务意义的过度抽象。
2. **共享领域模型（`models/`）强类型化**：
   - 跨模块共享的持久化数据（如 [`PlayerProfileModel`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/game/shared/models/player_profile_model.gd)、[`GameSettingsModel`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/game/shared/models/game_settings_model.gd)）统一继承 [`BaseParams`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/infra/param/base_params.gd)，消除全工程读写裸 `Dictionary` 的隐患，并通过命名后缀明确其领域语义。
3. **通用组件扁平化（`components/`）**：
   - 业务通用控件（[`BaseDialog`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/game/shared/components/base_dialog.gd)、[`DialogManager`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/game/shared/components/dialog_manager.gd)、[`ToastManager`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/game/shared/components/toast_manager.gd)、[`BaseTextureButton`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/game/shared/components/base_texture_button.gd)）直接收敛于 `src/game/shared/components/` 下，去除多余的 `ui/` 二级目录层级。
4. **跨模块弱依赖（`events/`）**：
   - 各个业务 Feature 之间杜绝直接交叉引用内部类，统一通过 `Bus.emit(GameEvents.XXX, payload)` 与 `Bus.on(GameEvents.XXX, callback)` 异步解耦通讯。
