# Skill Wiki · 模块架构设计与文档编写蓝图 (Module & Doc Design Blueprint)

> **Wiki 定位**：当任务涉及**新增/重构框架模块（`src/framework/modules/`）**、**新建/拆分业务功能切片（`src/game/features/` 或 `src/game/shared/`）**、或**编写/更新架构文档（`_doc_*.md`）与代码注释（`##`）**时，必须遵循本蓝图的标准化模板与工程工序。

---

## 一、 框架模块设计四层蓝图 (`src/framework/modules/<module>/`)

所有框架模块严格遵循 **“公开门面 + 公开类型 + 私有实现 + 组合根显式注入”** 四层隔离架构，严禁在模块内部调用 `App.xxx`。

### 1. 标准目录拓扑

```text
src/framework/modules/<module>/          # 单数能力名 (如 audio/, storage/, cursor/)
├── _doc_<module>.md                     # [必选] 12 维模块架构设计文档
├── base_<module>_system.gd              # [必选] 抽象公开门面 (@abstract class_name BaseXxx)
├── types/                               # [可选] 复数容器：公开枚举、配置、选项契约 (*Options / *State / *Error)
│   ├── <module>_options.gd
│   └── <module>_error.gd
└── impl/                                # [必选] 私有实现层（外部严禁直接引用，由 R10 门禁拦截）
    ├── <module>_system.gd               # 主实现类 (class_name XxxSystem extends BaseXxx)
    ├── <engine>_adapter.gd              # 引擎/平台底层隔离适配器 (便于单测替换)
    └── drivers/                         # 多后端/多介质驱动集合 (如 memory/disk/remote)
```

### 2. 框架模块开发与接入五步工序

1. **定义抽象门面 (`base_<role>.gd`)**：
   - 使用 `@abstract` 标记类与所有公开方法（`@abstract func xxx(...) -> Result`）；
   - 选择最小基类：无需挂树/帧更新的系统一律继承 `RefCounted`；需要持有子节点或监听 `_input`/`_process` 的系统继承 `Node`。
2. **编写主实现类 (`impl/<role>.gd`)**：
   - 在文件顶部 `#region Module Dependency Manifest` 声明三项静态常量（由 `R09` 与 `RuntimeManifest.verify_step_contract()` 双重核验）：
     ```gdscript
     #region Module Dependency Manifest
     const MODULE_ID: StringName = &"<module_id>"
     const REQUIRED_MODULES: Array[StringName] = [&"asset"]
     const OPTIONAL_MODULES: Array[StringName] = [&"logger"]
     #endregion
     ```
   - 通过 `_init(...)` 显式接收依赖模块的抽象门面（`Base*`），严禁出现 `App.xxx`（由 `R08` 门禁拦截）；
   - 按需实现生命周期协议：`func initialize() -> Result`、`func shutdown_async() -> void`、`func dispose() -> void`。
3. **注册拓扑清单 ([`RuntimeManifest`](../../../../src/framework/core/runtime/impl/runtime_manifest.gd))**：
   - 在 `RuntimeManifest.MODULES` 中按 DAG 拓扑顺序注册 `{"id": &"<module_id>", "required": [...], "optional": [...]}`，确保所有依赖项均排在当前模块之前。
4. **组合根显式装配 ([`FrameworkRuntime`](../../../../src/framework/core/runtime/framework_runtime.gd))**：
   - 在 `FrameworkRuntime._assemble_modules_async()` 中按拓扑槽位顺序实例化并调用 `await _host.install(service)`（自动核对契约、识别 `Node`/`RefCounted`、采集耗时并绑定 `App.<id>`）。
5. **暴露门面属性 ([`app.gd`](../../../../src/framework/core/autoload/app.gd))**：
   - 在 `app.gd` 的 `#region Core Subsystems` 中声明强类型公开属性 `var <module_id>: BaseXxx`。

---

## 二、 游戏业务模块设计蓝图 (`src/game/`)

### 1. 共享内核 vs 垂直业务切片准入边界 (`shared/` vs `features/`)

| 归属位置 | 准入判定法则 | 允许的结构 | 依赖红线 |
| :--- | :--- | :--- | :--- |
| **`src/game/shared/`** | **2+ 模块复用铁律 (Rule of 2+)**：必须被 **2 个及以上** 垂直业务切片共同使用的领域模型、全局业务服务或通用无业务流 UI 控件 | 严格固定为单数三支柱：<br>• `shared/model/<domain>/`<br>• `shared/service/<domain>/`<br>• `shared/component/<domain>/` | **零向上依赖 (`R06`)**：严禁引用任何 `features/` 或 `bootstrap/` 代码与资产 |
| **`src/game/features/<feature>/`** | 独立垂直业务域（如 `splash`、`lobby`、`battle`、`shop`、`talent`） | 按交互特征二选一：<br>• **MSVP** (`model/service/view/presenter`)<br>• **MES** (`model/engine/service`) | 跨 Feature 严禁直接互引内部类，统一通过 `shared/` 或 `Bus` 事件解耦 |

