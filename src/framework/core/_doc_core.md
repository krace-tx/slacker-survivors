# Framework · Core

> 框架通用基础类型、运行时组合根与全局聚合根。

```text
src/framework/core/
├── _doc_core.md           # 本文档
├── contracts/             # 所有服务共享的核心契约
│   ├── _doc_contract.md
│   ├── result.gd          # Result 可失败操作封装
│   ├── framework_error.gd # FrameworkError 不可变错误对象
│   ├── subsystem.gd       # 纯对象生命周期托管基类 (Subsystem)
│   └── node_subsystem.gd  # Node 场景树生命周期托管基类 (NodeSubsystem)
├── runtime/              # Framework 唯一组合根
│   ├── _doc_runtime.md
│   └── framework_runtime.gd
└── autoload/              # 引擎 Autoload 挂载点
	├── _doc_autoload.md
	├── app.gd             # 全局服务定位器 (Service Locator)
	└── event_bus.gd       # 全局领域事件总线 (EventBus / Bus，不可变事实广播)
```

---

## 一、 错误处理与 Result

统一可失败操作的结果返回模型，强制调用方显式分支处理：

`Result.value`、`Result.error` 和 `FrameworkError.code/message` 对外只读；创建结果统一使用 `Result.ok(...)`、`Result.err(...)` 或 `Result.err_code(...)`。

```gdscript
# 1. 成功返回
return Result.ok(data)

# 2. 标准错误码返回 ({Module}.{Reason})
return Result.err_code("Scene.NotFound", "Scene path does not exist: %s" % path)

# 3. 消费结果
var res := await App.storage.read_async("user_profile")
if res.is_ok():
	var data = res.value
else:
	App.logger.error("Core", "Load error: %s (%s)" % [res.error_code(), res.error_message()])
```

---

## 二、 App 服务定位器

全工程唯一 Autoload 服务门面聚合根。它不实例化具体服务，启动和释放交给 `FrameworkRuntime`：

```gdscript
App.logger.info("Boot", "Engine started.")
App.audio.play_sfx_by_path("res://assets/audio/click.wav")
```

---

## 三、 Bus 领域事件总线

只广播已发生的客观事实，不承载具体业务命令：
- **框架系统级事实**：通过内置 `signal` 直接连接（如 `app_paused`、`scene_changed`、`locale_changed`）；
- **业务跨模块事实**：通过动态主题方法 `Bus.on()` / `Bus.off()` / `Bus.emit()` 配合 `GameEvents` 常量解耦广播（自动清理已销毁对象的悬空回调，并自适应无参或单参回调）。

```gdscript
# 1. 订阅框架系统级信号
Bus.scene_changed.connect(_on_scene_changed)
Bus.app_paused.connect(_on_app_paused)

# 2. 订阅与广播业务跨模块领域事件
Bus.on(GameEvents.GOLD_CHANGED, _on_gold_changed)
Bus.emit(GameEvents.GOLD_CHANGED, {"gold": 500, "delta": 100})
```
