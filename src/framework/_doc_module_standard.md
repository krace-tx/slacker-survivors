# Framework · 模块标准与工程治理规范 (Module Standard & Governance)

> 本规范是 `src/framework/` 下所有核心模块的最高工程治理标准。
> 任何新增或演进的模块，必须满足本规范定义的**依赖治理规则、12 维设计契约、生命周期状态机与五大完成验收标准**。

---

## 一、 模块依赖治理规范 (Module Dependency Policy)

### 1. 四类依赖分级规则

| 依赖类型 | 典型示例 | 访问规则 |
|---|---|---|
| **Core 依赖** | [`Result`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/core/contracts/result.gd)、[`FrameworkError`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/core/contracts/framework_error.gd)、[`Bus`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/core/autoload/event_bus.gd) | 允许所有模块与基建直接使用 |
| **Infra / Util 依赖** | [`TaskScope`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/infra/async/task_scope.gd)、[`BudgetCache`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/infra/cache/budget_cache.gd)、[`BaseParams`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/infra/param/base_params.gd)、[`FileUtils`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/util/file/file_utils.gd) | 允许所有模块使用；`infra/` 与 `util/` 自身严禁反向依赖任何 `modules/` |
| **Module API 依赖** | `AudioSystem` 使用 `BaseAssetSystem` 公开门面 | **必须显式声明**在 `REQUIRED_MODULES` / `OPTIONAL_MODULES` 中，并由 [`FrameworkRuntime`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/core/runtime/framework_runtime.gd) 构造注入 |
| **Module Internal 依赖** | 其他模块或业务层直接引用某模块 `impl/` 下的类（如 `ResourceLoaderAdapter`、`DiskStorageDriver`） | **绝对禁止**（由 `check_compliance.ps1` 自动拦截） |

### 2. 依赖注入与 Service Locator 铁律

- **业务层（`src/game/`）**：允许且应当通过 `App.<service>` 访问模块公开门面（`BaseXxx`）。
- **框架实现层（`src/framework/modules/`、`infra/`、`util/`）**：
  - **严禁**在代码中通过 `App.<service>` 访问其他服务（防止掩盖真实依赖与制造隐式环路）。
  - 模块间依赖必须通过 `_init(...)` 或 `set_xxx(...)` 接收抽象门面类型（`BaseXxx`），由唯一组合根 [`FrameworkRuntime`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/core/runtime/framework_runtime.gd) 统一装配。

### 3. 全量模块依赖清单与拓扑矩阵

每个模块主实现类必须声明静态常量 `MODULE_ID`、`REQUIRED_MODULES` 与 `OPTIONAL_MODULES`，并与 `FrameworkRuntime.MODULE_MANIFEST` 保持一致：

| 启动序号 | 模块 ID (`MODULE_ID`) | 门面契约 (`Base*`) | 核心实现类 (`impl/`) | 强依赖 (`REQUIRED`) | 可选依赖 (`OPTIONAL`) | 宿主形态 |
|---|---|---|---|---|---|---|
| 01 | `&"env"` | `BaseRuntimeEnvironment` | `RuntimeEnvironment` | `[]` | `[]` | `RefCounted` |
| 02 | `&"logger"` | `BaseFrameworkLogger` | `FrameworkLogger` | `[]` | `[&"env"]` | `RefCounted` |
| 03 | `&"clock"` | `BaseClockSystem` | `ClockSystem` | `[]` | `[]` | `RefCounted` |
| 04 | `&"asset"` | `BaseAssetSystem` | `AssetSystem` | `[]` | `[]` | `RefCounted` |
| 05 | `&"input"` | `BaseInputSystem` | `InputSystem` | `[]` | `[&"logger"]` | `Node` |
| 06 | `&"haptic"` | `BaseHapticFeedback` | `HapticFeedback` | `[]` | `[&"input"]` | `RefCounted` |
| 07 | `&"net"` | `BaseNetworkClient` | `NetworkClient` | `[]` | `[&"logger", &"env"]` | `Node` |
| 08 | `&"storage"` | `BaseStorageSystem` | `StorageSystem` | `[]` | `[&"logger", &"net"]` | `RefCounted` |
| 09 | `&"locale"` | `BaseLocalizationSystem` | `LocalizationSystem` | `[]` | `[]` | `RefCounted` |
| 10 | `&"scene"` | `BaseSceneRouter` | `SceneRouter` | `[&"asset"]` | `[&"logger"]` | `Node` |
| 11 | `&"display"` | `BaseDisplaySystem` | `DisplaySystem` | `[]` | `[&"logger"]` | `Node` |
| 12 | `&"audio"` | `BaseAudioSystem` | `AudioSystem` | `[]` | `[&"asset", &"logger"]` | `Node` |
| 13 | `&"video"` | `BaseVideoPlayer` | `VideoPlayer` | `[]` | `[&"audio", &"logger"]` | `Node` |

