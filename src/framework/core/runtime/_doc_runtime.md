# Runtime · Framework 运行时

## 职责

`FrameworkRuntime` 是 Framework 的唯一组合根（Composition Root）。它按依赖顺序创建服务、挂载需要场景树的节点服务，并在任意一步失败时逆序回滚。

`App` 是全局门面和系统生命周期入口，不负责实例化具体服务。业务代码继续通过 `App.xxx` 使用服务；具体实现和依赖关系只存在于 `framework/core/runtime/`。

```text
src/framework/core/
├── contracts/
│   ├── _doc_contract.md
│   ├── result.gd
│   ├── framework_error.gd
│   ├── subsystem.gd
│   └── node_subsystem.gd
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
Env → Log → Time → Asset → Haptic
	→ Network → Storage → Locale
	→ Scene → UI → Audio
```

顺序表达真实依赖关系：`Log` 依赖 `Env`，`Storage` 依赖 `Log + Network`，表现层服务依赖 `Asset + Log`。新增服务时应先判断它属于纯逻辑服务还是节点服务，再把它放到依赖完成之后的单一装配点。

## 生命周期

```gdscript
var result := await App.bootstrap()
if result.is_err():
	App.log.error("Core", result.error_message())
```

- `App.bootstrap()` 可被多个入口等待，重复调用不会重复创建服务。
- 初始化失败会返回 `Result.err`，已创建服务按逆序释放，`App.xxx` 会清空。
- `App._process()` 只转发 `tick(delta)`；没有帧驱动需求的服务保留空实现。
- 退出时由 `App` 调用 `FrameworkRuntime.dispose()`，节点服务和纯逻辑服务统一释放。

## 扩展约定

不要新增 `BootStage` 或 `BootPipeline` 包装单个初始化动作。直接在 `FrameworkRuntime.initialize()` 中加入一个有明确依赖的安装步骤即可。只有未来出现独立启动阶段、可取消任务或跨阶段进度展示时，才重新引入阶段调度抽象。

旧的 `BootPipeline.new(...).run()` 调用统一迁移为 `await App.bootstrap()`；业务层不再感知启动阶段类型。
