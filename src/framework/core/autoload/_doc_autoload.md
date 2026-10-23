# Framework · Core · Autoload (全局服务聚合根与领域事件总线)

> `autoload/` 仅保存 Godot 工程在 `project.godot` 中注册的两个全局入口（[`App`](app.gd) 与 [`EventBus` / `Bus`](event_bus.gd)）。
> 严格遵循**「门面与装配分离」**原则：Autoload 脚本自身绝不直接实例化任何具体子系统实现，全部依赖注入与生命周期编排均委托给唯一组合根 [`FrameworkRuntime`](../runtime/framework_runtime.gd)。

```text
src/framework/core/autoload/
├── _doc_autoload.md    # 本文档
├── app.gd              # 全局服务定位器与系统级生命周期入口 (Autoload: App)
└── event_bus.gd        # 全局双轨领域事件总线 (Autoload: Bus)
```

---

## 一、 `App` 全局服务聚合根 (`app.gd`)

### 1. 14 大核心子系统强类型门面

业务层（`src/game/`）统一通过 `App.<service>` 面向抽象基类（`Base*`）编程；框架实现层（`src/framework/modules/`、`infra/`、`util/`）**严禁**调用 `App.xxx`，必须通过构造函数显式依赖注入。

| 访问属性 | 强类型抽象门面 | 所属领域与核心职责 |
| :--- | :--- | :--- |
| `App.env` | [`BaseRuntimeEnvironment`](../../modules/env/base_runtime_environment.gd) | 运行环境（Local/Emulator/Dev/Test/Staging/Prod）只读快照与多环境 `BaseEnvProfile` 策略 |
| `App.logger` | [`BaseFrameworkLogger`](../../modules/logger/base_framework_logger.gd) | 分级日志过滤、Tag 染色输出与 1000 条环形内存缓冲（`dump()`） |
| `App.clock` | [`BaseClockSystem`](../../modules/clock/base_clock_system.gd) | 防作弊本地单调时钟与服务器 Unix 时间戳对齐校准 |
| `App.asset` | [`BaseAssetSystem`](../../modules/asset/base_asset_system.gd) | 同步缓存直通（`get_cached`）、信号驱动并发加载合并、双阶段预加载与 LRU 预算缓存 |
| `App.input` | [`BaseInputSystem`](../../modules/input/base_input_system.gd) | 键鼠/手柄双轨双槽隔离映射、`InputChord` 组合键优先消费、上下文栈与二段式免勾选录制 |
| `App.haptic` | [`BaseHapticFeedback`](../../modules/haptic/base_haptic_feedback.gd) | 手机/手柄/PC 三端差异化触觉反馈翻译、高优防打断、怪潮节流与镜头震屏脉冲信号 |
| `App.net` | [`BaseNetworkClient`](../../modules/network/base_network_client.gd) | 有界并发 HTTP 队列、抖动指数退避重试、401 单飞刷新与 `.tmp` 原子文件下载 |
| `App.auth` | [`BaseAuthSystem`](../../modules/auth/base_auth_system.gd) | 跨平台身份取证（Steam/Apple/Google/Guest）、单机/网关双模会话签发与 401 令牌续期 |
| `App.storage` | [`BaseStorageSystem`](../../modules/storage/base_storage_system.gd) | L1 内存 + L2 磁盘（`.tmp/.bak` 原子自愈 + ZSTD + AES-256）+ L3 远端（HTTP & Steam Cloud）三级存储 |
| `App.locale` | [`BaseLocalizationSystem`](../../modules/locale/base_localization_system.gd) | 多语言区域切换、`TranslationServer` 适配与缺省回退保底 |
| `App.scene` | [`BaseSceneRouter`](../../modules/scene/base_scene_router.gd) | 顶层场景栈路由（`bind` / `replace` / `push` / `pop`）与流式视觉转场 |
| `App.display` | [`BaseDisplaySystem`](../../modules/display/base_display_system.gd) | 窗口/全屏状态机、分辨率钳制、异形屏安全区逆矩阵投影、渲染抗锯齿与五大 `CanvasLayer` |
| `App.audio` | [`BaseAudioSystem`](../../modules/audio/base_audio_system.gd) | 零协程缓存热路径、BGM 双轨交叉淡入淡出、正交音画避让（`duck_bgm`）与 16 通道 SFX 池 |
| `App.video` | [`BaseVideoPlayer`](../../modules/video/base_video_player.gd) | 跨平台视频播放控制（桌面 FFmpeg / 移动原生 ExoPlayer & AVPlayer / 引擎 Theora 保底） |

