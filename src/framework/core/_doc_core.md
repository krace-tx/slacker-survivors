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
	App.log.error("Core", "Load error: %s (%s)" % [res.error_code(), res.error_message()])
```

---

## 二、 App 服务定位器

全工程唯一 Autoload 服务门面聚合根。它不实例化具体服务，启动和释放交给 `FrameworkRuntime`：

```gdscript
App.log.info("Boot", "Engine started.")
App.audio.play_sfx_by_path("res://assets/audio/click.wav")
```

---

## 三、 Bus 领域事件总线

只广播已发生的客观事实，不承载具体业务命令：

```gdscript
# 订阅事实
Bus.scene_changed.connect(_on_scene_changed)
Bus.app_paused.connect(_on_app_paused)
```
