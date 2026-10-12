class_name LocaleConfig
extends Resource

## 多语言表：一份 CSV 的路径，以及缺省语言。
##
## 表格式：首列 key，其后是语言代码（[code]zh_CN[/code]、[code]en_US[/code]）。
## 以下划线开头的列（如 [code]_tscn[/code]）是注释，引擎不导入，不影响 [method tr] / Auto Translate。
## CSV 由引擎导入，并在项目设置 Localization 里注册；本资源只回答「表在哪、默认哪门」。
## 切语言走 [LocaleService]。各环境用不同 [code].tres[/code]，不写进 [EnvService]。

#region Constants & Enums
## 主流游戏发行语言；表头里出现的列才会启用。
enum Language {
	ZH_CN, ZH_TW, EN_US, JA, KO,
	ES, PT_BR, FR, DE, IT, RU, PL,
	TR, AR, TH, VI, ID,
}

## 枚举 → BCP-47 标签，须与 CSV 列名一致。
const _LOCALE_TAGS: Dictionary = {
	Language.ZH_CN: "zh-CN",	## 简体中文
	Language.ZH_TW: "zh-TW",	## 繁体中文
	Language.EN_US: "en-US",	## 英语
	Language.JA: "ja-JP",		## 日语
	Language.KO: "ko-KR",		## 韩语
	Language.ES: "es-ES",		## 西班牙语
	Language.PT_BR: "pt-BR",	## 葡萄牙语（巴西）
	Language.FR: "fr-FR",		## 法语
	Language.DE: "de-DE",		## 德语
	Language.IT: "it-IT",		## 意大利语
	Language.RU: "ru-RU",		## 俄语
	Language.PL: "pl-PL",		## 波兰语
	Language.TR: "tr-TR",		## 土耳其语
	Language.AR: "ar",			## 阿拉伯语
	Language.TH: "th-TH",		## 泰语
	Language.VI: "vi-VN",		## 越南语
	Language.ID: "id-ID",		## 印度尼西亚语
}
#endregion

#region Exports
## 已保存语言、系统语言都不在表头里时使用。启动默认也是这门。
@export var default_language: Language = Language.EN_US
## 唯一字典文件。首列 key，其后按语言填文案；`_tscn` 这类下划线列不进翻译。
@export_file("*.csv") var csv_path: String = ""
#endregion

#region Public API
static func locale_tag(language: Language) -> String:
	return String(_LOCALE_TAGS.get(language, ""))


## 无法识别时返回 [code]-1[/code]。
static func language_from_tag(tag: String) -> int:
	for language in _LOCALE_TAGS:
		if String(_LOCALE_TAGS[language]) == tag:
			return int(language)
	return -1
#endregion