### 2. MSVP 与 MES 架构选型决策树

```text
新建业务模块 src/game/features/<feature>/
       │
       ▼
是否包含独立 UI 场景、视图面板或弹窗交互？
 ├── 【是】 ──► 采用 MSVP 架构 (model/ + service/ + view/ + presenter/)
 │              ├─ model/      : 纯数据契约与状态 (*Config / *Model / *State / *Params / *Data)
 │              ├─ service/    : 业务规则、调用 App.storage / App.net、修改 Model、发射 Bus 事件
 │              ├─ view/       : 拆分为 scene/<domain>/ 与 component/<domain>/ (1 .tscn + N .gd)
 │              └─ presenter/  : 薄胶水层 (监听 View 信号调 Service；监听 Model/Bus 调 View.render_*)
 │
 └── 【否】 ──► 采用 MES 架构 (model/ + engine/ + service/)
                ├─ model/      : 实体数据、运行时状态 (*State) 与演算上下文 (*Context)
                ├─ engine/     : 100% 纯计算/纯算法推演 (*Engine extends RefCounted，零外部 I/O)
                └─ service/    : 对外业务入口，组装 Context 调 Engine，负责持久化与 Bus 广播
```

### 3. `view/` 内部二级分类与“领域单元文件夹”包裹铁律

严禁在 `features/<feature>/view/` 根目录下直接平铺 `.tscn` 与 `.gd` 文件：

1. **顶层场景舞台 (`view/scene/<domain>/`)**：
   - 文件夹名使用**精简领域单数名词**（如 `view/scene/splash/`）；
   - 内部包含 `1 个 .tscn + N 个职责分离的 .gd`：
     - `<domain>_scene.tscn`：主场景文件；
     - `<domain>_scene.gd`（`extends BaseScene`）：仅负责 `_on_enter(params: BaseParams = null)` / `_on_exit()` 路由生命周期与 `Presenter` 装配解绑；
     - `<domain>_view.gd`（`extends BaseView`，挂载于场景树 `UI` 节点）：负责安全区适配、持有子组件引用并对外暴露纯净的 `render_*()` 视图更新接口。
2. **局部预制体与弹窗 (`view/component/<domain>/`)**：
   - 文件夹名使用**精简领域单数名词**（如 `view/component/progress/`、`view/component/card/`）；
   - 文件名与 `class_name` **严禁使用赘述的 `_component` / `Component` 后缀**，必须使用具体 UI 语义角色后缀：`*Panel`、`*Bar`、`*Card`、`*Slot`、`*Item`、`*Button`、`*Dialog`。

### 4. `model/` 7 大领域后缀与沙盒持久化绑定规范

所有 `model/` 下的数据类必须遵循 **“一类一文件 (`1 class_name = 1 .gd`)”** 并严格按生命周期选用后缀：

| 后缀 | 定位 | 基类 | 关键约束 |
| :--- | :--- | :--- | :--- |
| **`*Config`** | 静态只读策划配表 | `Resource` / `BaseParams` | 运行期只读，严禁原地修改属性 |
| **`*Req` / `*Resp`** | 网络请求/响应信封 | `BaseParams` | 在 `Service` 层内序列化/反序列化消化 |
| **`*Model`** | 跨周期持久化存档根 | `BaseParams` | **唯一允许构造 `StorageItem` 的类**（见下表 `R16` 规范） |
| **`*State`** | 不存盘的运行时活状态 | `RefCounted` / `BaseParams` | 退出场景或结束单局即销毁 |
| **`*Data`** | 内嵌子结构 / 列表条目 | `BaseParams` / `RefCounted` | 挂在 `*Model` 或 `*Resp` 内部，替代 `*VO/*Info` |
| **`*Params`** | 切场景 / 开弹窗传参包 | `BaseParams` | 传给 `App.scene.replace(..., params)` 或 `DialogManager` |
| **`*Context`** | 算法引擎演算工作台 | `RefCounted` / `BaseParams` | 在 MES 的 `Engine` 或多步管线间传递 |

