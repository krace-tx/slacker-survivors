# Addon · ExportIgnore (`.exportignore` 极简打包隔离插件)

> 像写 `.gitignore` 一样管理 Godot 导出裁剪：在编辑器内所有测试场景与研发工具 **100% 正常可见、随时按 `F6` 调试**；打包导出 PCK 时自动读取项目根目录 [`.exportignore`](../../.exportignore) 物理剥离匹配文件及 `.godot/imported/` 关联缓存，且插件自身运行期 **0 字节残留**。

```text
.exportignore                                    # [唯一配置入口] 根目录纯文本规则文件（按需克制添加）
addons/build_isolation/
├── _doc_build_isolation.md                      # 本文档
├── plugin.cfg                                   # Godot 插件注册清单
├── plugin.gd                                    # 极简门面：挂载导出插件 + Tools 控制台预览入口
└── core/
    ├── export_ignore_matcher.gd                 # .exportignore 解析与通配编译引擎 (ExportIgnoreMatcher)
    ├── build_isolation_exporter.gd              # EditorExportPlugin 导出拦截器 (BuildIsolationExporter)
    └── reverse_dependency_scanner.gd            # 保留代码误引用剥离文件的后台断路检查器 (ReverseDependencyScanner)
```

---

## 一、 当前默认隔离范围（克制按需原则）

根目录 [`.exportignore`](../../.exportignore) 遵循 **YAGNI（有明确需求时再添加）** 原则，当前仅隔离：
1. **测试与演练目录**：`src/test/`
2. **纯编辑器研发与 AI 辅助插件（共 5 个，运行期 0 依赖）**：
   - `addons/build_isolation/`（本打包隔离插件自身）
   - `addons/godot_mcp/`（Godot MCP 编辑器通信服务）
   - `addons/blender_mcp/`（Blender MCP 建模辅助服务）
   - `addons/scene_define_generator/`（编辑器开发期场景常量生成面板）
   - `addons/locate_in_filesystem/`（编辑器文件系统快捷定位工具）

> **不处理的运行时/混合插件**：`ffmpeg`、`video_player_android`、`video_player_ios`、`spine_godot`、`godotsteam`、`flow_graph` 均承载运行时扩展或业务内核，保持原样完整保留。

---

## 二、 `.exportignore` 扩展语法速查（后续按需使用）

直接修改根目录 [`.exportignore`](../../.exportignore)，自上而下顺序求值，**最后一条命中的规则决定去留**：

| 写法示例 | 含义 |
| :--- | :--- |
| `# 注释` | 注释行（忽略） |
| `src/test/` | 剥离 `res://src/test/` 整个目录及其所有子文件 |
| `*.md` / `*.psd` | 剥离任意目录下的指定后缀文件（跨层支持 `**`） |
| `!src/test/keep.tscn` | **`!` 取反白名单**：在前序忽略规则下重新放行指定文件或子目录 |
| `[prod]` / `[demo]` | **条件段落**：仅当导出预设 `Features` 包含该标签时追加生效（支持 `[a, b]`、`[a & !b]`、`[all]`） |
