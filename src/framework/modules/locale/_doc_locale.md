# Framework · Locale

## 核心

表由引擎把 CSV 导入成 `.translation`，再经项目设置挂到 `TranslationServer`。本服务只选语言并经 `TranslationServerAdapter` 切换。

查词不经本服务：静态 UI 走 Auto Translate，动态文案直接 `tr()` / `tr_n()`。

---

## 细节

- 入口：`App.locale`（`BaseLocalizationSystem`），boot 时 `initialize()`。语言必须已在项目设置里加载，否则 `set_language` 返回 `Result.err`。
- 启动选语言：`LocaleConfig.default_language`（英文 `EN_US`）→ 设备语言 → 已加载的第一门。
- 切语言成功后发 `Bus.locale_changed`。静态控件由引擎重绘；带参数的 `text` 要自己再赋一次。
- 唯一字典：`res://src/assets/translations/i18n.csv`。`LocaleConfig` 只回答表路径和默认语言，不进 `RuntimeEnvironment`。
- 表里**只留仍被 tscn / `tr()` 引用的 key**。删场景或改文案时同步删行。
- key 与贴图同构：`{scene}_{slot}`，小写蛇形，全局不重复。`scene` 为 launcher / lobby / level / gallery / leaderboard / common / popup_*。占位符写在译文里（`%d` / `%s`），不写进 key。静态控件把 key 填进 `text` 走 Auto Translate；带参数或拼接（如省略号）用 `tr("key")`。
- `_tscn` 列是给人看的：相对 `src/game/scenes/` 的场景路径，多个用 `|` 分隔。列名以下划线开头，引擎当注释丢掉，不生成语言包。

```text
src/framework/modules/locale/
├── _doc_locale.md                     # 本文档
├── base_localization_system.gd        # 公开门面契约 BaseLocalizationSystem (App.locale，详尽注释)
│
├── types/                             # [公开契约]
│   └── locale_config.gd               # 配置对象：csv_path、default_language、Language 枚举
│
└── impl/                              # [私有收敛]
    ├── localization_system.gd         # 门面实现：initialize / set_language
    └── translation_server_adapter.gd  # 引擎适配器：封装 TranslationServer 原生 API
```

---

## 样例

```gdscript
App.locale.set_language(LocaleConfig.Language.EN_US)

func _ready() -> void:
	Bus.locale_changed.connect(_refresh_describe)
	_refresh_describe()

func _refresh_describe() -> void:
	_describe.text = "%s %s" % [tr("launcher_loading"), ".".repeat(_dot_count)]
```