### 2. 内核启动守卫与 OS 生命周期接管

1. **单飞幂等启动（`App.bootstrap(on_progress)`）**：
   - 支持多个调用方安全并发 `await App.bootstrap()`，内部通过 `_booting` 状态锁合并等待，绝不重复创建 `FrameworkRuntime`。
   - **独立场景 `F6` 调试保底（`_ensure_standalone_bootstrap`）**：在编辑器中直接按 `F6` 运行任意非 `BootstrapScene` 的业务或测试场景（如 `input_test.tscn`）时，自动延迟拉起 `bootstrap()` 并将当前 `BaseScene` 绑定至 `App.scene`。
2. **OS 系统通知统一拦截（`_notification`）**：
   - **优雅退出拦截**：在 `_ready()` 中设置 `get_tree().set_auto_accept_quit(false)`；收到 `NOTIFICATION_WM_CLOSE_REQUEST` 时触发 `_on_app_quit()`，等待 `await _runtime.shutdown_async()` 完成进行中的磁盘/云端存档落盘并逆序销毁服务后，再调用 `get_tree().quit()`。
   - **前后台与窗口焦点**：统一收口移动端 `NOTIFICATION_APPLICATION_PAUSED / RESUMED` 与桌面端 `NOTIFICATION_WM_WINDOW_FOCUS_OUT / IN`，自动防抖并广播 `Bus.app_paused` / `Bus.app_resumed`。
   - **硬件返回与低内存保护**：拦截 `NOTIFICATION_WM_GO_BACK_REQUEST` 广播 `Bus.app_back_pressed`；拦截 `NOTIFICATION_OS_MEMORY_WARNING` 自动调用 `App.asset.clear()` 释放非钉住缓存。
3. **运行时诊断快照（`App.get_runtime_diagnostics()`）**：
   - 随时返回当前 `FrameworkRuntime` 状态枚举名、已安装服务列表及各模块启动耗时毫秒表（`boot_metrics_ms`）。

---

## 二、 `EventBus` / `Bus` 全局领域事件总线 (`event_bus.gd`)

> **核心铁律**：`Bus` **只广播已经发生的客观事实（Domain Facts）**，绝不承载需要返回值或失败感知的控制命令（执行命令请直接调用 `App.xxx` 或业务 `Service`）。

### 1. 双轨事件架构

| 轨道类型 | 调用方式 | 适用范围 | 清单 / 特性 |
| :--- | :--- | :--- | :--- |
| **轨道 A：框架系统级信号**<br>(Built-in Signals) | `Bus.<signal>.connect(...)` | 由 Framework 核心模块发出的底层状态事实 | • `app_paused` / `app_resumed` / `app_back_pressed`<br>• `locale_changed`<br>• `input_device_changed(device_type, joy_brand)`<br>• `input_bindings_changed(action)`<br>• `joypad_connection_changed(device_id, connected)`<br>• `scene_changed(path)` / `scene_change_failed(path)` |
| **轨道 B：业务跨模块主题**<br>(Dynamic Pub/Sub) | `Bus.on(...)`<br>`Bus.on_scoped(...)`<br>`Bus.off(...)`<br>`Bus.emit(...)` | `src/game/` 各垂直业务模块间的解耦广播（配合各业务 `Service` 公开的 `EVENT_*` 常量） | • **作用域自动解绑（`on_scoped`）**：绑定宿主 `Node.tree_exiting` 信号，节点退树时自动 `off`，根除悬空回调泄漏<br>• **参数签名自适应**：回调既可写成无参 `func()` 也可写成单参 `func(payload)`<br>• **快照遍历与失效自洁**：派发前自动剔除已销毁对象的无效 `Callable`，并复制数组快照遍历防止回调内增删订阅引发错位<br>• **防死循环递归保护**：内置 `_MAX_RECURSION_DEPTH = 8`，拦截 `A -> B -> A` 无限事件环路 |

### 2. 使用范式

```gdscript
# 1. 订阅框架内置系统级信号
func _ready() -> void:
	Bus.app_paused.connect(_on_app_paused)
	Bus.input_device_changed.connect(_on_device_changed)

# 2. 在 UI 或场景节点中使用 on_scoped 订阅业务领域事件（节点销毁退树时自动解绑！）
	Bus.on_scoped(PlayerProfileService.EVENT_PROFILE_UPDATED, self, _on_profile_updated)

# 3. 广播跨模块领域事件（由 Service 层在状态变更后发出）
Bus.emit(PlayerProfileService.EVENT_PROFILE_UPDATED, {"profile": profile})
```
