# Framework · Clock

> 防作弊权威时钟服务。基于本地单调 Tick 与服务器 Unix 时间戳对齐校准，提供秒/毫秒时间戳与可信度查询。
> 严格区分有状态的**时钟设备 (`App.clock` / `BaseClockSystem`)** 与无状态的**时间格式化纯函数工具 (`TimeUtils`)**。

```text
src/framework/modules/clock/
├── _doc_clock.md           # 本文档
├── base_clock_system.gd    # 公开门面契约 BaseClockSystem (App.clock，详尽注释)
└── impl/                   # 私有实现收敛
    └── clock_system.gd     # 门面实现：防作弊权威时钟与服务器校对
```

---

## 核心设计特性与四类时钟边界

| 时钟类型 | 方法入口 | 适用场景 |
|---|---|---|
| **单调时钟 (Monotonic)** | `App.clock.monotonic_msec()` / `monotonic_usec()` | 计算耗时、超时判定、重试退避间隔（不受修改系统时间影响） |
| **墙上时钟 (Wall Clock)** | `App.clock.system_unix_msec()` | 本地日期显示、日志时间戳（不可作为防作弊依据） |
| **服务器校准时间 (Estimated Server)** | `App.clock.estimated_server_time_ms()` / `now_msec()` / `now()` | 依赖服务端时间的活动期限、每日重置、跨设备时间判断 |
| **游戏模拟时钟 (Simulation)** | 由 `src/game/` 业务层按玩法自行维护 | 游戏内时间流逝、暂停、倍速、战斗帧计时（不混入 Framework 权威时钟） |

---

## 使用范式

```gdscript
# 1. 计算操作耗时（使用单调时钟）
var start_ms := App.clock.monotonic_msec()

# 2. 读取服务端校准后的权威时间戳
if App.clock.is_trusted():
    var server_sec := App.clock.now()
    var server_msec := App.clock.estimated_server_time_ms()

# 3. 格式化时长文本（使用无状态纯函数工具 TimeUtils）
var text := TimeUtils.format_mm_ss(125) # "02:05"
```
