# 🤖 Slacker Survivors · Agent 自定义体系与 Skill Wiki

本目录遵循 **Google Antigravity Customization System** 规范，为项目量身定制 AI Agent（如 Antigravity / Cursor / Claude Code 等）的专业能力包、知识库与行为约束。

---

## 目录组织结构

```text
.agents/
├── README.md                      # 本文档：Agent 自定义体系总览
└── skills/                        # 项目专属技能库 (Workspace Skills)
    └── framework-aware/           # 框架感知编码技能 (Skill Wiki)
        ├── SKILL.md               # 技能入口、触发条件与渐进式披露导航
        ├── references/            # 核心规范 Wiki 知识库
        │   ├── keyword_matrix.md          # 关键词 ➔ 文档路由矩阵
        │   ├── architecture_rules.md      # 架构分层、通信与单复数铁律
        │   └── verification_checklist.md  # 编码前/中/后自查清单
        ├── examples/              # Few-Shot 范例库
        │   └── code_patterns.md           # 场景/UI/按钮/服务正反范式对比
        └── scripts/               # 确定性自动化扫描工具
            └── check_compliance.ps1       # 框架与架构合规性自检脚本
```

---

## 核心设计理念：Skill Wiki 渐进式披露 (Progressive Disclosure)

为避免海量 prompt 一次性撑爆 Agent 的上下文窗口（Context Window），本工程全面贯彻 **渐进式披露** 原则：

1. **第一层 (Router/Frontmatter)**：
   - Agent 默认仅读取各技能 `SKILL.md` 的 YAML Frontmatter（`name` 与 `description`），按语义判断是否需要激活技能。
2. **第二层 (Index/SKILL.md)**：
   - 技能被激活后，Agent 加载轻量级 `SKILL.md`，执行 5 步判定流，获取知识索引链接。
3. **第三层 (Deep Wiki/references & examples)**：
   - Agent 仅在需要明确特定知识时，点对点读取 `references/` 中的路由矩阵或 `examples/` 中的代码正反范例。
4. **第四层 (Deterministic Tools/scripts)**：
   - 杜绝纯 LLM 猜测，通过执行 `scripts/` 中的自动化脚本，确定性地校验代码合规性。

---

## 快速自测

在日常编码或重构后，可通过执行以下指令进行合规性验证：

```pwsh
# 运行项目合规性扫描
pwsh .agents/skills/framework-aware/scripts/check_compliance.ps1

# 运行 Godot 引擎静态编译检查
& "D:\software\Godot\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe" --headless --editor --quit
```