> **持久化 `*Model` 沙盒绑定铁律 (`R16`)**：
> - `src/game/` 下严禁裸写 `"user://..."` 字符串；
> - 仅允许 `*_model.gd` 调用 `StorageItem.for_config(STORAGE_DOMAIN, subject, version)` 或 `StorageItem.for_save(STORAGE_DOMAIN, subject, version, ext)`；
> - 位于 `src/game/shared/model/save/` 的模型，`STORAGE_DOMAIN` 必须为 `&"shared"`；位于 `src/game/features/<feature>/model/` 的模型，`STORAGE_DOMAIN` 必须为 `&"<feature>"`。

---

## 三、 架构文档 (`_doc_*.md`) 与代码注释 (`##`) 编写规范

### 1. 何时必须编写或更新 `_doc_*.md`

- 新增或重构 `src/framework/modules/<module>/` 时，必须同步维护 `_doc_<module>.md`；
- 新增或重构 `src/framework/infra/<domain>/` 或 `src/framework/util/<domain>/` 时，必须同步维护对应 `_doc_*.md`；
- 新增或重构 `src/game/features/<feature>/` 时，必须在模块根目录创建 `_doc_<feature>.md`；
- 新增 `_doc_*.md` 后，必须将其同步登记到 [keyword_matrix.md](keyword_matrix.md)。

### 2. 框架模块文档 (`_doc_<module>.md`) 12 维标准结构

编写框架层模块文档时，必须覆盖以下核心章节（详见 [`src/framework/_doc_module_standard.md`](../../../../src/framework/_doc_module_standard.md)）：

1. **职责边界 (Responsibility)**：一句话定位 + 明确模块“负责什么”与“绝不负责什么”。
2. **目录结构与组件拆分 (Directory & Collaborators)**：ASCII 目录树 + 门面/实现/驱动/适配器职责表（含文件相对链接）。
3. **公开契约与数据模型 (Public Contract & Types)**：`Base*` 核心 API 签名、`types/` 参数选项与 `{Module}.{Reason}` 错误码表。
4. **依赖关系与降级策略 (Dependencies)**：`MODULE_ID`、`REQUIRED_MODULES`、`OPTIONAL_MODULES` 及可选依赖缺失时的安全降级行为。
5. **生命周期与并发安全 (Lifecycle, Async & Cancellation)**：初始化、挂树、`TaskScope` 取消守卫、`shutdown_async()` 优雅停机与 `dispose()`。
6. **性能预算与故障自愈 (Performance Budget & Failure Policy)**：对象池容量/节流阈值/缓存上限，以及 I/O 失败重试或回退策略。
7. **标准调用示例 (Usage Examples)**：提供可直接复制的黄金 GDScript 调用示例。

### 3. 业务切片文档 (`_doc_<feature>.md`) 标准结构

编写业务模块文档时，必须包含：
1. **模块定位与架构模式**：声明采用 **MSVP** 还是 **MES**，以及与 `shared/` 或其他模块的边界。
2. **目录拓扑树**：清晰列出 `model/`、`service/`（或 `engine/`）、`presenter/`、`view/scene/<domain>/`、`view/component/<domain>/` 下的文件职责。
3. **核心数据流与状态流转图**：使用 `mermaid` (`flowchart LR` 或 `sequenceDiagram`) 描绘交互或算法流。
4. **领域事件与外部契约**：列出该模块发射或监听的 `Bus` 事件常量（`EVENT_*`）、路由入参（`*Params`）与持久化模型（`*Model`）。

### 4. GDScript `##` 文档注释语法规范

所有公开类（`class_name`）、公开信号、公开属性与公开方法必须编写 `##` 文档注释，并使用 Godot 原生 BBCode 标签构建可跳转引用：

| 注释目标 | 标准 BBCode 语法 | 示例 |
| :--- | :--- | :--- |
| **引用类/枚举/方法/成员/信号** | `[ClassName]` / `[enum Class.Enum]` / `[method Class.fn]` / `[member Class.prop]` / `[signal Class.sig]` | `## 委托 [FrameworkRuntime] 执行初始化，完成后触发 [signal bootstrap_completed]。` |
| **引用函数形参** | `[param arg_name]` | `## [param on_progress] 阶段进度回调。` |
| **行内代码与加粗** | `[code]...[/code]` / `[b]...[/b]` | `## 返回包含 [code]state[/code] 字段的诊断快照。` |
| **段落换行** | 行尾添加 `[br]` | `## 第一行说明。[br]` |
| **代码块示例** | `[codeblocks]` + `[gdscript]` | 用于核心基类或复杂工具函数的内嵌示例 |
