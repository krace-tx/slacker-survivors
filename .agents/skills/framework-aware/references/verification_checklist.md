# Skill Wiki · 编码合规质量自查清单 (Verification Checklist)

> **Wiki 定位**：Agent 在开始编码前、编码过程中以及完成修改提交前，必须按照本清单进行质量核验，确保代码与文档 100% 通过 **R01 ~ R16** 自动化合规门禁。

---

## 阶段一：编码前自查 (Pre-Coding Check)

- [ ] **意图扫描与文档注入**：是否已命中 [keyword_matrix.md](keyword_matrix.md) 中的文档并真实读取了对应 `_doc_*.md` 或 [module_and_doc_design.md](module_and_doc_design.md)？
- [ ] **架构分层与目录选型 (`R02`, `R03`, `R04`, `R06`)**：
  - 新建框架模块是否遵循 `base_<role>.gd` + `types/` + `impl/` 四层结构？
  - 新建业务 `features/<feature>/` 是否按是否有 UI 交互选定 **MSVP** (`model/service/view/presenter`) 或 **MES** (`model/engine/service`)？
  - `view/` 下的场景与预制体是否按 `view/scene/<domain>/` 与 `view/component/<domain>/` 领域单元文件夹（`1 .tscn + N .gd`）包裹，且未使用赘述的 `_component` 后缀？
  - 放入 `src/game/shared/` 的代码是否满足 **2+ 模块复用铁律**，且归属在 `model/`、`service/`、`component/` 单数三支柱下？
- [ ] **基类与数据后缀确认**：
  - 顶层场景是否继承 `BaseScene`？场景内 UI 根节点是否继承 `BaseView` 且节点名为 `UI`？模态弹窗是否继承 `BaseDialog`？
  - `model/` 下的数据类是否遵循“一类一文件 (`1 class_name = 1 .gd`)”并采用 7 大标准后缀（`*Config`、`*Req`/`*Resp`、`*Model`、`*State`、`*Data`、`*Params`、`*Context`）？
- [ ] **资产与沙盒路径确认 (`R14`, `R16`)**：
  - 新增/引用的资产是否位于 `src/assets/<媒介容器>/<架构域>/`，文件名是否符合 `<prefix>_<domain>_<subject>` 且 `<domain>` 与目录一致？
  - 本地持久化是否仅在 `*_model.gd` 中通过 `StorageItem.for_config()` 或 `StorageItem.for_save()` 声明，且 `STORAGE_DOMAIN` 与目录域（`&"shared"` 或 `&"<feature>"`）完全一致？

---

## 阶段二：编码中自查 (During-Coding Check)

- [ ] **依赖方向与门面边界 (`R01`, `R05`, `R07`, `R08`, `R09`, `R10`)**：
  - `src/framework/` 内部是否严守零 `src/game/`、零 `src/test/`、零 `src/assets/` 引用？
  - `src/framework/modules/`、`infra/`、`util/` 内部是否严守**零 `App.xxx` 调用**（全部依赖由 `FrameworkRuntime` 构造注入）？
  - `src/game/` 是否只引用了模块的 `Base*` 公开门面与 `types/`，**零 `impl/` 私有类引用**？
  - `src/game/` 是否严守**零 `"user://..."` 裸路径字符串**？
- [ ] **强类型与现代 GDScript 语法 (`R11`, `R12`, `R13`, `R15`)**：
  - 所有函数参数与返回值是否 100% 显式声明类型（含 `-> void` / `-> Variant`）？未使用的形参是否已加 `_` 前缀？
  - 从 `Result.value`、`Dictionary.get()`、`Array` 解包时，是否使用了显式类型声明（如 `var x: Type = val as Type`），杜绝 `:=` 触发 `Variant` 推导告警？
  - 引用已声明 `class_name` 的脚本时，是否**直接使用全局类名**，零 `const _Xxx = preload("res://src/...")` 冗余别名？
  - 日志输出是否统一使用 `App.logger.<level>(tag, msg)`，零原生 `print()` 残留？
  - 界面异步操作是否绑定了宿主 `task_scope` 或 `TaskScope.wait(self, sec)` 防 UAF？事件总线订阅是否优先使用 `Bus.on_scoped(...)`？

---

## 阶段三：编码后自查 (Post-Coding Check)

- [ ] **全量自动化合规与静态编译门禁**：运行跨平台 Python 合规引擎（内置 `R01 ~ R16` 架构规则与 Godot Headless 全量脚本静态编译校验），确保 **0 errors, 0 warnings**：
  ```bash
  # 运行全量 16 项检查（含 GDScript 编译检查）
  python .agents/skills/framework-aware/scripts/check_compliance.py

  # 仅快速运行指定规则（例如 R14 资产治理 + R16 沙盒持久化）
  python .agents/skills/framework-aware/scripts/check_compliance.py --rule R14 --rule R16
  ```
- [ ] **文档与索引同步**：
  - 若新增或重构了模块、接口、目录或契约，是否已同步编写/更新对应的 `_doc_*.md` 与 `##` BBCode 注释？
  - 若新增了 `_doc_*.md`，是否已登记至 [keyword_matrix.md](keyword_matrix.md)？
- [ ] **回复声明契约**：是否在回复最顶部输出了标准 `framework-aware` 激活与已查阅文档声明框？
