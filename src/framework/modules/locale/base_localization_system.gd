@abstract
class_name BaseLocalizationSystem
extends RefCounted

## 多语言本地化系统门面契约（Localization System Facade Contract）。[br]
##
## 本抽象基类作为业务层管理游戏语言环境与文本翻译的唯一规范入口，核心职责：[br]
## - 接入 Godot 官方 [TranslationServer]，无缝支持 [code]tr("KEY")[/code] 国际化宏；[br]
## - 语言安全切换：支持枚举与国际标准 Locale 字符串映射，缺失配置时提供安全保底；[br]
## - 持久化集成：与存储子系统无缝联动保存用户语言选择偏好。[br]
##
## 业务代码应统一通过 [code]App.locale[/code] 访问本契约提供的方法。


## 当前生效的应用语言枚举常量（定义参见 [LocaleConfig.Language]）。
var current_language: LocaleConfig.Language = LocaleConfig.Language.EN_US

## 本工程支持并可供玩家选择的全部可用语言列表。
var languages: Array[LocaleConfig.Language] = []


#region Public Locale APIs
## 切换当前游戏运行时的语言。[br]
##
## 切换后会自动向 Godot 引擎 [TranslationServer] 同步激活对应语言包，[br]
## 并通过全局总线广播 [signal Bus.locale_changed] 事件以驱动 UI 文本即时刷新。[br]
##
## [param language] 目标语言枚举常量（[LocaleConfig.Language]）。[br]
## @return 返回 [Result] 对象（若指定语言不在支持列表中则返回失败）。
@abstract
func set_language(language: LocaleConfig.Language) -> Result
#endregion
