# Runtime · Framework 运行时

## 职责

`FrameworkRuntime` 是 Framework 的唯一组合根（Composition Root）。它按依赖顺序创建服务、挂载需要场景树的节点服务，并在任意一步失败时逆序回滚。

`App` 是全局门面和系统生命周期入口，不负责实例化具体服务。业务代码继续通过 `App.xxx` 使用服务；具体实现和依赖关系只存在于 `framework/core/runtime/`。

```text
src/framework/core/
├── contracts/
│   ├── _doc_contract.md
│   ├── result.gd
│   └── framework_error.gd
├── runtime/
│   ├── _doc_runtime.md
│   └── framework_runtime.gd
└── autoload/
	├── _doc_autoload.md
	├── app.gd
	└── event_bus.gd
```

## 初始化顺序
 
```text
Env → Logger → Time → Asset → Haptic → Input
	→ Network → Storage → Locale
	→ Scene → UI → Audio → Video
```
 
顺序表达真实依赖关系：`Logger` 依赖 `Env`，`Storage` 依赖 `Logger + Network`，表现层服务依赖 `Asset + Logger`，`Video` 依赖 `Audio + Logger`。新增服务时应先判断它属于纯逻辑服务还是节点服务，再把它放到依赖完成之后的单一装配点。

## 生命周期

```gdscript
var result := await App.bootstrap()
if result.is_err():
	App.logger.error("Core", result.error_message())
```

- `App.bootstrap(on_progress)` 负责装配 Framework 底层服务，可被多个入口安全并发等待，重复调用不会重复创建。
- 支持传入 `on_progress: Callable(step_idx, total_steps, key)`，供业务启动管线（`CoreBootPhase`）呈现内核组件加载明细。
- 初始化失败会返回 `Result.err`，已创建服务按逆序释放，`App.xxx` 会清空。
- `App._process()` 只转发 `tick(delta)`；没有帧驱动需求的服务保留空实现。
- 退出时由 `App` 调用 `FrameworkRuntime.dispose()`，节点服务和纯逻辑服务统一释放。

## 启动分工与业务衔接

- **Framework 内核启动**：由 `App.bootstrap()` 负责，唯一收敛 12 大底层技术模块；
- **两阶段完整流水线**：由游戏业务层 `GameBootstrapper` 编排：
  1. 阶段一：调用 `CoreBootPhase` 驱动 `App.bootstrap()`；
  2. 阶段二：调用 `BusinessBootPhase` 载入策划配置、玩家存档与业务 Model；
  两阶段完成后平滑切换至大厅主场景（详见 `src/game/bootstrap/_doc_bootstrap.md`）。
