# 🤖 Slacker Survivors · Agent 自定义体系与 Skill Wiki

本目录遵循 **Google Antigravity Customization System** 规范，为项目量身定制 AI Agent（如 Antigravity / Cursor / Claude Code 等）的专业能力包、知识库与确定性质量门禁。

---

## 目录组织结构

```text
.agents/
├── README.md                                  # 本文档：Agent 自定义体系总览
└── skills/                                    # 项目专属技能库 (Workspace Skills)
    ├── framework-aware/                       # [技能 1] 框架感知编码技能 (Skill Wiki)
    │   ├── SKILL.md                           # 技能入口、触发条件与渐进式披露导航
    │   ├── references/                        # 核心规范 Wiki 知识库
    │   │   ├── keyword_matrix.md              # 关键词 ➔ 文档路由矩阵
    │   │   ├── architecture_rules.md          # 架构分层、通信与单复数铁律
    │   │   └── verification_checklist.md      # 编码前/中/后自查清单
    │   ├── examples/                          # Few-Shot 范例库
    │   │   └── code_patterns.md               # 场景/UI/按钮/服务正反范式对比
    │   └── scripts/                           # 确定性自动化扫描与语法编译门禁
    │       ├── check_compliance.py            # 架构合规性 + 全量 GDScript 编译检查 (跨平台 Python)
    │       └── check_syntax.gd                # Godot Headless 全量 GDScript 语法与静态类型扫描器
    │
    └── blender-pipeline/                      # [技能 2] 工业级 Blender 3D 资产自动化生产与验证管线
        ├── SKILL.md                           # 六步闭环管线入口 (Spec ➔ Generate ➔ Execute ➔ Verify ➔ Repair ➔ Deliver)
        ├── references/                        # 3D 建模、材质灯光、骨骼动画与 Godot 导出规范库
        │   ├── api_reliability.md             # Blender 4.x/5.0 Python API 兼容铁律
        │   ├── concept_and_lookdev_workflow.md# 概念设定与 LookDev 卡片审视工作流
        │   ├── godot_export_contract.md       # glTF/GLB 导出至 Godot 4 契约规范
        │   ├── highpoly_character_pipeline.md # 高模角色雕刻与拓扑生产管线
        │   ├── materials_and_lighting.md      # PBR 材质节点与三点布光规范
        │   ├── procedural_modeling.md         # 程序化 BMesh 几何建模规范
        │   ├── rigging_and_animation.md       # 骨骼装配、权重绑定与 NLA 动作规范
        │   └── scene_hierarchy_architecture.md# 场景层级命名与坐标轴心契约
        ├── examples/                          # 3D 资产脚本正反范式
        │   └── asset_patterns.md              # 标准程序化建模与材质脚本范例
        └── scripts/                           # 确定性几何/材质体检与 LookDev 渲染脚本
            ├── high_precision_refiner.py      # 高精度几何细分与平滑精修器
            ├── render_lookdev_card.py         # 多视角 LookDev 审视卡渲染器
            ├── run_pipeline_gate.sh           # 一键执行 Blender 资产体检与导出门禁
            └── verify_blender_asset.py        # 网格流形、法线、UV、材质与轴心自动化校验器
```

---

## 核心设计理念：Skill Wiki 渐进式披露 (Progressive Disclosure)

为避免海量 prompt 一次性撑爆 Agent 的上下文窗口（Context Window），本工程全面贯彻 **渐进式披露** 原则：

1. **第一层 (Router/Frontmatter)**：
   - Agent 默认仅读取各技能 `SKILL.md` 的 YAML Frontmatter（`name` 与 `description`），按语义判断是否需要激活技能。
2. **第二层 (Index/SKILL.md)**：
   - 技能被激活后，Agent 加载轻量级 `SKILL.md`，执行标准化判定流，获取知识索引链接。
3. **第三层 (Deep Wiki/references & examples)**：
   - Agent 仅在需要明确特定领域规范时，点对点读取 `references/` 中的路由矩阵或 `examples/` 中的代码正反范例。
4. **第四层 (Deterministic Tools/scripts)**：
   - 杜绝纯 LLM 猜测，通过执行 `scripts/` 中的自动化脚本，确定性地校验架构合规性、GDScript 静态类型编译与 3D 资产几何指标。

---

## 快速自测

在日常编码或重构后，可通过执行以下跨平台指令进行一键合规性与全项目 GDScript 语法编译验证：

```bash
# Windows / macOS / Linux (Python 3)
python .agents/skills/framework-aware/scripts/check_compliance.py
```
