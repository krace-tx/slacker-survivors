# Modules · Framework 模块层

Framework 的业务技术基建按四层架构划分：**模块名、公开门面、内部实现、底层适配器**。这样具有清晰类似操作系统的层次感。

```text
src/framework/modules/
├── env/          # 运行环境
├── logger/       # 日志与诊断
├── clock/        # 权威时钟
├── asset/        # 资源加载与缓存
├── storage/      # 内存/磁盘/远端存储
├── network/      # HTTP 通讯
├── scene/        # 场景栈与转场
├── ui/           # 全局 UI 分层与安全区适配
├── audio/        # BGM / SFX
├── locale/       # 多语言与区域
├── haptic/       # 触觉反馈
├── input/        # 键鼠/手柄双轨映射与复合键输入
└── video/        # 视频播放与插件桥接
```

---

## 一、 命名与组织规范

| 层次 | 职责定位 | 命名规则 | 示例 |
|---|---|---|---|
| **模块目录** | 单数表达垂直技术领域能力 | 单数名词 | `asset/`、`scene/`、`storage/`、`env/`、`input/` |
| **能力门面基类** | 系统对外契约与全量注释门面 | `base_<role>` / PascalCase | `base_storage_system.gd` (`BaseStorageSystem`), `base_input_system.gd` (`BaseInputSystem`) |
| **能力系统实现** | 完整运行能力入口 / 核心编排 | `<role>` / PascalCase | `storage_system.gd` (`StorageSystem`), `input_system.gd` (`InputSystem`) |
| **业务承载基类** | 业务扩展/继承基类 | `base_<entity>` | `base_scene.gd` (`BaseScene`), `base_view.gd` (`BaseView`) |
| **动作角色实现** | 专注特定行为的执行者 | `<action_role>` | `scene_router.gd` (`SceneRouter`), `network_client.gd` (`NetworkClient`), `framework_logger.gd` (`FrameworkLogger`), `haptic_feedback.gd` (`HapticFeedback`) |
| **公开契约/类型** | 跨层公开类型与枚举（脱离目录自解释） | `<feature>_<type>` | `storage_read_mode.gd` (`StorageReadMode`), `input_chord.gd` (`InputChord`) |
| **配置对象** | 跨环境/静态配置声明 | `<feature>_config` | `locale_config.gd` (`LocaleConfig`) |
| **状态机/栈** | 栈式导航与状态流转 | `<feature>_stack` | `scene_stack.gd` (SceneRouter 历史栈) |
| **队列** | 请求或任务调度 | `<feature>_queue` | `request_queue.gd` |
| **缓存** | 容量与过期策略 | `<feature>_cache` | `asset_cache.gd`, `storage_cache.gd` |
| **驱动** | 可替换存储或底层实现 | `<backend>_<domain>_driver` | `memory_storage_driver.gd`, `disk_storage_driver.gd` |
| **引擎适配器** | 隔离 Godot 原生 API 边界 | `<engine>_adapter` | `resource_loader_adapter.gd`, `translation_server_adapter.gd`, `input_map_adapter.gd` |

### 核心约束

1. **角色化语义命名（拒绝泛化的 Service）**：
   - 协调完整运行能力的模块采用 **System**（`AudioSystem`、`AssetSystem`、`DisplaySystem`、`StorageSystem`、`ClockSystem`、`LocalizationSystem`、`InputSystem`）。
   - 专注特定功能行为的模块采用具体 **角色名词**（`SceneRouter` 导航路由、`NetworkClient` 通讯客户端、`FrameworkLogger` 框架日志、`HapticFeedback` 震动反馈、`RuntimeEnvironment` 运行环境）。
   - 显示与视图继承基类明确职责：`BaseDisplaySystem`（显示设备与画布舞台门面）、`BaseView`（单个界面根节点，带安全区）；业务弹窗统一继承业务共享层 `BaseDialog`。
