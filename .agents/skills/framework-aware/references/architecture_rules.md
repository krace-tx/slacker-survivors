# Skill Wiki · 框架架构设计铁律与开发规范 (Architecture & Coding Rules)

> **Wiki 定位**：本规范提炼全工程的核心架构约束与 GDScript 4.7 编码红线（对应 `check_compliance.py` 的 **R01 ~ R16** 自动化门禁）。Agent 在编写或重构任何代码时，必须严格遵守。

---

## 1. 全局单向依赖与模块隔离铁律 (`R05 ~ R10`)

项目严格实行自上而下的单向有向无环图（DAG），严禁逆向引用或跨层穿透：

```text
[测试验证层 / src/test/]
          ↓ (单向验证，正式代码严禁引用 src/test/)
[游戏业务层 · 垂直切片 / src/game/features/* (MSVP / MES)]
          ↓ (单向复用，shared/ 严禁反向引用 features/ 或 bootstrap/)
[游戏业务层 · 共享内核 / src/game/shared/ (model / service / component)]
          ↓ (仅面向 App.xxx / Bus / Base* 门面与 types/ 编程，严禁碰 impl/)
[框架与基础设施层 / src/framework/ (core / modules / infra / util)]
          ↓ (显式构造 DI 装配，零业务耦合、零资产耦合)
[Godot 4.7 引擎底层 / Engine & OS API]
```

### 六大依赖红线
1. **框架层零业务与资产耦合 (`R05`, `R07`, `R14`)**：`src/framework/` 下不得引用任何 `src/game/`、`src/test/` 或 `src/assets/` 路径，严禁出现具体项目名硬编码，严禁在框架层内写业务弹窗或 UI 遮罩（弹窗基类 `BaseDialog` 与 `DialogManager` 归属 `src/game/shared/component/dialog/`）。
2. **业务共享层三支柱与零向上依赖 (`R06`)**：`src/game/shared/` 一级目录严格锁定为单数三支柱 `model/`、`service/`、`component/`（遵循 **2+ 模块复用准入法则**），严禁反向依赖 `src/game/features/` 或 `src/game/bootstrap/`。
3. **框架模块显式构造注入 (`R08`, `R09`)**：`src/framework/modules/`、`infra/`、`util/` 内部**严禁调用 `App.xxx`**；15 大核心模块主实现类必须声明 `MODULE_ID`、`REQUIRED_MODULES`、`OPTIONAL_MODULES`，由唯一组合根 [`FrameworkRuntime`](../../../../src/framework/core/runtime/framework_runtime.gd) 显式构造注入并通过 [`RuntimeServiceHost.install()`](../../../../src/framework/core/runtime/impl/runtime_service_host.gd) 核对拓扑契约。
4. **私有实现绝对隔离 (`R10`)**：`src/game/` 及跨模块代码只允许引用公开门面（`Base*`）与公开数据契约（`types/`），**严禁**直接引用或实例化任何模块 `impl/` 下的内部类、Adapter 或 Driver。
5. **表现层与业务层职责正交**：`View` 节点只负责视觉排版、动效与发射交互 `signal`，严禁持有核心业务计算或直接调用 `App.storage` / `App.net`；`Service` / `Engine` 严禁直接查找或操作具体 UI 控件节点。
6. **全局类直呼，零冗余脚本别名 (`R15`)**：凡已声明 `class_name` 的脚本（如 `FileUtils`、`CryptoUtils`、`Result`、`BaseParams`），一律直接使用全局类名，**严禁**在 `src/` 下编写 `const _Xxx = preload("res://src/...")` 冗余别名。

---

## 2. 三级通信解耦规范

为防止工程随功能扩张演变为“网状强耦合”，通信严格收敛于以下 3 级：

| 通信级别 | 唯一合法通道 | 适用范围与规范要求 |
| :--- | :--- | :--- |
| **1. 父子节点 / P-V 级** | **下行调方法，上行发 `signal`** | • `Presenter ➔ View` / `父 ➔ 子`：直接调用公开方法（如 `_view.render_progress(...)`）；<br>• `View ➔ Presenter` / `子 ➔ 父`：仅发射过去分词信号（如 `signal retry_requested`），严禁 `get_parent().xxx()`。 |
| **2. 跨业务模块级** | **全局事件总线 (`Bus`)** | • 由 `Service` 层定义 `const EVENT_XXX: StringName = &"domain:event"` 并调用 `Bus.emit(...)`；<br>• 节点侧统一使用 `Bus.on_scoped(EVENT_XXX, self, _on_xxx)` 订阅，随节点退树自动解绑防泄漏。 |
| **3. 全局系统能力** | **服务定位器 (`App.xxx`)** | • 仅限 `src/game/` 与 `src/test/` 调用 15 大系统门面（`App.env`, `App.logger`, `App.clock`, `App.asset`, `App.input`, `App.haptic`, `App.net`, `App.auth`, `App.storage`, `App.locale`, `App.scene`, `App.display`, `App.cursor`, `App.audio`, `App.video`）。 |

---

## 3. 目录单复数、资产三轴与沙盒双层拓扑法则 (`R01 ~ R04`, `R14`, `R16`)

