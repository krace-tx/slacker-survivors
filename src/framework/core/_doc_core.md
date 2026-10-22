# Framework · Core

> 框架通用基础类型、运行时组合根与全局聚合根。

```text
src/framework/core/
├── _doc_core.md           # 本文档
├── contracts/             # 所有服务共享的核心契约
│   ├── _doc_contract.md
│   ├── result.gd          # Result 可失败操作封装
│   └── framework_error.gd # FrameworkError 不可变错误对象
├── runtime/               # Framework 唯一组合根
│   ├── _doc_runtime.md
│   ├── framework_runtime.gd
│   ├── types/
│   │   └── runtime_state.gd
│   └── impl/
│       ├── runtime_manifest.gd
│       └── runtime_service_host.gd
└── autoload/              # 引擎 Autoload 挂载点
	├── _doc_autoload.md
	├── app.gd             # 全局服务定位器 (Service Locator)
	└── event_bus.gd       # 全局领域事件总线 (EventBus / Bus，不可变事实广播)
```

---

## 一、 错误处理与 Result

统一可失败操作的结果返回模型，强制调用方显式分支处理（纯 getter、不可失败计算无需强行包裹 `Result`）：

- `Result.value`、`Result.error` 对外只读；创建结果统一使用 `Result.ok(...)`、`Result.err(...)`、`Result.err_code(...)` 或带上下文诊断信息的 `Result.err_ex(...)`。
- `FrameworkError` 支持不可变的 `code`、`message`、`module`、`category`、`retryable`、`cause` 与 `context`，可通过 `with_context(...)` / `with_cause(...)` / `with_retryable(...)` 链式补充上下文。

```gdscript
# 1. 成功返回
return Result.ok(data)

# 2. 标准错误码返回 ({Module}.{Reason})
return Result.err_code("Scene.NotFound", "Scene path does not exist: %s" % path)

# 3. 携带结构化诊断上下文与重试标记的错误返回
return Result.err_ex("Network.Timeout", "Request timed out", {"url": url}, true)

# 4. 消费结果
var res := await App.storage.read_async("user_profile")
if res.is_ok():
	var data = res.value
else:
	App.logger.error("Core", "Load error: %s (%s)" % [res.error_code(), res.error_message()])
```

---

## 二、 App 服务定位器

全工程唯一 Autoload 服务门面聚合根。它不实例化具体服务，启动和释放交给 `FrameworkRuntime`：
- **业务层（`src/game/`）**：允许通过 `App.xxx` 访问各模块门面；
- **框架模块内部（`src/framework/modules/`）**：严禁通过 `App.xxx` 隐式访问其他服务，必须声明 `REQUIRED_MODULES` / `OPTIONAL_MODULES` 并由 `FrameworkRuntime` 显式构造注入。

```gdscript
App.logger.info("Boot", "Engine started.")
App.audio.play_sfx_by_path("res://assets/audio/click.wav")
```

---

## 三、 Bus 领域事件总线

只广播**已发生的客观事实**，绝不替代需要返回值与失败感知的直接服务调用（如切场景应直接调用 `await App.scene.replace(...)`）：
- **框架系统级事实**：通过内置 `signal` 直接连接（如 `app_paused`、`scene_changed`、`locale_changed`）；
- **业务跨模块事实**：通过动态主题方法 `Bus.on()` / `Bus.on_scoped()` / `Bus.off()` / `Bus.emit()` 配合各业务 `Service` 公开的 `EVENT_*` 常量解耦广播（内置最大递归深度 8 保护、自动清理已销毁对象的悬空回调，并支持 `on_scoped(event, owner_node, cb)` 随节点退树自动解绑）。

```gdscript
# 1. 订阅框架系统级信号
Bus.scene_changed.connect(_on_scene_changed)
Bus.app_paused.connect(_on_app_paused)

# 2. 订阅与广播业务跨模块领域事件（推荐节点使用 on_scoped 自动随退树解绑）
Bus.on_scoped(PlayerProfileService.EVENT_PROFILE_UPDATED, self, _on_profile_updated)
Bus.emit(PlayerProfileService.EVENT_PROFILE_UPDATED, {"profile": profile})
```
