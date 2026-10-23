# Infra · Async (异步任务作用域与并发编排协议)

## 核心

全框架唯一的异步生命周期管理与并发编排基建。
统一收敛单任务守卫执行（`run`）、多任务并发收集（`gather`）、竞态抢占（`race`）、安全休眠（`sleep` / `TaskScope.wait`）与协作式取消（`CancellationToken`），彻底杜绝「场景退出或 UI 关闭后，异步回调继续执行并访问已释放节点」的 Use-After-Free 与资源泄漏风险。

```text
src/framework/infra/async/
├── _doc_async.md           # 本文档
├── cancellation_token.gd   # 协作式取消令牌 (CancellationToken)
└── task_scope.gd           # 绑定宿主生命周期的任务作用域与并发编排器 (TaskScope)
```

---

## 异步任务三级所有权模型

| 所有者 | 绑定宿主 | 典型任务 | 清理时机 |
|---|---|---|---|
| **Framework** | `FrameworkRuntime` | 远端配置刷新、全局网络/存储落盘 | `FrameworkRuntime.shutdown_async()` / `dispose()` |
| **Scene** | `BaseScene.task_scope` | 当前场景的资源加载、并发预热、延时动效 | 场景退栈或 `_exit_tree()` 时自动 `dispose()` |
| **UI / View** | `BaseView.task_scope` | 界面数据拉取、按钮触发的异步请求 | `close()` 时自动 `cancel_all()`；退树时自动 `dispose()` |

---

## 核心特性

1. **零循环引用弱绑定**：`TaskScope` 内部仅通过 `instance_id` 弱引用追踪宿主节点（`BaseScene` / `BaseView`），绝不阻止 `RefCounted` 或 `Node` 的正常释放。
2. **代际隔离（Generation Isolation）**：调用 `cancel_all()` 时递增代际号并轮换新 `CancellationToken`，尚未结束的旧协程在 `await` 恢复后会被 Completion Guard 立即拦截，丢弃过期结果并返回 `Async.Cancelled`。
3. **全链路 Result 与级联取消（Cascading Cancellation）**：
   - `run(task, timeout)`：单任务守卫执行；
   - `gather(tasks, timeout)`：并发等待全部子任务完成，若任意子任务返回错误 `Result` 或整体取消/超时，立即级联取消其余同行任务；全部成功时自动解包返回 `Result.ok(results_array)`；
   - `race(tasks, timeout)`：竞态等待首个任务完成，胜出瞬间自动触发级联令牌取消其余陪跑任务；
   - `sleep(seconds)` / `TaskScope.wait(node, seconds)`：受生命周期保护的安全休眠。
4. **取消与超时语义分离**：
   - 主动取消或宿主销毁退树：返回 `Result.err_code("Async.Cancelled", ...)`（`retryable = false`）。
   - 超过指定时限：返回 `Result.err_code("Async.Timeout", ...)`（`retryable = true`）。
5. **诊断统计**：通过 `task_scope.get_diagnostics()` 可随时读取 `active / completed / cancelled / timed_out / failed` 计数。

---

## 使用范式

```gdscript
# 1. 在 BaseScene / BaseView 子类中执行单任务守卫 (run)
func _on_enter(params: Dictionary = {}) -> void:
	var res := await task_scope.run(func(token: CancellationToken) -> Result:
		return await App.asset.load("res://src/assets/textures/lobby/tex_lobby_bg.png")
	, 5.0) # 5秒超时保护

	if res.is_err():
		return # 若等待期间玩家已切走场景，res 为 Async.Cancelled，安全短路！
	$UI/Background.texture = res.value as Texture2D

# 2. 多任务并发收集 (gather)：任一失败或场景退出自动级联取消
var batch_res := await task_scope.gather([
	func(token: CancellationToken): return await App.asset.load("res://icon.svg"),
	func(token: CancellationToken): return await App.net.get_json("/api/profile", {}, token),
], 10.0)
if batch_res.is_ok():
	var items: Array = batch_res.value
	var icon_tex := items[0] as Texture2D
	var profile_dict := items[1] as Dictionary

# 3. 作用域安全休眠 (sleep) 与普通节点静态等待 (TaskScope.wait)
if (await task_scope.sleep(1.5)).is_ok():
	_play_next_step()

# 普通非 BaseScene 节点一行防 UAF 等待：
if (await TaskScope.wait(self, 0.8)).is_ok():
	queue_free()
```
