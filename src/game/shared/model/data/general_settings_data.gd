class_name GeneralSettingsData
extends BaseParams

## 语言与通用偏好设置子数据块（位于 src/game/shared/model/data/）。[br]
##
## [b]核心职责：[/b][br]
## 1. 承载多语言区域标识（BCP-47 标签，如 `"zh-CN"` / `"en-US"`）；[br]
## 2. 支持首次启动自动读取宿主操作系统语言（`OS.get_locale()`）并映射至受支持语言表。


#region 常量与成员属性

const DEFAULT_LOCALE: String = "zh-CN"

## 语言区域标识（BCP-47 标签，如 "zh-CN" / "en-US"；为空时首次启动自动匹配 OS 语言）
var locale: String = ""

#endregion


#region 公开方法

## 对语言区域标签执行非空校验与系统默认语言自愈，返回自身支持链式调用。
func sanitize() -> GeneralSettingsData:
	if locale.is_empty():
		locale = resolve_os_default_locale()
	return self


## 重置当前通用数据块为系统默认语言。
func reset() -> void:
	locale = resolve_os_default_locale()


## 根据当前操作系统环境自动推导最匹配的受支持语言标签。
static func resolve_os_default_locale() -> String:
	var os_tag: String = OS.get_locale().replace("_", "-")
	if LocaleConfig.language_from_tag(os_tag) >= 0:
		return os_tag
	var lang_prefix: String = os_tag.split("-")[0].to_lower()
	match lang_prefix:
		"zh":
			return "zh-TW" if (os_tag.contains("TW") or os_tag.contains("HK")) else "zh-CN"
		"en":
			return "en-US"
		"ja":
			return "ja-JP"
		"ko":
			return "ko-KR"
		_:
			return DEFAULT_LOCALE

#endregion
