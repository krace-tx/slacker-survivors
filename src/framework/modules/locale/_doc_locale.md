# Framework · Locale (多语言本地化与区域匹配系统)

> 统一管理游戏运行时语言环境切换、BCP-47 标准语言标签映射与启动期智能语言匹配（`App.locale` / [`BaseLocalizationSystem`](base_localization_system.gd)）。
> 遵循**「切换归服务，查词归引擎」**原则：多语言 CSV 由 Godot 引擎导入为 `.translation` 并注册至 `Project Settings > Localization`；本模块仅负责通过 [`TranslationServerAdapter`](impl/translation_server_adapter.gd) 探测已加载语言包、切换活跃 Locale 并广播 [`Bus.locale_changed`](../../core/autoload/event_bus.gd)。

```text
src/framework/modules/locale/
├── _doc_locale.md                     # 本文档
├── base_localization_system.gd        # 公开门面契约 BaseLocalizationSystem (App.locale，详尽注释)
│
├── types/                             # [公开契约]
│   └── locale_config.gd               # 语言配置资源与枚举 (LocaleConfig: 17 种 Language 枚举与 BCP-47 双向映射)
│
└── impl/                              # [私有实现收敛]
    ├── localization_system.gd         # 门面实现 (LocalizationSystem: 启动语言探测、相似度匹配与安全降级)
    └── translation_server_adapter.gd  # 引擎边界适配器：隔离 Godot TranslationServer 原生 API
```

---

## 一、 核心工程设计机制

1. **职责边界与零耦合依赖 (`MODULE_ID = &"locale"`)**：
   - `REQUIRED_MODULES = []`，`OPTIONAL_MODULES = []`。
   - 静态 UI 控件直接将文案 Key 填入 `text` 属性并开启引擎 `Auto Translate`；带动态占位符（`%s` / `%d`）的文案直接调用 `tr("key")` / `tr_n(...)`，切语言时监听 `Bus.locale_changed` 重新格式化即可。
2. **17 种主流发行语言枚举与 BCP-47 标签双向映射 (`LocaleConfig`)**：
   - 内置 `LocaleConfig.Language` 枚举（`ZH_CN`, `ZH_TW`, `EN_US`, `JA`, `KO`, `ES`, `PT_BR`, `FR`, `DE`, `IT`, `RU`, `PL`, `TR`, `AR`, `TH`, `VI`, `ID`）。
   - 提供静态 `LocaleConfig.locale_tag(lang) -> String`（如 `Language.ZH_CN -> "zh-CN"`）与 `LocaleConfig.language_from_tag(tag) -> int`（供 [`GameSettingsService.apply_locale()`](../../../game/shared/service/settings/game_settings_service.gd) 从持久化设置还原语言枚举）。
3. **三级启动语言决策链与无表安全降级 (`initialize`)**：
   - 启动时扫描 `TranslationServer.get_loaded_locales()`，通过 `compare_locales`（阈值 `10` 精确匹配）构建当前已挂载的可用语言列表 `App.locale.languages`。
   - **无配置安全保底（Fallback Mode）**：若工程尚未在项目设置中挂载任何 `.translation` 文件，自动记录警告并将 `default_language`（默认 `EN_US`）加入 `languages` 保底返回 `Result.ok()`，绝不阻断开发期启动。
   - **初始语言优先级**：`LocaleConfig.default_language`（若在已加载列表中） $\rightarrow$ 操作系统语言 `OS.get_locale()`（相似度评分 $\ge 1$ 的最佳匹配） $\rightarrow$ 已加载列表首门语言 `languages[0]`。
4. **幂等切换与标准错误契约 (`set_language`)**：
   - 若请求的 `language` 未在 `App.locale.languages` 中加载，显式返回 `Result.err_code("Locale.NotLoaded", ...)`。
   - 若目标语言与当前已生效语言一致，直接幂等返回 `Result.ok()`，不重复触发 `Bus.locale_changed` 重绘。
5. **多语言 CSV 表维护约定**：
   - 唯一字典表首列为 `key`，后续列为语言代码（如 `zh_CN`、`en_US`）；以下划线开头的列（如 `_feature` / `_tscn`，记录相对于 `src/game/features/` 的消费路径）会被引擎自动视作注释忽略，不打入语言包。
   - Key 命名推荐遵循 `{feature}_{slot}` 小写蛇形（如 `splash_loading`、`lobby_start_btn`），保持全局唯一。

---

## 二、 使用范式

```gdscript
# 1. 切换当前游戏语言（返回 Result，成功后自动广播 Bus.locale_changed）
var res := App.locale.set_language(LocaleConfig.Language.ZH_CN)
if res.is_err():
	App.logger.warn("Locale", "[%s] %s" % [res.error_code(), res.error_message()])

# 2. 通过 GameSettingsService 持久化并同步多语言偏好
var settings := GameSettingsService.get_current()
settings.locale = LocaleConfig.locale_tag(LocaleConfig.Language.ZH_CN) # "zh-CN"
GameSettingsService.apply_locale(settings)
await GameSettingsService.save_async()

# 3. 含有动态参数的 UI 文本响应语言热切换
func _ready() -> void:
	Bus.locale_changed.connect(_refresh_wave_title)
	_refresh_wave_title()

func _refresh_wave_title() -> void:
	wave_label.text = tr("battle_wave_progress") % [current_wave, max_wave]
```
