# Test Layer Architecture (功能测试层架构规范)

> `src/test/` 是与 `src/framework/`、`src/game/` 平级的功能测试与玩法原型验证层。
> 本层不引入额外的单元测试框架或复杂的测试基类，直接复用工程现有的 [`App`](../framework/core/autoload/app.gd) 独立启动机制、[`BaseScene`](../framework/modules/scene/base_scene.gd) 场景基类以及 [`_doc_game.md`](../game/_doc_game.md) 定义的垂直业务模块架构。

---

## 一、 顶层目录规范

`src/test/` 下按**被测功能域（单数名词）**划分垂直子目录，每个子目录对应一个可独立运行的功能测试模块：

```text
src/test/
├── _doc_test.md                 # 本架构规范文档
└── <feature_name>/              # 独立功能测试模块 (遵循单复数黄金法则，使用单数能力名，如 video/, audio/, dialog/)
```

---

## 二、 功能测试模块内部组织模式

根据被测功能的复杂度，每个 `src/test/<feature_name>/` 内部按需采用以下模式（拒绝为空文件创建多余目录）：

### 1. 轻量单场景模式（适用于单一接口或控件验证）

当仅需验证某个框架模块接口（如音频播放、存档读写）或通用 UI 组件（如弹窗、按钮）时，直接放置测试场景与脚本：

```text
src/test/<feature_name>/
├── _doc_<feature_name>.md       # [可选] 测试目的与验证项说明
├── <feature_name>_test.tscn     # 测试入口场景 (根节点继承 BaseScene，包含 $UI: BaseView)
├── <feature_name>_test.gd       # 测试场景脚本
└── assets/                      # [可选] 仅该测试模块专用的临时测试素材 (复数容器，命名见下方「测试素材规范」)
```

### 2. MSVP 交互模块模式（适用于复杂 UI 交互或玩法原型测试）

当测试模块包含完整的界面交互、多状态流转或新玩法原型验证时，直接采用与 `src/game/features/` 相同的 **MSVP (`model/` - `service/` - `view/` - `presenter/`)** 子目录分层：

```text
src/test/<feature_name>/
├── _doc_<feature_name>.md       # 测试模块说明与验证清单
├── assets/                      # [可选] 仅该测试模块专用的临时测试素材
├── model/                       # 数据与状态定义 (按 *Config / *Model / *State / *Params 后缀区分)
├── service/                     # 业务逻辑、被测能力编排与 App.* 调用
├── view/                        # 测试场景 (.tscn) 与视图节点脚本 (BaseScene / BaseView / BaseDialog)
└── presenter/                   # 连接 View 与 Service/Model 的中介胶水层
```

### 3. MES 算法模块模式（适用于纯数据与核心算法演算测试）

当测试聚焦于无复杂 UI 的数值公式、状态推演或生成算法时，采用 **MES (`model/` - `engine/` - `service/`)** 子目录分层，搭配一个极简入口场景在控制台（`App.logger`）或调试面板输出演算结果：

```text
src/test/<feature_name>/
├── _doc_<feature_name>.md       # 算法测试说明
├── model/                       # 领域状态 (*State) 与计算上下文 (*Context)
├── engine/                      # 纯净算法与规则推演 (*Engine)
├── service/                     # 测试用例编排与结果校验 (*Service)
└── <feature_name>_test.tscn     # 极简触发入口场景 (继承 BaseScene)
```

### 4. 测试素材规范 (`assets/`)

测试素材沿用 [`src/assets/_doc_assets.md`](../assets/_doc_assets.md) 的媒介容器与文件命名规则，但**省略架构域层级**（测试目录本身即架构域），文件名第 2 段使用测试模块名：

```text
src/test/office_3d/assets/
├── models/skm_office_3d_worker.glb
└── textures/tex_office_3d_floor_albedo.png
```

测试素材验证通过、需要转正时，迁入 `src/assets/<容器>/<feature>/` 并将域段改为正式 Feature 名。

---

## 三、 独立运行与调试机制

1. **编辑器一键运行（`F6`）**：
   - [`App`](../framework/core/autoload/app.gd#L60-L65) 内置 `_ensure_standalone_bootstrap()` 保底机制：当直接运行任何非 `BootstrapScene` 的测试场景时，会自动完成 `await App.bootstrap()` 装配全部 13 个框架底层服务并绑定当前场景路由。
   - 在 Godot 编辑器中打开任意 `src/test/<feature_name>/` 下的 `.tscn` 场景并按下 `F6`（运行当前场景），即可直接测试该功能。
2. **命令行运行**：
   ```bash
   # 直接指定被测功能场景运行
   /Applications/Godot.app/Contents/MacOS/Godot --path . res://src/test/<feature_name>/<feature_name>_test.tscn
   ```
3. **原型零成本转正**：
   - 采用 MSVP / MES 组织的功能测试或玩法原型在验证通过后，其 `model/`、`engine/`、`service/`、`view/`、`presenter/` 代码可直接平移至 `src/game/features/<feature_name>/`，无需二次重构。

---

## 四、 架构红线

1. **单向依赖铁律**：仅允许 `src/test/` 单向引用 `src/framework/` 与 `src/game/`；`src/framework/` 与 `src/game/` 的正式代码**严禁**引用 `src/test/` 下的任何脚本、场景或 `assets/` 测试素材。
2. **模块互不耦合**：`src/test/` 下的各个 `<feature_name>/` 测试目录彼此完全独立，**严禁**跨测试目录互相引用。
3. **基类与规范对齐**：测试场景根节点统一继承 [`BaseScene`](../framework/modules/scene/base_scene.gd)，顶层 UI 节点统一继承 [`BaseView`](../framework/modules/display/base_view.gd)，日志输出统一使用 `App.logger`，数据结构命名严格遵循 [`_doc_game.md`](../game/_doc_game.md) 的领域后缀规范。
