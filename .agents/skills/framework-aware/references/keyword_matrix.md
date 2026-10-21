# Skill Wiki · 框架感知关键词检索矩阵 (Keyword Matrix)

> 📖 **Wiki 定位**：本矩阵为 Agent 编码前的首要检索索引。当用户需求、任务描述或代码改动意图命中以下关键词时，**必须**查阅对应文档，提取架构约束后再进行编码。

---

## 核心路由映射表

| 意图分类 | 触发关键词 | 必须查阅文档 | 核心约束与重点确认项 |
| :--- | :--- | :--- | :--- |
| **场景系统** | 新建场景、场景切换、push/pop/replace、关卡流转 | `src/framework/modules/scene/_doc_scene.md` | 必须继承 `BaseScene`；重写生命周期钩子（`_on_enter`、`_on_exit`、`_on_pause`、`_on_resume`）；切场景统一调用 `App.scene`。 |
| **UI 表现层** | UI 视图根节点、界面层级、UI 编排、安全区适配 | `src/framework/modules/ui/_doc_ui.md` | 场景内 UI 根节点必须继承 `BaseUIView`，节点名称固定为 `UI`；由 `BaseScene` 自动装载；仅负责引擎级视口挂载与过渡。 |
| **弹窗与提示** | 弹窗、模态对话框、Toast、提示条、确认框 | `src/game/shared/components/dialog_manager.gd`<br>`src/game/shared/components/toast_manager.gd` | 弹窗类必须继承 `BaseDialog`；通过 `DialogManager.open(...)` 打开；严禁在 framework 层写业务弹窗。 |
| **按钮与交互** | 按钮、点击反馈、音效震动、纹理按钮 | `src/game/shared/components/base_texture_button.gd` | 统一继承/使用 `BaseTextureButton`；基类已自动内置缩放动画、音效与触感震动；业务侧仅连接 `pressed` 信号，严禁手写补间与音效。 |
| **业务模块与数据模型** | 新建业务模块、Feature、MSVP、MES、Model、Engine、Service、Presenter | `src/game/_doc_game.md`<br>`src/game/shared/_doc_shared.md` | 交互模块采用 **MSVP** (`model/service/view/presenter`) 子目录，纯算法模块采用 **MES** (`model/engine/service`) 子目录；`model/` 内严格按 `*Config`、`*Model`、`*State`、`*Params`、`*Context`、`*VO` 后缀区分数据领域。 |
| **聚合根与总线** | 全局服务、App.xxx、服务定位器、Service Locator、事件总线 | `src/framework/_doc_framework.md` | 全局单例统一通过 `App` 访问；跨模块解耦通信统一使用全局事件总线 `Bus.emit(...)` / `Bus.on(...)`。 |
| **启动与运行时** | 启动流程、FrameworkRuntime、初始化、加载阶段、Boot | `src/framework/core/runtime/_doc_runtime.md` | 必须遵循 `FrameworkRuntime` 唯一组合根；按预定生命周期阶段推进加载；严禁私自绕过运行时乱序初始化。 |
| **网络通讯** | 网络请求、HTTP、API、Token、鉴权、后端通信 | `src/framework/modules/network/_doc_network.md` | 统一通过门面 `App.net` 调用；返回值使用标准 `Result` 包装；拦截器与 Token 刷新由网络驱动层透明接管。 |
| **持久化存储** | 本地存储、存档、读写磁盘、序列化、偏好设置 | `src/framework/modules/storage/_doc_storage.md` | 统一通过门面 `App.storage` 访问；支持自动加解密与容错校验；严禁直接使用底层 `FileAccess` 硬编码业务存档。 |
| **音频与音效** | BGM、背景音乐、SFX、音效播放、音频淡入淡出 | `src/framework/modules/audio/_doc_audio.md` | 统一通过门面 `App.audio` 调度；支持音频总线分组与自动音量避让；严禁随意调用原生 `AudioServer` 破坏管理。 |
| **视频播放** | 视频、CG、开场动画、Cutscene、MP4/OGV | `src/framework/modules/video/_doc_video.md` | 统一通过门面 `App.video` 调度；使用 `VideoPlayOptions` 链式配置；资源统一存放在 `src/assets/videos/`。 |
| **日志与诊断** | 打印日志、错误追踪、诊断、Logger、调试信息 | `src/framework/modules/logger/_doc_logger.md` | 统一使用 `App.logger`（`debug/info/warn/error`）；必须带模块 Tag；严禁在业务和框架代码中残留原生 `print()`。 |
| **多语言本地化** | 多语言、国际化、翻译、Locale、文案切换 | `src/framework/modules/locale/_doc_locale.md` | 统一通过 `App.locale` 管理；文本通过字典键映射，支持动态占位符格式化。 |
| **环境与配置** | 环境变量、运行环境、Debug/Release 判定、渠道参数 | `src/framework/modules/env/_doc_env.md` | 统一通过 `App.env` 读取；隔离开发机环境与线上生产配置。 |
| **参数契约实体** | 数据传参、参数对象、序列化、契约实体、DTO | `src/framework/infra/param/_doc_param.md` | 统一继承 `BaseParams`；内置 `to_dict()` 与 `from_dict()` 映射；严禁使用拼装字典裸传关键参数。 |
| **通用工具体系** | 节点遍历、文件操作、异步等待、时间格式化、UUID、坐标计算 | `src/framework/util/_doc_util.md` | 优先使用各二级分类全局工具类（`NodeUtils`, `FileUtils`, `AsyncUtils`, `TimeUtils`, `CoordUtils` 等），严禁重复造轮子。 |
| **结果与错误处理** | Result、错误返回、AppError、is_ok/is_err | `src/framework/core/_doc_core.md` | 涉及失败可能性的核心操作统一返回 `Result`；错误包装为 `AppError`，禁止通过静默返回 null 或裸异常阻断流程。 |

---

## 路由命中检索规则

1. **单任务多命中**：若任务同时涉及“新建关卡场景”与“添加返回按钮”，应同时查阅 `_doc_scene.md` 与 `_doc_ui.md`。
2. **文档版本优先级**：始终以本地代码库中最新的 `_doc_*.md` 文档规范为准，切勿凭历史经验或过时记忆臆断。
3. **未收录模块**：若操作涉及纯业务专属逻辑（如 `src/game/features/battle/combat_calculator.gd`），查阅对应业务模块的文档（如 `src/game/features/battle/_doc_battle.md`）。
