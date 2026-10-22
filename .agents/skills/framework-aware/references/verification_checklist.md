# Skill Wiki · 编码合规质量自查清单 (Verification Checklist)

> **Wiki 定位**：Agent 在开始编码前以及完成修改提交前，应按照本清单进行质量核验，确保代码 100% 符合项目架构约定。

---

## 阶段一：编码前自查 (Pre-Coding Check)

- [ ] **意图扫描**：是否已阅读用户需求并提取出涉及的框架系统关键词？
- [ ] **文档注入**：是否已命中 [keyword_matrix.md](keyword_matrix.md) 中的文档并执行了 `view_file` 查阅？
- [ ] **基类与模块结构确认**：
  - 新建场景是否继承 `BaseScene` 而非裸 `Node`？
  - 新建 UI 根节点是否继承 `BaseView` 且节点名为 `UI`？
  - 新建弹窗是否继承 `BaseDialog`（位于 `src/game/shared/component/dialog/`）并将具体业务弹窗放置在对应 Feature 的 `view/`？
  - 新建传参契约是否继承 `BaseParams`？
  - 新建业务 `features/<feature>/` 模块是否按交互特征采用 **MSVP** (`model/service/view/presenter`) 或 **MES** (`model/engine/service`) 子文件夹结构？
  - `model/` 下的数据类是否严格遵循领域后缀（`*Config`、`*Model`、`*State`、`*Params`、`*Context`、`*VO`）？
- [ ] **路径与命名**：
  - 引用视频资源是否使用 `src/assets/videos/`（复数）？
  - 引用参数基类是否使用 `src/framework/infra/param/`（单数）？
  - 引用业务共享内核是否使用 `src/game/shared/` 下的单数三支柱（`model/`、`service/`、`component/`）二级子域？
  - 引用日志服务是否使用 `App.logger`？

---

## 阶段二：编码中自查 (During-Coding Check)

- [ ] **服务调用**：
  - 网络调用是否使用 `App.net`（而非 `App.network` 或原生 `HTTPRequest`）？
  - 日志打印是否使用 `App.logger.xxx(tag, message)`（严禁裸 `print`）？
  - 音效与背景音乐是否使用 `App.audio`（严禁裸调 `AudioServer`）？
- [ ] **交互反馈**：
  - 界面按钮是否使用 `BaseTextureButton`（严禁自行手写 Tween 缩放和点击音效代码）？
  - 弹窗弹出是否使用 `DialogManager.open(...)`？
- [ ] **分层解耦**：
  - 业务层代码是否通过 Signal 向上抛出事件，而不是强行查找 UI 节点？
  - 跨系统解耦广播是否使用 `Bus.emit(...)` 与 `Bus.on(...)`？
  - 工具类调用是否使用了 `src/framework/util/` 提供的现成静态工具函数？

---

## 阶段三：编码后自查 (Post-Coding Check)

- [ ] **自动化合规与全量语法核验**：运行合规与语法扫描脚本（已内置 Godot Headless 全量 `.gd` 编译校验）：
  ```pwsh
  pwsh .agents/skills/framework-aware/scripts/check_compliance.ps1
  # 或 Shell 版本:
  bash .agents/skills/framework-aware/scripts/check_compliance.sh
  ```
- [ ] **全局类名刷新（仅当新增 `class_name` 时）**：
  ```pwsh
  & "D:\software\Godot\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --editor --quit
  ```
- [ ] **文档一致性**：若新增或重构了公共接口/目录，是否已同步更新对应的 `_doc_*.md` 文档？
- [ ] **回复声明**：是否在回复开头显式声明了加载的 Skill 与注入的文档清单？
