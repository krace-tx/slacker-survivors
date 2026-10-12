# Skill Wiki · 框架架构设计铁律与约束准则 (Architecture Rules)

> 📖 **Wiki 定位**：本规范记录项目的核心架构约束。Agent 在编写或重构任何代码时，必须遵守本文件的硬性规则，避免破坏系统分层与封装。

---

## 1. 系统总体分层与单向依赖

项目严格实行单向分层，严禁逆向或跨层强耦合：

```
[表现层 / Presentation (UI / Dialog / HUD)]
          ↓ (通过 Presenter / Signal 驱动)
[业务逻辑层 / Domain & Gameplay (Features / Shared)]
          ↓ (通过 Service Locator / App.xxx 调用)
[框架与基础设施 / Framework & Infra (Core / Modules / Infra)]
          ↓
[Godot 引擎底层 / Engine API]
```

### 依赖红线
1. **表现层严禁拥有核心业务状态**：UI 节点只负责视图呈现与事件收集，不处理战斗数值计算或业务决策。
2. **业务逻辑层严禁直接操作具体 UI 节点**：业务计算（如玩家扣血、怪物死亡）禁止调用 `get_node("/root/.../HealthBar")`；应通过 Signal 向上抛出事件，由 Presenter 或 UI 监听刷新。
3. **框架层严禁反向依赖业务层**：`src/framework/` 下不得引用任何 `src/game/` 内的代码或资源。所有业务通用控件（如 `BaseDialog`、`DialogManager`）必须放在 `src/game/shared/components/`。

---

## 2. 三级通信解耦规范

为防止工程随着功能扩张演变为“网状调用”，通信严格收敛于以下 3 级：

| 通信级别 | 通信通道 | 适用范围 | 经典场景 |
| :--- | :--- | :--- | :--- |
| **父子节点级** | **Signal / 方法调用** | 强内聚的单场景内树形结构 | 按钮点击通知父面板 `button.pressed`；子控件通过信号传递数据给上层。 |
| **同层模块间** | **全局事件总线 (`Bus`)** | 跨界面、跨系统广播通知，监听者无需知晓触发源 | 玩家经验满级广播 `Bus.emit("player_leveled_up", data)`，战斗 HUD 与成就系统各自监听。 |
| **全局服务调用** | **服务定位器 (`App.xxx`)** | 获取由框架统一管理的全局系统能力 | 播放音效 `App.audio.play_sfx(...)`；切换场景 `App.scene.replace(...)`；网络请求 `App.net.get(...)`。 |

> ⚠️ **严禁行为**：
> - 严禁在两个平级业务模块间互相 `get_node()` 强引用。
> - 严禁绕过 `App` 门面自行实例化或缓存底层服务单例。

---

## 3. 目录与命名单复数黄金法则

全工程遵循统一的语义化命名标准：

> 💡 **核心原则**：
> - **领域 / 系统 / 功能域 ➔ 单数 (Singular)**：表达一个子系统、能力范畴、逻辑分层或业务领域。
> - **容器 / 资源 / 实例集合 ➔ 复数 (Plural)**：表达物理或逻辑上存放多个具体同质对象、文件、资源或插件的集合。

### 核心对比查照
- **单数技术域**：`src/framework/`、`src/framework/infra/param/`、`src/framework/modules/logger/`、`src/framework/util/file/`、`src/game/scenes/battle/`。
- **复数容器域**：`src/assets/videos/`、`src/assets/textures/`、`src/game/shared/components/`、`addons/`、`docs/`、各模块内的 `types/`、`adapters/`。

---

## 4. 工具集二级封装规范 (`util/`)

1. `src/framework/util/` 下禁止在根目录下平铺海量工具文件。
2. 必须按照技术领域细分二级单数目录（如 `file/file_utils.gd`、`async/async_utils.gd`、`node/node_utils.gd` 等）。
3. 所有工具类对外必须暴露统一风格的全局类名（`class_name XxxUtils`），工具方法统一声明为静态方法 `static func`。

---

## 5. 错误处理与返回值规范

1. **可失败操作统一使用 Result**：涉及网络 I/O、磁盘持久化、跨平台解码器初始化的方法，必须返回 `Result`（`Result.ok(value)` 或 `Result.err(AppError)`）。
2. **严禁静默吞异常**：禁止使用空的 `catch` / `if result.is_err(): pass`；失败分支必须通过 `App.logger.error(...)` 输出可诊断上下文。
