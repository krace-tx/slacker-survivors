# Slacker Survivors - 项目文档总览 (Docs Overview)

欢迎查阅 **Slacker Survivors** 项目文档。本项目文档采用**具有独立语义的命名**，避免多标签页混淆与搜索冲突。

---

## 📚 文档模块导航

```
docs/
├── docs_overview.md                 # 🧭 全局文档总览与索引入口
│
├── architecture/                    # 🏛️ 1. 项目架构模块
│   └── architecture_design.md       # 系统分层、解耦通信、数据流向与技术规范
│
├── design/                          # 🎮 2. 策划架构模块
│   └── game_design.md               # 核心玩法循环、武器技能树、波次与数值体系
│
└── deployment/                      # ⚙️ 3. 构建部署模块
	└── deployment_guide.md          # 运行环境依赖、多端导出规范与 CI/CD 自动化
```

| 模块与色彩 | 颜色标识 (FileSystem) | 核心内容 | 适用角色 | 快速入口 |
| :--- | :--- | :--- | :--- | :--- |
| **项目架构** | 🟣 `purple` (紫色 / 严谨底座) | 系统分层、模块解耦、通信总线、编码规范 | 客户端程序、架构师、AI Agent | [进入项目架构文档](file:///d:/code/GodotProject/slacker-survivors/docs/architecture/architecture_design.md) |
| **策划架构** | 🟠 `orange` (橙色 / 创意活力) | 核心循环、战斗系统、技能树、数值与波次规则 | 游戏策划、数值、关卡设计 | [进入策划架构文档](file:///d:/code/GodotProject/slacker-survivors/docs/design/game_design.md) |
| **构建部署** | 🩵 `teal` (青色 / 工程稳定) | 导出模板配置、多端打包流程、CI/CD 与发布 | 技术美术、运维、打包发布人员 | [进入构建部署文档](file:///d:/code/GodotProject/slacker-survivors/docs/deployment/deployment_guide.md) |

---

## 🎨 FileSystem 文件树色彩设计规范 (Color System)

在 Godot 编辑器左侧 `FileSystem (文件系统)` 面板中，已为 `src` 外部及各大核心模块配置了统一的视觉色相：

### 1. 外层宏观模块 (Outside src)

| 目录路径 | 预设色值 | 视觉含义与设计意图 |
| :--- | :--- | :--- |
| `res://docs/` | 🔵 **Blue (蓝色)** | 文档知识中心，统领全局规范 |
| ├─ `architecture/` | 🟣 **Purple (紫色)** | 技术架构与基类契约，象征严谨与抽象骨架 |
| ├─ `design/` | 🟠 **Orange (橙色)** | 策划与核心玩法，象征创造力与战斗热度 |
| └─ `deployment/` | 🩵 **Teal (青色)** | 构建与发布管线，象征工程交付与稳定性 |
| `res://src/` | 🟢 **Green (绿色)** | 业务研发核心源码根目录 |
| `res://addons/` | ⚪ **Gray (灰色)** | 第三方外部插件与工具包，辅助底层依赖 |

### 2. src 内部二级模块 (Inside src)

| 目录路径 | 预设色值 | 模块定位与视觉逻辑 |
| :--- | :--- | :--- |
| `res://src/game/` | 🔴 **Red (红色)** | **核心业务/玩法逻辑**：英雄、怪物、技能、战斗计算等最常修改的业务代码 |
| `res://src/framework/` | 🟣 **Purple (紫色)** | **框架基础设施**：生命周期、事件总线、App 聚合服务（与架构同频） |
| `res://src/assets/` | 🟡 **Yellow (黄色)** | **美术与视听资产**：材质贴图、音频音效、字体及美术工程文件 |
| `res://src/resources/` | 🩵 **Teal (青色)** | **静态配置与数据实体**：Godot Resource 实体定义与数值配置表 |
| `res://src/test/` | 🩷 **Pink (粉色)** | **测试沙盒与验证场景**：单元测试、功能 Demo，醒目防误入生产 |



---

## 🧭 文档命名与维护原则

1. **拒绝通用命名**：文档一律使用**具体业务/模块全称**（如 `architecture_design.md`、`game_design.md`），不使用 `README.md` 或 `index.md`，确保 IDE 标签页与模糊搜索（Ctrl+P）一眼可辨。
2. **宏观与微观分工**：
   - `docs/` 负责宏观设计原则、系统拓扑、玩法机制与构建步骤；
   - `src/` 内部代码附带的 `_doc_*.md` 负责微观接口定义与类使用约束。
3. **图文结合**：涉及复杂流转、状态机或网络流程时，优先使用 Mermaid 图表直观呈现。
4. **及时更新**：涉及系统重大重构、玩法规则变动或打包管线变更时，代码与文档需同步提交。
