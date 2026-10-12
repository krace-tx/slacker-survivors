class_name TranslationServerAdapter
extends RefCounted

## 引擎边界适配器：封装 Godot [TranslationServer] 的交互（私有实现，仅供 [LocaleService] 使用）。[br]
## 隔离引擎多语言服务原生 API，提供强类型与标准化的接口。

## 获取已加载的语言代码列表
func get_loaded_locales() -> PackedStringArray:
	return TranslationServer.get_loaded_locales()


## 设置引擎当前活跃语言代码
func set_locale(locale: String) -> void:
	TranslationServer.set_locale(locale)


## 获取引擎当前活跃语言代码
func get_locale() -> String:
	return TranslationServer.get_locale()


## 标准化语言代码格式
func standardize_locale(locale: String) -> String:
	return TranslationServer.standardize_locale(locale)


## 比较两门语言的匹配相似度（0 ~ 10，10 为完全匹配）
func compare_locales(locale_a: String, locale_b: String) -> int:
	return TranslationServer.compare_locales(locale_a, locale_b)
