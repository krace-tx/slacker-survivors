# Skill Wiki · 框架感知关键词检索矩阵 (Keyword Matrix)

> **Wiki 定位**：本矩阵为 Agent 编码前的首要检索索引。当用户需求、任务描述或代码改动意图命中以下关键词时，**必须**查阅对应文档，提取架构约束后再进行编码。

---

## 核心路由映射表

| 意图分类 | 触发关键词 | 必须查阅文档 | 核心约束与重点确认项 |
| :--- | :--- | :--- | :--- |
| **场景系统** | 新建场景、场景切换、push/pop/replace、关卡流转、BaseScene | `src/framework/modules/scene/_doc_scene.md` | 必须继承 `BaseScene`；重写生命周期钩子（`_on_enter(params: BaseParams = null)`、`_on_exit()`、`_on_pause()`、`_on_resume(params: BaseParams = null)`）；切场景统一调用 `App.scene`。 |
| **Display 与画布舞台** | 窗口模式、全屏、分辨率、拉伸比例、安全区适配、UI 视图根节点、画布层级、BaseView | `src/framework/modules/display/_doc_display.md` | 统一通过 `App.display` 掌管窗口模式、分辨率、安全区与六大 `CanvasLayer`；场景内 UI 根节点继承 `BaseView`（节点名称固定为 `UI`）。 |
| **自定义鼠标与光标系统** | 鼠标、光标、Cursor、准星、悬停变态、点击波、鼠标拖尾、粒子光标、手柄隐藏鼠标、窗口囚笼、App.cursor | `src/framework/modules/cursor/_doc_cursor.md` | 统一通过 `App.cursor` (`BaseCursorSystem`) 调度；内置 11 种语义形态、五层交互优先级漏斗（L5 覆盖栈 > L4 UI 自动嗅探 > L3 世界实体悬停 > L2 上下文基底 > L1 默认）、硬/软指针双擎与 `Layer.CURSOR (120)` 粒子伴生舞台。 |
| **弹窗与提示** | 弹窗、模态对话框、Toast、提示条、确认框、BaseDialog、DialogManager | `src/game/shared/component/dialog/dialog_manager.gd`<br>`src/game/shared/component/toast/toast_manager.gd` | 弹窗类必须继承 `BaseDialog`；通过 `DialogManager.open(...)` 打开；业务弹窗放置在 `features/<f>/view/component/<domain>/`；严禁在 `src/framework/` 写业务弹窗。 |
| **按钮与交互** | 按钮、点击反馈、音效震动、纹理按钮、BaseTextureButton | `src/game/shared/component/button/base_texture_button.gd` | 统一继承/使用 `BaseTextureButton`；基类已自动内置缩放动画、音效与触感震动；业务侧仅连接 `pressed` 信号，严禁手写补间与音效。 |
| **业务模块与数据模型** | 新建业务模块、Feature、Shared、MSVP、MES、Model、Engine、Service、Presenter、View 拆分、设置、GameSettings | `src/game/_doc_game.md`<br>`src/game/shared/_doc_shared.md`<br>`.agents/skills/framework-aware/references/module_and_doc_design.md` | 交互模块采用 **MSVP** (`model/service/view/presenter`)，纯算法模块采用 **MES** (`model/engine/service`)；`view/` 必须按 `scene/<domain>/` 与 `component/<domain>/` 单元文件夹（`1 .tscn + N .gd`）包裹；`shared/` 锁定 `model/service/component` 三支柱并遵循 2+ 模块复用铁律。 |
| **聚合根与总线** | 全局服务、App.xxx、服务定位器、Service Locator、事件总线、Bus.on_scoped、前后台挂起 | `src/framework/_doc_framework.md`<br>`src/framework/core/autoload/_doc_autoload.md` | 全局服务统一通过 `App` 访问（支持多调用方并发 `await App.bootstrap()` 合并等待）；跨模块解耦通信统一使用 `Bus.emit(...)` / `Bus.on_scoped(...)`。 |
| **启动与运行时** | 启动流程、FrameworkRuntime、RuntimeManifest、RuntimeServiceHost、RuntimeState、BootstrapScene、Splash、初始化 | `src/framework/core/runtime/_doc_runtime.md`<br>`src/game/bootstrap/_doc_bootstrap.md`<br>`src/game/features/splash/_doc_splash.md` | `FrameworkRuntime` 按 `RuntimeManifest` 拓扑顺序显式构造注入并调用 `_host.install(service)` 自动核对契约；引擎主场景固定为极简空入口 `BootstrapScene`，随后交接至 `features/splash/` (MSVP)。 |
| **网络通讯** | 网络请求、HTTP、API、Token、鉴权、请求签名、防重放、流式下载、App.net | `src/framework/modules/network/_doc_network.md` | 统一通过门面 `App.net` 调用；返回值使用标准 `Result` 包装；流式下载中转默认走 `FileUtils.USER_CACHE_NET_DIR`（`user://cache/net`）。 |
| **身份认证与登录** | 登录、鉴权、会话、Steam 登录、Apple 登录、Google Play 登录、游客登录、网关换票、JWT、Auth、App.auth | `src/framework/modules/auth/_doc_auth.md` | 统一通过门面 `App.auth` 调度；采用「平台凭据采集 (`AuthProviderAdapter`) × 会话核验签发 (`AuthSessionVerifier`)」二阶段正交架构；联动 `App.net` 401 单飞续期与 `App.clock` 校时。 |
| **持久化存储与本地沙盒 (`user://`)** | 本地存储、存档、读写磁盘、user://、沙盒目录、StorageItem、for_config、for_save、STORAGE_DOMAIN、云存档、Steam Cloud | `src/framework/modules/storage/_doc_storage.md` | 统一通过 `App.storage` 访问；本地沙盒执行 **2 层目录拓扑** (`user://config|saves|cache|tmp|logs/<domain_or_module>/`)；`src/game/` 严禁裸写 `"user://"`，仅允许 `*_model.gd` 使用 `StorageItem.for_config()` / `StorageItem.for_save()` 且 `STORAGE_DOMAIN` 必须对齐目录域（`R16`）。 |
| **音频与音效** | BGM、背景音乐、SFX、音效播放、音频淡入淡出、音画避让、App.audio | `src/framework/modules/audio/_doc_audio.md` | 统一通过门面 `App.audio` 调度；支持零协程同步热路径、BGM 交叉淡变与正交音画避让；严禁裸调 `AudioServer`。 |
| **视频播放** | 视频、CG、开场动画、Cutscene、MP4/OGV、视频缓存、App.video | `src/framework/modules/video/_doc_video.md` | 统一通过门面 `App.video` 调度；使用 `VideoPlayOptions` 链式配置；视频资产存放在 `src/assets/videos/<domain>/`，沙盒缓存归属 `user://cache/video`。 |
| **日志与诊断** | 打印日志、错误追踪、诊断、Logger、调试信息、崩溃日志、App.logger | `src/framework/modules/logger/_doc_logger.md` | 统一使用 `App.logger`（`debug/info/warn/error`）；必须带模块 Tag；严禁在 `src/` 代码中残留原生 `print()`（`R13`）。 |
| **多语言本地化** | 多语言、国际化、翻译、Locale、文案切换、App.locale | `src/framework/modules/locale/_doc_locale.md` | 统一通过 `App.locale` 管理；文本通过字典键映射，支持动态占位符格式化。 |
| **输入与键位映射** | 输入、键盘映射、手柄、改键、组合键、按键提示、摇杆死区、Input、InputMap、App.input | `src/framework/modules/input/_doc_input.md` | 统一通过 `App.input` 访问；支持键鼠/手柄双轨双槽隔离、`InputChord` 组合键消费、二段式免勾选交互录制与增量序列化；严禁直接调用 `InputMap.action_erase_events()`。 |
| **环境与配置** | 环境变量、运行环境、Debug/Release 判定、渠道参数、BaseEnvProfile、App.env | `src/framework/modules/env/_doc_env.md` | 统一通过 `App.env` 读取；隔离开发机环境与线上生产配置。 |
| **权威时钟与校时** | 权威时钟、防作弊时间、服务器时间戳校准、单调时钟、Clock、App.clock | `src/framework/modules/clock/_doc_clock.md` | 统一通过 `App.clock` 获取权威时间戳（`now` / `now_msec`）与单调时钟（`monotonic_msec`）；纯字符串格式化使用 `TimeUtils`。 |
| **参数契约实体** | 数据传参、参数对象、序列化、契约实体、DTO、BaseParams | `src/framework/infra/param/_doc_param.md` | 统一继承 `BaseParams`（位于单数路径 `src/framework/infra/param/`，`R02`）；内置反射序列化 `to_dict()` 与 `from_dict()`。 |
| **预算缓存与防抖调度** | 内存缓存、LRU、TTL、BudgetCache、冷却调度、防抖、节流、CooldownScheduler | `src/framework/infra/cache/_doc_cache.md`<br>`src/framework/infra/scheduler/_doc_scheduler.md` | 容量/水位/TTL 缓存统一使用 `BudgetCache`；高频异步冷却合并与串行互斥统一使用 `CooldownScheduler`。 |
| **模块标准、依赖治理与文档编写** | 新增框架模块、模块依赖、REQUIRED_MODULES、12维规范、编写文档、_doc_*.md | `src/framework/_doc_module_standard.md`<br>`.agents/skills/framework-aware/references/module_and_doc_design.md` | 模块内部严禁调用 `App.xxx`（`R08`）；必须声明 `MODULE_ID` / `REQUIRED_MODULES` / `OPTIONAL_MODULES`（`R09`）并遵循 12 维设计文档规范。 |
| **异步任务与并发编排** | 异步任务、并发 gather、竞态 race、超时取消、TaskScope、CancellationToken、防 UAF 等待 | `src/framework/infra/async/_doc_async.md` | 统一使用 `BaseScene.task_scope` / `BaseView.task_scope`（`run` / `gather` / `race` / `sleep`）或 `TaskScope.wait(node, sec)`；全链路返回 `Result` 并支持 `CancellationToken`。 |
| **Spine 骨骼动画与池化** | Spine、骨骼动画、SpineSprite、SpineController、SpinePool、骨骼预热、分频错峰 | `src/framework/infra/spine/_doc_spine.md` | 统一使用 `src/framework/infra/spine/` 下的 `SpineController` 与 `SpinePool`（享元对象池、视口内真预热与 30FPS 奇偶帧错峰步进）；严禁使用已废弃的 `SpineUtils`（`R11`）。 |
| **Shader 与渲染管线预热** | Shader、着色器预加载、材质预热、PSO 编译、ShaderWarmer、ShaderWarmupConfig | `src/framework/infra/shader/_doc_shader.md` | 统一使用 `src/framework/infra/shader/` 下的 `ShaderWarmer` 与 `ShaderWarmupConfig`。 |
| **状态机与行为树 AI 内核** | 状态机、FSM、HFSM、StateMachine、行为树、BT、BTTree、BTBuilder、BTCompiler、AI 决策、黑板、BTBlackboard | `src/framework/infra/fsm/_doc_fsm.md`<br>`src/framework/infra/bt/_doc_bt.md` | 统一使用 `src/framework/infra/fsm/` 与 `src/framework/infra/bt/`；遵循 100% `RefCounted` 与享元无状态节点铁律。 |
| **通用工具体系** | 节点操作、文件操作、沙盒目录常量、加解密、签名、HMAC、AES、压缩、编解码、时间格式化、UUID、坐标计算 | `src/framework/util/_doc_util.md` | 优先使用二级分类全局工具类（`NodeUtils`, `FileUtils`, `CryptoUtils`, `ResourceCodecUtils`, `FileCodecUtils`, `TimeUtils`, `CoordUtils` 等），直接使用全局 `class_name`（禁止 `preload` 起别名，`R15`）。 |
| **结果与错误处理** | Result、错误返回、FrameworkError、err_code、err_ex、is_ok/is_err | `src/framework/core/_doc_core.md`<br>`src/framework/core/contracts/_doc_contract.md` | 涉及失败可能性的核心操作统一返回 `Result`；错误包装为 `FrameworkError`，禁止静默吞没错误。 |
| **功能测试与原型验证** | 功能测试、测试场景、原型验证、src/test | `src/test/_doc_test.md` | 按单数被测功能域建立 `src/test/<feature_name>/`；正式代码严禁引用 `src/test/`（`R07`）。 |
| **Godot 设计与编码规范** | 编码规范、代码风格、命名规范、静态类型、Variant 解包、脚本结构、性能红线、注释规范 | `docs/godot_coding_standards.md` | 遵循 `Node` / `RefCounted` / `Resource` 选型第一性原理、单复数黄金法则、100% 显式静态类型注解、`StringName` 拘留池、文件 `#region` 声明顺序与 5 大防卡顿性能红线。 |
| **美术与媒体资产** | 资产、素材、贴图、图标、按钮图、精灵、序列帧、Spine 文件、模型、glb、音效文件、BGM 文件、字体、着色器、材质、资源命名 | `src/assets/_doc_assets.md` | 目录 `<媒介容器>/<架构域>/[<分组>/]`（架构域 = `shared` 或与 Feature 同名）；文件名 `<prefix>_<domain>_<subject>[_<state>][_<index>]` 全小写且域段 == 目录域；Feature 仅引用自身域与 `shared/` 资产（`R14`）。 |
| **配置与数据资源架构** | Resource、.tres、配置资源、数据表、静态定义、关卡编排、预设、envs、locales、presets、tables、defs、stages | `src/resources/_doc_resources.md` | 按六大生命周期与职责容器（`envs/`、`locales/`、`presets/`、`tables/`、`defs/`、`stages/`）存放 `.tres/.res/.csv`；禁止在运行期原地修改 `.tres` 静态定义。 |

---

## 路由命中检索规则

1. **单任务多命中**：若任务同时涉及“新建关卡场景”、“添加设置存档”与“编写模块文档”，应同时查阅 `_doc_scene.md`、`_doc_storage.md` 与 `module_and_doc_design.md`。
2. **文档版本优先级**：始终以本地代码库中最新的 `_doc_*.md` 文档规范为准，切勿凭历史经验或过时记忆臆断。
3. **未收录业务模块**：若操作涉及具体业务切片（如 `src/game/features/<feature>/`），同步查阅对应业务模块的 `_doc_<feature>.md`。
