# Framework · Logger (分级日志、富文本染色与环形诊断缓冲系统)

> 全项目统一的结构化分级日志与崩溃现场回溯基础设施（`App.logger` / [`BaseFrameworkLogger`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/modules/logger/base_framework_logger.gd)）。
> 支持环境感知级别过滤、模块 Tag 分类追踪、控制台 BBCode 安全染色、调试器面板联动（`push_warning` / `push_error`）、1000 条环形内存缓冲导出（`dump()`）以及启动早期的静态无实例保底打印。

```text
src/framework/modules/logger/
├── _doc_logger.md              # 本文档
├── base_framework_logger.gd    # 公开门面契约 BaseFrameworkLogger (App.logger，详尽注释)
│
├── types/                      # [公开契约]
│   └── log_level.gd            # 日志级别枚举 (DEBUG/INFO/WARN/ERROR)、标签与 Tailwind 色板常量 (LogLevel)
│
└── impl/                       # [私有实现收敛]
    └── framework_logger.gd     # 门面实现 (FrameworkLogger: 环境阈值推导、环形缓冲、安全染色与 print_raw 保底)
```

---

## 一、 核心工程设计机制

1. **环境感知阈值与显式依赖注入 (`MODULE_ID = &"logger"`)**：
   - 声明 `OPTIONAL_MODULES = [&"env"]`，在 `FrameworkRuntime` 启动阶段紧随 `RuntimeEnvironment` 之后构造并注入 `BaseRuntimeEnvironment`。
   - **自动分级策略**：生产环境（`env.is_prod() == true`）自动将 `min_level` 设为 `LogLevel.WARN`，屏蔽高频 `DEBUG / INFO` 日志开销；本地开发与测试环境默认设为 `LogLevel.DEBUG`。
2. **四级日志体系与双通道调试联动 (`LogLevel`)**：
   - `LogLevel.DEBUG (0)`：亮蓝 `#3B82F6`，开发期高频调试细节；
   - `LogLevel.INFO (1)`：灰白 `#D1D5DB`，关键生命周期节点与状态流转；
   - `LogLevel.WARN (2)`：橙黄 `#F59E0B`，可恢复异常（如网络重试、回退 `.bak`），同时调用 `push_warning(line)` 同步进入 Godot 调试器面板；
   - `LogLevel.ERROR (3)`：亮红 `#EF4444`，阻断性故障，同时调用 `push_error(line)` 同步进入 Godot 调试器面板并触发栈追踪。
3. **BBCode 防注入转义与统一时间戳格式**：
   - 输出格式统一为 `[YYYY-MM-DD HH:MM:SS] [LEVEL] [Tag] Message`（时间戳由无状态 [`TimeUtils.now_string()`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/util/time/time_utils.gd) 提供）。
   - 调用 `print_rich` 前自动将正文中的 `[` 转义为 `[lb]`，防止日志内容中包含数组文本（如 `[Shift + Q]`）或方括号时被误解析为非法 BBCode 标签导致文字吞没。
4. **1000 条固定容量环形内存缓冲 (`dump()` / `clear()`)**：
   - 内部通过 `_entries: PackedStringArray` 维护最近 `1000` 条通过级别过滤的纯文本日志（超出上限时 FIFO 淘汰最旧条目）。
   - 发生严重错误或玩家提交反馈时，调用 `App.logger.dump()` 即可一键导出完整的带时间戳历史日志上下文。
5. **未初始化静态保底机制 (`FrameworkLogger.print_raw`)**：
   - 在 `App.bootstrap()` 尚未完成、或位于禁止访问 `App.xxx` 的底层无状态工具类/基建类（如 `CooldownScheduler`、`SpinePool`）中，可直接调用静态方法 `FrameworkLogger.print_raw(LogLevel.WARN, "Tag", "Message")` 安全输出染色日志，绝不产生空指针。

---

## 二、 使用范式

```gdscript
# 1. 标准业务与模块分级日志输出（严禁裸写 print()）
App.logger.debug("Network", "Sending request to /v1/profile...")
App.logger.info("Scene", "Entered scene: SplashScene")
App.logger.warn("Storage", "Primary save missing, falling back to .bak")
App.logger.error("Audio", "Failed to load audio stream: %s" % path)

# 2. 崩溃或错误上报时导出最近 1000 条历史日志快照
var log_snapshot: String = App.logger.dump()

# 3. 启动早期或底层工具类中的无实例静态保底输出
FrameworkLogger.print_raw(LogLevel.INFO, "Boot", "Kernel initialization started.")
```
