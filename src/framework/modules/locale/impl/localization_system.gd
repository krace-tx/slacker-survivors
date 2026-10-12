class_name LocalizationSystem
extends BaseLocalizationSystem

## 多语言本地化系统。表由项目设置挂到引擎；这里只选语言并经 [TranslationServerAdapter] 切换。[br]
##
## 静态 UI：原生控件 text 填 key，保持 Auto Translate。[br]
## 动态文案：直接 [method Object.tr] / [method Object.tr_n]，再 [code]%[/code] 填值。[br]
## 切语言后发 [signal EventBus.locale_changed]。

#region State
var _config: LocaleConfig
var _adapter: TranslationServerAdapter
#endregion

#region Lifecycle
func _init(adapter: TranslationServerAdapter = null) -> void:
	_adapter = adapter if adapter != null else TranslationServerAdapter.new()
#endregion

#region Public API
## 读取已挂载的表，选定初始语言。[param config] 为空则用 [LocaleConfig] 默认值。
func initialize(config: LocaleConfig = null) -> Result:
	_config = config if config != null else LocaleConfig.new()
	languages.clear()
	for locale in _adapter.get_loaded_locales():
		var language := _match_language(locale, _all_languages(), 10)
		if language >= 0 and language not in languages:
			languages.append(language as LocaleConfig.Language)
	if languages.is_empty():
		push_warning("LocaleService: No translations in Project Settings > Localization. Running in fallback mode with default language.")
		current_language = _config.default_language
		languages.append(_config.default_language)
		return Result.ok()

	var start := _pick_start_language()
	if start < 0:
		current_language = _config.default_language
		return Result.ok()
	return set_language(start as LocaleConfig.Language)


## 切换当前语言。成功后发 [signal Bus.locale_changed]。
func set_language(language: LocaleConfig.Language) -> Result:
	if language not in languages:
		return Result.err_code("Locale.NotLoaded", "Set language failed: language is not loaded.")
	var locale := _godot_locale(language)
	if current_language == language and _adapter.get_locale() == locale:
		return Result.ok()
	current_language = language
	_adapter.set_locale(locale)
	Bus.locale_changed.emit()
	return Result.ok()
#endregion

#region Internal
func _godot_locale(language: LocaleConfig.Language) -> String:
	return _adapter.standardize_locale(LocaleConfig.locale_tag(language))


func _all_languages() -> Array[LocaleConfig.Language]:
	var out: Array[LocaleConfig.Language] = []
	for i in LocaleConfig.Language.size():
		out.append(i as LocaleConfig.Language)
	return out


## 比较语言相似度，最高分且不低于 [param min_score]（10 为完全匹配）。
func _match_language(locale: String, candidates: Array[LocaleConfig.Language], min_score: int) -> int:
	var best := -1
	var best_score := 0
	for language in candidates:
		var score := _adapter.compare_locales(locale, _godot_locale(language))
		if score > best_score:
			best_score = score
			best = language as int
	return best if best_score >= min_score else -1


## [member LocaleConfig.default_language] → 设备语言 → 已加载第一门。
func _pick_start_language() -> int:
	if _config != null and _config.default_language in languages:
		return _config.default_language as int
	var system := _match_language(OS.get_locale(), languages, 1)
	if system >= 0:
		return system
	if not languages.is_empty():
		return languages[0] as int
	return -1
#endregion
