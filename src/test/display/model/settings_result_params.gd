class_name SettingsResultParams
extends BaseParams

## 设置页返回大厅页的结果载荷参数包（位于 src/test/display/model/）。


#region 成员属性

## 最近一次设置变更或当前配置摘要文本
var summary_text: String = ""

#endregion


#region 生命周期

func _init(p_summary: String = "") -> void:
	summary_text = p_summary

#endregion
