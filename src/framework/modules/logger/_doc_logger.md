# Framework · Logger

> 结构化分级日志基础设施，支持 Tag 模块分类染色与未初始化保底。

```text
src/framework/modules/logger/
├── _doc_logger.md          # 本文档
├── base_framework_logger.gd # 公开门面契约 BaseFrameworkLogger (App.logger，详尽注释)
│
├── types/                  # [公开契约]
│   └── log_level.gd        # LogLevel 枚举命名空间 + 标签 / 颜色
│
└── impl/                   # [私有收敛]
    └── framework_logger.gd # 门面实现：级别过滤、环形缓冲、富文本控制台
```

---

## 核心设计特性

1. **Tag 分类输出**：强制或推荐包含模块 Tag，输出形如 `[INFO][Scene] Scene loaded: MainMenu`。
2. **级别过滤**：`LogLevel.DEBUG / INFO / WARN / ERROR` 四级阈值，PROD 环境默认 `WARN` 起步。
3. **未初始化保底机制**：在 `App.logger` 实例化之前，使用静态 `FrameworkLogger.print_raw(LogLevel.INFO, tag, msg)` 降级输出，绝不抛空指针，绝不丢失启动早期日志。

---

## 使用范式

```gdscript
App.logger.debug("Network", "Connecting to socket...")
App.logger.info("Lobby", "Player selected hero: 01")
App.logger.warn("Storage", "Save file missing, restoring backup.")
App.logger.error("Scene", "Failed to load level: Level_05")

# 启动早期 / 工具类中无 App.logger 时
FrameworkLogger.print_raw(LogLevel.WARN, "Boot", "App.logger is not ready yet.")
```
