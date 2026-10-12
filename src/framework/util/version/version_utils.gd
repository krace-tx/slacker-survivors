class_name VersionUtils
extends RefCounted

## 点分数字版本比较工具（如 [code]1.2.3[/code]）。
## 缺段默认视为 0（故 [code]1.0[/code] 与 [code]1.0.0[/code] 等价）。
## 纯无状态，不依赖场景树或单例。

#region Constants
const _DEFAULT_VERSION: String = "1.0.0"
const _PROJECT_VERSION_SETTING: String = "application/config/version"
#endregion


#region Public API
## 获取当前客户端软件版本号（读取 ProjectSettings，未配置时回退 [code]1.0.0[/code]）。
static func current() -> String:
	var version := ProjectSettings.get_setting(_PROJECT_VERSION_SETTING, _DEFAULT_VERSION) as String
	return version if not version.is_empty() else _DEFAULT_VERSION


## 三路比较：left 小于 / 等于 / 大于 right 分别返回 -1 / 0 / 1。
static func compare(left: String, right: String) -> int:
	var left_parts := left.split(".")
	var right_parts := right.split(".")
	var count := maxi(left_parts.size(), right_parts.size())
	for i in count:
		var left_num := _segment_at(left_parts, i)
		var right_num := _segment_at(right_parts, i)
		if left_num < right_num:
			return -1
		if left_num > right_num:
			return 1
	return 0


## [param left] 版本是否小于 [param right]（即 left < right）。[br]
## 若 [param right] 为空则视为无版本约束，返回 false。
static func is_lower(left: String, right: String) -> bool:
	if right.is_empty():
		return false
	return compare(left, right) < 0


## [param left] 版本是否大于 [param right]（即 left > right）。[br]
## 若 [param right] 为空则返回 true。
static func is_greater(left: String, right: String) -> bool:
	if right.is_empty():
		return true
	return compare(left, right) > 0


## [param left] 版本是否大于等于 [param right]（即 left >= right）。[br]
## 若 [param right] 为空则返回 true。
static func is_greater_or_equal(left: String, right: String) -> bool:
	if right.is_empty():
		return true
	return compare(left, right) >= 0


## [param left] 版本是否与 [param right] 完全相等（即 left == right）。
static func is_equal(left: String, right: String) -> bool:
	return compare(left, right) == 0
#endregion


#region Internal
static func _segment_at(parts: PackedStringArray, index: int) -> int:
	return int(parts[index]) if index < parts.size() else 0
#endregion