### 3.1 目录单复数黄金法则
- **领域 / 系统 / 能力 / 架构职能 ➔ 统一单数 (Singular)**：
  - `src/framework/`、`src/game/`、`src/test/`
  - `infra/async/`、`infra/cache/`、`infra/param/` (`R02`)、`infra/scheduler/`、`infra/shader/`、`infra/spine/`（FSM / BT / Debug 运行时归属独立零依赖插件 `addons/flow_graph/runtime/`）
  - `modules/logger/` (`R04`)、`modules/network/`（门面为 `App.net`，`R01`）等 15 个模块目录
  - `shared/model/`、`shared/service/`、`shared/component/` 及 Feature 内的 `model/`、`service/`、`engine/`、`presenter/`、`view/scene/<domain>/`、`view/component/<domain>/`
- **同质资源 / 切片集合 / 公开类型容器 ➔ 统一复数 (Plural)**：
  - `src/assets/textures/`、`src/assets/videos/` (`R03`)、`src/resources/envs/`、`src/resources/tables/`、`src/resources/defs/`、`src/game/features/`、`types/`、`drivers/`、`adapters/`、`tasks/`、`addons/`、`docs/`

### 3.2 运行时资产 (`src/assets/`) 三轴正交治理 (`R14`)
- **目录结构**：`src/assets/<媒介容器(复数)>/<架构域(单数: shared 或与 Feature 同名)>/[<分组>/]`（`audio/` 下先分 `bgm/ sfx/ vox/ amb/` 子容器再分架构域）。
- **文件命名**：`<type_prefix>_<domain>_<subject>[_<variant>][_<state>][_<index>].<ext>`，全小写 `snake_case`，且**文件名的 `<domain>` 段必须与所在架构域目录名完全一致**（如 `src/assets/textures/splash/btn_splash_retry_normal.svg`）。
- **引用边界**：`features/<f>/` 只允许引用 `<f>/` 与 `shared/` 域资产，严禁跨 Feature 私自引用；DCC 源文件（`.blend` / `.psd` / `.spine`）一律存放在仓库根 `art/`。

### 3.3 本地沙盒 (`user://`) 双层持久化与缓存拓扑 (`R16`)
- **一级生命周期分区（封顶 2 层目录 `user://<tier1>/<tier2>/<file>`）**：
  - `user://config/<domain>/`：设备级本地设置（明文 `.json`，不随云存档跨设备覆盖，由 `FileUtils.USER_CONFIG_DIR` 定义）；
  - `user://saves/<domain>/`：玩家核心进度存档（`.json` / `.sav`，支持压缩加密、`.tmp/.bak` 自愈与云同步，由 `FileUtils.USER_SAVES_DIR` 定义）；
  - `user://cache/<module>/`：可随时安全清空的衍生缓存（`cache/res/`、`cache/video/`、`cache/net/`）；
  - `user://tmp/<module>/`：原子写入与流式下载事务中转区（`tmp/storage/`）；
  - `user://logs/`：运行日志与 `logs/crash/` 崩溃现场快照。
- **业务层强制契约**：
  - `src/game/` 下**严禁出现裸 `"user://..."` 字符串字面量**；
  - 仅允许 `model/` 下的 `*_model.gd` 通过语义工厂 `StorageItem.for_config(STORAGE_DOMAIN, subject, version)` 或 `StorageItem.for_save(STORAGE_DOMAIN, subject, version, ext)` 构造存储项；
  - `shared/model/save/` 下 `STORAGE_DOMAIN` 必须为 `&"shared"`；`features/<f>/model/` 下 `STORAGE_DOMAIN` 必须为 `&"<f>"`。

---

## 4. GDScript 4.7 强类型、并发安全与性能铁律 (`R11 ~ R13`)

1. **100% 显式静态类型与安全 `Variant` 解包 (`R12`)**：
   - 所有函数形参、返回值（含 `-> void` / `-> Variant`）必须显式标注类型；未使用的重写形参或回调形参必须加 `_` 前缀（如 `_params: BaseParams = null`）。
   - 从 `Result.value`、`Dictionary.get()`、`Array` 取值时，**严禁直接用 `:=` 触发 `Variant` 隐式推导告警**，必须显式声明目标类型：`var tex: Texture2D = res.value as Texture2D` 或 `var count: int = int(dict.get("count", 0))`。
2. **可失败操作统一返回 `Result` 与零裸 `print()` (`R13`)**：
   - I/O、网络、加载等可失败方法统一返回 `Result`（错误码格式 `"{Module}.{Reason}"`）；
   - 全工程严禁残留原生 `print()`，统一使用 `App.logger.debug/info/warn/error(tag, msg)`（底层无注入处使用 `FrameworkLogger.print_raw`）。
3. **异步生命周期守卫 (`TaskScope`) 与基建收敛 (`R11`)**：
   - 场景与视图内的并发/延时任务统一绑定 `task_scope`（`gather` / `race` / `sleep`）或调用 `await TaskScope.wait(self, sec)`，严禁裸写 `create_timer` 后无实例校验直接访问节点导致 UAF 崩溃；
   - 文件编解码统一使用 `FileCodecUtils`，资源序列化统一使用 `ResourceCodecUtils`，骨骼池化统一使用 `SpinePool`（严禁使用已废弃的旧工具名）。
4. **高频标识拘留与防卡顿红线**：
   - 输入动作名、模块 ID、领域事件名、缓存/存储 Key、音频总线名一律使用 `StringName` (`&"..."`)；
   - `_process` / `_physics_process` 几何距离与扇形判定统一使用 `CoordUtils` 零开方方法；SFX 与已缓存资源读取走同步直通热路径。
