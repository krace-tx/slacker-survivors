# Skill Wiki · 框架感知关键词检索矩阵 (Keyword Matrix)

> **Wiki 定位**：本矩阵为 Agent 编码前的首要检索索引。当用户需求、任务描述或代码改动意图命中以下关键词时，**必须**查阅对应文档，提取架构约束后再进行编码。

---

## 核心路由映射表

| 意图分类 | 触发关键词 | 必须查阅文档 | 核心约束与重点确认项 |
| :--- | :--- | :--- | :--- |
| **场景系统** | 新建场景、场景切换、push/pop/replace、关卡流转 | `src/framework/modules/scene/_doc_scene.md` | 必须继承 `BaseScene`；重写生命周期钩子（`_on_enter`、`_on_exit`、`_on_pause`、`_on_resume`）；切场景统一调用 `App.scene`。 |
| **Display 与画布舞台** | 窗口模式、全屏、分辨率、拉伸比例、安全区适配、UI 视图根节点、画布层级 | `src/framework/modules/display/_doc_display.md` | 统一通过 `App.display` 掌管窗口模式、分辨率、安全区与五大 `CanvasLayer`；场景内 UI 根节点继承 `BaseView`（名称固定为 `UI`）。 |
| **弹窗与提示** | 弹窗、模态对话框、Toast、提示条、确认框 | `src/game/shared/component/dialog/dialog_manager.gd`<br>`src/game/shared/component/toast/toast_manager.gd` | 弹窗类必须继承 `BaseDialog`；通过 `DialogManager.open(...)` 打开；严禁在 framework 层写业务弹窗。 |
| **按钮与交互** | 按钮、点击反馈、音效震动、纹理按钮 | `src/game/shared/component/button/base_texture_button.gd` | 统一继承/使用 `BaseTextureButton`；基类已自动内置缩放动画、音效与触感震动；业务侧仅连接 `pressed` 信号，严禁手写补间与音效。 |
| **业务模块与数据模型** | 新建业务模块、Feature、Shared、MSVP、MES、Model、Engine、Service、Presenter、设置、GameSettings | `src/game/_doc_game.md`<br>`src/game/shared/_doc_shared.md` | 交互模块采用 **MSVP** (`model/service/view/presenter`)，纯算法模块采用 **MES** (`model/engine/service`)；`src/game/shared/` 采用 `model/`、`service/`、`component/` 三支柱二级子域结构并遵循 2+ 模块引用准入铁律。 |
| **聚合根与总线** | 全局服务、App.xxx、服务定位器、Service Locator、事件总线、Bus.on_scoped | `src/framework/_doc_framework.md`<br>`src/framework/core/autoload/_doc_autoload.md` | 全局单例统一通过 `App` 访问；跨模块解耦通信统一使用全局事件总线 `Bus.emit(...)` / `Bus.on_scoped(...)`。 |
| **启动与运行时** | 启动流程、FrameworkRuntime、BootstrapScene、Splash、初始化、加载阶段、Boot | `src/framework/core/runtime/_doc_runtime.md`<br>`src/game/bootstrap/_doc_bootstrap.md`<br>`src/game/features/splash/_doc_splash.md` | 引擎主场景固定为极简空入口 `BootstrapScene`（完成 `App.bootstrap()` 与 `GameSettingsService.load_and_apply()`），随后移交至 `src/game/features/splash/` (MSVP) 执行加权业务启动管线。 |
| **网络通讯** | 网络请求、HTTP、API、Token、鉴权、请求签名、防重放、后端通信 | `src/framework/modules/network/_doc_network.md` | 统一通过门面 `App.net` 调用；返回值使用标准 `Result` 包装；支持 `set_request_signing` HMAC-SHA256 签名与 401 单飞刷新。 |
| **持久化存储** | 本地存储、存档、读写磁盘、序列化、加密存档、防拷档、偏好设置 | `src/framework/modules/storage/_doc_storage.md` | 统一通过门面 `App.storage` 访问；支持 `ZSTD 压缩 + AES-256 加密` 正交管线、`with_device_encryption` 设备绑定与 `.bak` 容错自愈；严禁直接使用底层 `FileAccess` 硬编码业务存档。 |
| **音频与音效** | BGM、背景音乐、SFX、音效播放、音频淡入淡出 | `src/framework/modules/audio/_doc_audio.md` | 统一通过门面 `App.audio` 调度；支持音频总线分组与自动音量避让；严禁随意调用原生 `AudioServer` 破坏管理。 |
| **视频播放** | 视频、CG、开场动画、Cutscene、MP4/OGV | `src/framework/modules/video/_doc_video.md` | 统一通过门面 `App.video` 调度；使用 `VideoPlayOptions` 链式配置；资源统一存放在 `src/assets/videos/`。 |
| **日志与诊断** | 打印日志、错误追踪、诊断、Logger、调试信息 | `src/framework/modules/logger/_doc_logger.md` | 统一使用 `App.logger`（`debug/info/warn/error`）；必须带模块 Tag；严禁在业务和框架代码中残留原生 `print()`。 |
| **多语言本地化** | 多语言、国际化、翻译、Locale、文案切换 | `src/framework/modules/locale/_doc_locale.md` | 统一通过 `App.locale` 管理；文本通过字典键映射，支持动态占位符格式化。 |
| **输入与键位映射** | 输入、键盘映射、手柄、改键、组合键、按键提示、摇杆死区、Input、InputMap | `src/framework/modules/input/_doc_input.md` | 统一通过 `App.input` 访问；支持键鼠/手柄双轨双槽隔离、`InputChord` 组合键消费、二段式免勾选交互录制与增量序列化；严禁直接调用 `InputMap.action_erase_events()` 破坏双轨绑定。 |
| **环境与配置** | 环境变量、运行环境、Debug/Release 判定、渠道参数 | `src/framework/modules/env/_doc_env.md` | 统一通过 `App.env` 读取；隔离开发机环境与线上生产配置。 |
| **权威时钟与校时** | 权威时钟、防作弊时间、服务器时间戳校准、单调时钟、Clock、App.clock | `src/framework/modules/clock/_doc_clock.md` | 统一通过 `App.clock` 获取权威时间戳（`now` / `now_msec`）与单调时钟（`monotonic_msec`）；纯字符串格式化使用 `TimeUtils`。 |
| **参数契约实体** | 数据传参、参数对象、序列化、契约实体、DTO | `src/framework/infra/param/_doc_param.md` | 统一继承 `BaseParams`；内置 `to_dict()` 与 `from_dict()` 映射；严禁使用拼装字典裸传关键参数。 |
| **预算缓存与防抖调度** | 内存缓存、LRU、TTL、BudgetCache、冷却调度、防抖、节流、CooldownScheduler | `src/framework/infra/cache/_doc_cache.md`<br>`src/framework/infra/scheduler/_doc_scheduler.md` | 容量/水位/TTL 缓存统一使用 `BudgetCache`；高频异步冷却合并与串行互斥统一使用 `CooldownScheduler`。 |
| **模块标准与依赖治理** | 新增框架模块、模块依赖、REQUIRED_MODULES、12维规范 | `src/framework/_doc_module_standard.md` | 模块内部严禁调用 `App.xxx`；必须声明 `MODULE_ID` / `REQUIRED_MODULES` / `OPTIONAL_MODULES` 并由 `FrameworkRuntime` 显式注入。 |
| **异步任务与并发编排** | 异步任务、并发 gather、竞态 race、超时取消、TaskScope、CancellationToken、防 UAF 等待 | `src/framework/infra/async/_doc_async.md` | 统一使用 `BaseScene.task_scope` / `BaseView.task_scope`（`run` / `gather` / `race` / `sleep`）或 `TaskScope.wait(node, sec)`；全链路返回 `Result` 并支持 `CancellationToken`。 |
| **Spine 骨骼动画与池化** | Spine、骨骼动画、SpineSprite、SpineController、SpinePool、骨骼预热、分频错峰 | `src/framework/infra/spine/_doc_spine.md` | 统一使用 `src/framework/infra/spine/` 下的 `SpineController`（流式链式控制与租约句柄）与 `SpinePool`（享元对象池、视口内真预热与 30FPS 奇偶帧错峰步进）；严禁使用已废弃的 `SpineUtils`。 |
| **通用工具体系** | 节点遍历、文件操作、加解密、签名、HMAC、AES、压缩、编解码、时间格式化、UUID、坐标计算 | `src/framework/util/_doc_util.md` | 优先使用各二级分类全局工具类（`NodeUtils`, `FileUtils`, `CryptoUtils`, `ResourceCodecUtils`, `FileCodecUtils`, `TimeUtils`, `CoordUtils` 等），严禁重复造轮子。 |
| **结果与错误处理** | Result、错误返回、FrameworkError、err_code、err_ex、is_ok/is_err | `src/framework/core/_doc_core.md`<br>`src/framework/core/contracts/_doc_contract.md` | 涉及失败可能性的核心操作统一返回 `Result`；错误包装为 `FrameworkError`，禁止通过静默返回 null 或裸异常阻断流程。 |
| **功能测试与原型验证** | 功能测试、测试场景、原型验证、src/test | `src/test/_doc_test.md` | 按单数被测功能域建立 `src/test/<feature_name>/`；轻量测试直接放 `BaseScene` 测试场景，复杂测试对齐 **MSVP / MES** 子目录分层；支持按 `F6` 独立运行；正式代码严禁引用 `src/test/`。 |
| **Godot 设计与编码规范** | 编码规范、代码风格、命名规范、静态类型、脚本结构、性能红线 | `docs/godot_coding_standards.md` | 遵循 `Node` / `RefCounted` / `Resource` 选型第一性原理、单复数黄金法则、100% 显式静态类型注解、`StringName` 拘留池、文件 `#region` 声明顺序与 5 大防卡顿性能红线。 |

---

## 路由命中检索规则

1. **单任务多命中**：若任务同时涉及“新建关卡场景”与“添加返回按钮”，应同时查阅 `_doc_scene.md` 与 `_doc_display.md`。
2. **文档版本优先级**：始终以本地代码库中最新的 `_doc_*.md` 文档规范为准，切勿凭历史经验或过时记忆臆断。
3. **未收录模块**：若操作涉及纯业务专属逻辑（如 `src/game/features/battle/combat_calculator.gd`），查阅对应业务模块的文档（如 `src/game/features/battle/_doc_battle.md`）。
