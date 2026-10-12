# Framework · Time

> 防作弊权威时间服务。基于本地单调 Tick 与服务器 Unix 时间戳对齐校准，提供秒/毫秒时间戳与可信度查询。

```text
src/framework/modules/time/
├── _doc_time.md            # 本文档
├── base_time_system.gd     # 公开门面契约 BaseTimeSystem (App.time，详尽注释)
└── impl/                   # 私有实现收敛
    └── time_system.gd      # 门面实现：防作弊权威时钟与服务器校对
```

---

## 核心设计特性

1. **防作弊时间基准**：结合 OS 单调运行时间（Monotonic Tick）计算流逝，防止玩家通过修改系统本地时间刷体力或刷新倒计时。
2. **服务器校准**：接收到服务器权威时间戳后自动平滑校对。

---

## 使用范式

```gdscript
if App.time.is_trusted():
    var server_sec := App.time.now()
    var server_msec := App.time.now_msec()
```