---

## 二、 模块设计文档 12 维标准模板

新增或重构模块文档（`_doc_<module>.md`）时，必须明确回答以下 12 个工程维度：

| 规范章节 | 必须明确回答的工程问题 |
|---|---|
| **1. Responsibility** | 模块负责什么？明确**不负责**什么（与业务层和其他模块的边界）？ |
| **2. Public Contract** | 对外暴露哪些 `Base*` 门面方法、`types/` 数据结构与 `{Module}.{Reason}` 错误码？ |
| **3. Dependencies** | `REQUIRED_MODULES` 与 `OPTIONAL_MODULES` 分别是什么？无可选依赖时如何降级？ |
| **4. Lifecycle** | 何时创建、`initialize()`、挂树、`shutdown_async()`、`dispose()`？是否支持幂等重入？ |
| **5. Threading** | 哪些操作必须在主线程（SceneTree）执行？哪些 I/O 或编解码在后台线程执行？ |
| **6. Async & Cancellation** | 异步方法是否支持超时、并发合并（Inflight Join）或 [`TaskScope`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/infra/async/task_scope.gd) 取消守卫？ |
| **7. Failure Policy** | 失败时返回什么 `Result`？是否自动重试（`retryable`）、回退（`.bak`）或安全降级？ |
| **8. Resource Ownership** | 谁创建、谁持有、谁释放底层 `Resource` / `Node` / 文件句柄？ |
| **9. Performance Budget** | 内存上限、对象池容量、请求队列深度、同音节流间隔等硬性预算指标是什么？ |
| **10. Security & Privacy** | 哪些数据需要完整性校验（MD5 / SchemaVersion）？哪些敏感字段（Token）禁止打入日志？ |
| **11. Testing** | 如何通过 Fake Adapter 或独立测试场景（`src/test/<module>/`）脱离完整游戏验证？ |
| **12. Compatibility** | 公共接口演进或持久化格式（`schema_version`）升级时，如何保证向后兼容与迁移？ |

---

## 三、 Framework 完成度五大验收标准

框架演进不以“堆砌模块数量”为目标，而以以下五项工程能力作为唯一验收标准：

1. **依赖可控**：所有模块显式声明依赖，通过 [`FrameworkRuntime.validate_dependency_graph()`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/core/runtime/framework_runtime.gd) 与 `check_compliance.ps1` 双重校验，零循环依赖、零隐式 `App.xxx` 穿透、零业务反向耦合。
2. **生命周期可靠**：`FrameworkRuntime` 具备严格的状态机（`UNINITIALIZED -> INITIALIZING -> READY -> SHUTTING_DOWN -> STOPPED` 与失败回滚路径）；场景与视图内置 [`TaskScope`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/infra/async/task_scope.gd) 异步取消守卫。
3. **失败可恢复**：存档损坏具备 `.tmp/.bak` 原子自愈，格式升级具备 [`StorageMigrator`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/modules/storage/impl/storage_migrator.gd) 版本迁移链，可失败操作返回携带分类与上下文的 [`FrameworkError`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/core/contracts/framework_error.gd)。
4. **行为可验证**：引擎 API 由 Adapter 隔离，静态合规检查与 Headless 编译检查可通过命令行一键自动化执行。
5. **运行可诊断**：`App.get_runtime_diagnostics()` 与 `TaskScope.get_diagnostics()` 提供结构化耗时与状态快照。
