# Scheduler (调度基建)

## 核心

异步冷却防抖调度基础设施。基于**显式有限状态机 (FSM)** 与**单定时器模型 (Single-Timer Invariant)**，协调速率限制 (Rate Limiting)、尾部延迟合并 (Trailing Debounce) 与并发串行互斥 (Execution Mutex)。
做：保证执行间隔 $\ge$ 冷却时长、冷却期多次高频调用自动合并于尾部补发、并发异步串行化互斥。
不做：不持久化调用参数、不提供优先队列与跨帧任务切片调度。

---

## 细节

- **显式状态机驱动**：划分 `IDLE`（就绪）、`EXECUTING`（执行中）、`COOLDOWN`（冷却中）三个离散状态，流转关系闭环严密。
- **单定时器模型**：全局维护唯一等待计时器，彻底杜绝高频触发产生 Timer 协程雪崩与资源泄漏。
- **并发串行锁**：执行期间即使冷却已过也不允许重入，所有并发触发均标记为 `has_pending`，在前序任务执行完毕后继续冷却补发。
- **状态指标监控**：暴露只读状态 `state`、`is_busy`、`is_executing`、`has_pending`、`remaining_cooldown`，便于上层业务与埋点系统感知调度器负载。
- **信号切面**：任务实质性执行完成时发射 `executed`；请求被节流合并时发射 `throttled`；状态切换时发射 `state_changed`。

```text
src/framework/infra/scheduler/
├── _doc_scheduler.md       # 调度基建模块架构与调用规范
└── cooldown_scheduler.gd   # 异步冷却节流调度器核心实现 (FSM 驱动)
```

---

## 样例

```gdscript
# 1. 实例化调度器（冷却 5 秒，绑定异步云同步方法）
var scheduler := CooldownScheduler.new(5.0, func():
	await App.storage.write_async(item, data.encode(), WriteMode.LOCAL_FIRST)
)

# 2. 监听状态机流转
scheduler.state_changed.connect(func(old_state, new_state):
	print("Scheduler state: %s -> %s" % [old_state, new_state])
)

# 3. 高频调用：首次立即执行，后续 5 秒内触发全部合并，期满自动补发一次
scheduler.trigger()
scheduler.trigger()
scheduler.trigger()

# 4. 强制立即刷入
scheduler.flush()

# 5. 取消尾部待发任务
scheduler.cancel()
```
