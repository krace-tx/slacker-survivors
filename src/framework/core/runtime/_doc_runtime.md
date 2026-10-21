# Runtime · Framework 运行时

## 职责

`FrameworkRuntime` 是 Framework 的唯一组合根（Composition Root）。它按依赖顺序创建服务、挂载需要场景树的节点服务，并在任意一步失败时逆序回滚。

`App` 是全局门面和系统生命周期入口，不负责实例化具体服务。业务代码继续通过 `App.xxx` 使用服务；具体实现和依赖关系只存在于 `framework/core/runtime/`。

```text
src/framework/core/runtime/
├── _doc_runtime.md               # 本文档
├── framework_runtime.gd          # 唯一组合根与状态机编排器 (FrameworkRuntime)
├── types/
│   └── runtime_state.gd          # 生命周期状态枚举与名称映射 (RuntimeState)
└── impl/
	├── runtime_manifest.gd       # 13大模块拓扑清单与 DAG 依赖图校验器 (RuntimeManifest)
	└── runtime_service_host.gd   # 服务安装宿主、耗时采集与逆序销毁器 (RuntimeServiceHost)
```

## 内部职责拆分

| 组件 | 职责边界 |
|---|---|
| [`FrameworkRuntime`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/core/runtime/framework_runtime.gd) | 组合根门面：驱动运行时状态机流转、管理根级 `TaskScope`，并显式声明 13 个核心模块的构造依赖注入（DI Wiring）。 |
| [`RuntimeState`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/core/runtime/types/runtime_state.gd) | 定义运行时 7 种状态枚举（`UNINITIALIZED`、`INITIALIZING`、`READY`、`INITIALIZATION_FAILED`、`ROLLING_BACK`、`SHUTTING_DOWN`、`STOPPED`）。 |
| [`RuntimeManifest`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/core/runtime/impl/runtime_manifest.gd) | 集中维护 13 个核心模块的拓扑清单（`MODULES`），提供静态 `validate_dag()` 有向无环图与启动顺序校验。 |
| [`RuntimeServiceHost`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/core/runtime/impl/runtime_service_host.gd) | 封装 `RefCounted` / `Node` 服务的统一安装（`install_ref` / `install_node`）、单步耗时指标记录（`_boot_metrics`）、`App` 属性绑定，以及回滚/停机时的统一逆序销毁（`teardown_async` / `teardown_sync`）。 |

## 初始化顺序与依赖校验
 
```text
Env → Logger → Clock → Asset → Input → Haptic
	→ Network → Storage → Locale
	→ Scene → Display → Audio → Video
```
 
- 启动前首先调用 `FrameworkRuntime.validate_dependency_graph()`（委托 `RuntimeManifest.validate_dag()`）校验全量模块的 `MODULE_MANIFEST` 有向无环图（DAG）与拓扑顺序。
- 顺序严格表达真实依赖关系：`Logger` 依赖 `Env`，`Input` 依赖 `Logger`，`Haptic` 显式依赖 `Input`，`Storage` 依赖 `Logger + Network`，表现层服务依赖 `Asset + Logger`，`Video` 依赖 `Audio + Logger`。
- 状态机流转：
  - 正常路径：`UNINITIALIZED → INITIALIZING → READY → SHUTTING_DOWN → STOPPED`
  - 异常路径：`INITIALIZING → INITIALIZATION_FAILED → ROLLING_BACK → STOPPED`

## 生命周期与优雅关闭

```gdscript
var result := await App.bootstrap()
if result.is_err():
	App.logger.error("Core", result.error_message())
```

- `App.bootstrap(on_progress)` 负责装配 Framework 底层服务，可被多个入口安全并发等待，重复调用不会重复创建。
- 支持传入 `on_progress: Callable(step_idx, total_steps, key)`，供启动入口（[`BootstrapScene`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/game/bootstrap/bootstrap_scene.gd) 或诊断工具）采集内核组件安装进度。
- 初始化失败会进入 `INITIALIZATION_FAILED → ROLLING_BACK → STOPPED`，由 `RuntimeServiceHost.teardown_async()` 按逆序执行 `shutdown_async()` 与 `dispose()`，并自动清空 `App.xxx`。
- 退出时由 `App._on_app_quit()` 调用 `await _runtime.shutdown_async()`，先逆序等待需要落盘的服务（如 `StorageSystem.shutdown_async()` 等待进行中的写入完成），再释放节点与纯逻辑服务。
- 可通过 `App.get_runtime_diagnostics()` 查询当前运行时状态与各模块启动耗时指标。