2. **`Base` 前缀约束**：
   - `Base` 仅用于对外暴露的抽象基类与契约（如 `BaseAudioSystem`、`BaseStorageSystem`、`BaseView`）。
   - 内部实现（`impl/`、`drivers/`）直接表达具体职责，绝不冠以 `BaseXxx`。
3. **架构职责四要素**：
   - **模块目录** 表达能力领域
   - **base_<role>.gd** 表达公开门面契约（全量方法注释）
   - **types/** 表达公开契约与枚举数据（脱离目录名自解释，严禁包含私有实现）
   - **impl/** 收敛私有实现与状态（外部不可见，严禁直接引用）

---

## 二、 模块结构一览

```text
env/
├── _doc_env.md
├── base_runtime_environment.gd
├── base_env_profile.gd
├── types/
│   └── env_type.gd
└── impl/
	└── runtime_environment.gd

logger/
├── _doc_logger.md
├── base_framework_logger.gd
├── types/
│   └── log_level.gd
└── impl/
	└── framework_logger.gd

clock/
├── _doc_clock.md
├── base_clock_system.gd
└── impl/
	└── clock_system.gd

asset/
├── _doc_asset.md
├── base_asset_system.gd
└── impl/
	├── asset_system.gd
	├── asset_cache.gd
	└── resource_loader_adapter.gd

storage/
├── _doc_storage.md
├── base_storage_system.gd
├── types/
│   ├── storage_item.gd
│   ├── storage_read_mode.gd
│   └── storage_write_mode.gd
└── impl/
	├── storage_system.gd
	├── storage_cache.gd
	└── drivers/
		├── storage_driver.gd
		├── memory_storage_driver.gd
		├── disk_storage_driver.gd
		└── remote_storage_driver.gd

network/
├── _doc_network.md
├── base_network_client.gd
├── types/
│   └── network_request.gd
└── impl/
	├── network_client.gd
	└── request_queue.gd

scene/
├── _doc_scene.md
├── base_scene_router.gd
├── base_scene.gd
├── types/
│   └── scene_transition_type.gd
└── impl/
	├── scene_router.gd
	├── scene_stack.gd
	└── scene_transition.gd

display/
├── _doc_display.md
├── base_display_system.gd
├── base_view.gd
└── impl/
	└── display_system.gd

audio/
├── _doc_audio.md
├── base_audio_system.gd
└── impl/
	├── audio_system.gd
	├── bgm_player.gd
	└── sfx_pool.gd

locale/
├── _doc_locale.md
├── base_localization_system.gd
├── types/
│   └── locale_config.gd
└── impl/
	├── localization_system.gd
	└── translation_server_adapter.gd

haptic/
├── _doc_haptic.md
├── base_haptic_feedback.gd
├── types/
│   └── haptic_intensity.gd
└── impl/
	└── haptic_feedback.gd

input/
├── _doc_input.md
├── base_input_system.gd
├── types/
│   ├── input_device_type.gd
│   ├── input_context_type.gd
│   ├── input_binding_slot.gd
│   ├── input_conflict_policy.gd
│   ├── input_error.gd
│   ├── input_chord.gd
│   └── input_glyph_info.gd
└── impl/
	├── input_system.gd
	├── input_device_tracker.gd
	├── input_rebind_capturer.gd
	└── input_map_adapter.gd

video/
├── _doc_video.md
├── base_video_player.gd
├── types/
│   ├── video_error.gd
│   ├── video_playback_state.gd
│   ├── video_play_options.gd
│   └── video_backend_type.gd
└── impl/
	├── video_player.gd
	├── components/
	│   └── video_cutscene_overlay.gd
	└── adapters/
		├── video_player_adapter.gd
		├── addon_video_adapter.gd
		├── native_mobile_video_adapter.gd
		└── engine_video_adapter.gd
```

子系统之间的实例化和依赖注入只允许出现在 `core/runtime/framework_runtime.gd`。业务代码通过 `App.xxx` 访问门面，严禁直接跨层创建实现或直接访问 `impl/`。
