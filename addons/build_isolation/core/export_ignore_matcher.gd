@tool
class_name ExportIgnoreMatcher
extends RefCounted

## [code].exportignore[/code] 规则解析、通配符编译与路径匹配引擎（位于 [code]addons/build_isolation/core/[/code]）。[br]
##
## [b]核心设计原则：[/b][br]
## 1. [b]零EditorUI耦合[/b]：纯 `RefCounted` 内存匹配器，既可在 [BuildIsolationExporter] 导出管线中毫秒级判定，也可在 Headless CLI 脚本中直接单测；[br]
## 2. [b]对齐 `.gitignore` 直觉[/b]：自上而下顺序求值，[b]最后一条命中的规则决定去留[/b]（支持 [code]!pattern[/code] 白名单反选覆盖前序忽略目录）；[br]
## 3. [b]轻量条件段落扩展[/b]：支持 [code][prod][/code]、[code][android, ios][/code]（OR）、[code][prod & !demo][/code]（AND + 取反）按导出预设 Feature Tag 动态启用段落；[br]
## 4. [b]强制净室自剥离[/b]：[code]res://.exportignore[/code] 与 [code]res://addons/build_isolation/[/code] 始终内置硬编码剥离，无需依赖外部配置兜底。

#region Constants & Private Fields
## 默认读取的根目录忽略规则文件路径
const DEFAULT_IGNORE_FILE: String = "res://.exportignore"

## 插件自身相对路径前缀（强制物理自剥离，确保运行期 PCK 零字节残留）
const SELF_ADDON_REL_PREFIX: String = "addons/build_isolation/"

## 全工程模拟遍历时跳过的引擎缓存、版本控制与 IDE 隐藏目录
const _IGNORED_SCAN_DIRS: Array[String] = [".godot", ".git", ".agents", ".vscode", ".idea"]

## 已按当前激活段落过滤并预编译完成的规则序列；元素结构：`{"raw": String, "negated": bool, "conditional": bool, "regex": RegEx}`
var _rules: Array[Dictionary] = []

## 当前导出预设激活的小写 Feature Tag 哈希集合（用于 `O(1)` 判定条件段落是否生效）
var _feature_set: Dictionary = {}
#endregion


#region Factory & Public API
## 从磁盘 [param ignore_file_path]（默认 [code]res://.exportignore[/code]）读取规则，并结合导出预设 [param features] 构建匹配器。
static func from_file(
	features: PackedStringArray = PackedStringArray(),
	ignore_file_path: String = DEFAULT_IGNORE_FILE
) -> ExportIgnoreMatcher:
	var text: String = ""
	if FileAccess.file_exists(ignore_file_path):
		text = FileAccess.get_file_as_string(ignore_file_path)
	return from_text(text, features)


## 从原始规则文本 [param content] 解析并结合导出预设 [param features] 构建匹配器（便于单元测试直接注入规则文本）。
static func from_text(
	content: String,
	features: PackedStringArray = PackedStringArray()
) -> ExportIgnoreMatcher:
	var matcher := ExportIgnoreMatcher.new()
	matcher._feature_set = _make_feature_set(features)
	matcher._parse(content)
	return matcher


## 评估单个路径 [param path] 的最终去留决策。[br]
## 返回字典结构：[code]{"ignore": bool, "rule": String, "category": String}[/code]，其中 [code]category[/code] 区分无条件规则（[code]"unconditional"[/code]）与条件段落规则（[code]"conditional"[/code]）。
func evaluate(path: String) -> Dictionary:
	var rel: String = normalize_rel_path(path)
	if rel.is_empty():
		return {"ignore": false, "rule": "", "category": ""}

	# 最高优先级铁律：插件自身与 .exportignore 配置文件始终自剥离，不可被任何 ! 规则误放行
	if rel == ".exportignore" or rel.begins_with(SELF_ADDON_REL_PREFIX):
		return {"ignore": true, "rule": "<self>", "category": "self_plugin"}

	var ignored: bool = false
	var hit_rule: String = ""
	var hit_cat: String = ""

	# 按 .gitignore 语义顺序遍历全部生效规则，后命中的规则覆盖前序状态（Last-Match-Wins）
	for rule: Dictionary in _rules:
		var regex: RegEx = rule["regex"] as RegEx
		if regex != null and regex.search(rel) != null:
			var is_negated: bool = bool(rule["negated"])
			ignored = not is_negated
			hit_rule = str(rule["raw"])
			hit_cat = "conditional" if bool(rule["conditional"]) else "unconditional"

	return {
		"ignore": ignored,
		"rule": hit_rule if ignored else "",
		"category": hit_cat if ignored else "",
	}


## 快捷布尔查询：判断指定 [param path] 在当前导出特性下是否应被剥离。
func should_ignore(path: String) -> bool:
	return bool(evaluate(path).get("ignore", false))


## 无副作用遍历全工程文件，生成保留/剥离清单及 [ReverseDependencyScanner] 跨层反向引用检查报告。
func simulate_project() -> Dictionary:
	var all_files: PackedStringArray = PackedStringArray()
	_collect_project_files("res://", all_files)

	var kept_files: PackedStringArray = PackedStringArray()
	var stripped_files: PackedStringArray = PackedStringArray()
	var stripped_categories: Dictionary = {}
	var stripped_rules: Dictionary = {}

	for res_path: String in all_files:
		var dec: Dictionary = evaluate(res_path)
		if bool(dec.get("ignore", false)):
			stripped_files.append(res_path)
			stripped_categories[res_path] = str(dec.get("category", "unconditional"))
			stripped_rules[res_path] = str(dec.get("rule", ""))
		else:
			kept_files.append(res_path)

	var leaks: Array[Dictionary] = ReverseDependencyScanner.scan_leaks(
		kept_files,
		stripped_files,
		stripped_categories
	)

	return {
		"total_count": all_files.size(),
		"kept_files": kept_files,
		"stripped_files": stripped_files,
		"stripped_rules": stripped_rules,
		"reverse_leaks": leaks,
	}


## 将 `res://foo/bar.gd` 或 `/foo/bar.gd` 统一归一化为不带前导斜杠的相对 POSIX 路径 `foo/bar.gd`。
static func normalize_rel_path(path: String) -> String:
	var p: String = path.strip_edges().replace("\\", "/")
	if p.begins_with("res://"):
		p = p.substr(6)
	return p.trim_prefix("/")
#endregion


#region Parser & Glob-to-RegEx Compiler
## 逐行解析 `.exportignore` 文本，跳过未命中当前 `_feature_set` 的条件段落并将有效通配符预编译为 `RegEx`。
func _parse(content: String) -> void:
	_rules.clear()
	var current_section: String = ""
	var section_active: bool = true

	for raw_line: String in content.split("\n"):
		var trimmed: String = raw_line.strip_edges()
		if trimmed.is_empty() or trimmed.begins_with("#"):
			continue

		# 识别形如 `[prod]`、`[android, ios]`、`[!steam]` 的条件段落头
		if _is_section_header(trimmed):
			current_section = trimmed.substr(1, trimmed.length() - 2).strip_edges().to_lower()
			if current_section == "all" or current_section == "*" or current_section == "global":
				current_section = ""
			section_active = _is_section_active(current_section, _feature_set)
			continue

		# 当前条件段落未命中导出预设标签时，直接跳过该段落下的所有规则编译
		if not section_active:
			continue

		# 处理 `!` 取反白名单前缀，以及 `\#` / `\!` 字面量首字符转义
		var negated: bool = false
		var pat: String = trimmed
		if pat.begins_with("!"):
			negated = true
			pat = pat.substr(1).strip_edges()
		elif pat.begins_with("\\#") or pat.begins_with("\\!"):
			pat = pat.substr(1)

		var compiled: RegEx = _compile_gitignore_regex(pat)
		if compiled != null:
			_rules.append({
				"raw": trimmed if current_section.is_empty() else "[%s] %s" % [current_section, trimmed],
				"negated": negated,
				"conditional": not current_section.is_empty(),
				"regex": compiled,
			})


## 判断单行文本是否为 `[section]` 条件段落头（排除含 `/` 或 `.` 的普通文件名字符集模式，如 `[Dd]esktop.ini`）。
static func _is_section_header(trimmed: String) -> bool:
	return (
		trimmed.begins_with("[")
		and trimmed.ends_with("]")
		and not trimmed.contains("/")
		and not trimmed.contains(".")
	)


## 求值条件段落布尔表达式：[br]
## - 逗号 `,` 分隔表示 **OR**（任一子组满足即激活，如 `[android, ios, web]`）；[br]
## - `&` 或 `+` 分隔表示 **AND**（组内所有条件必须同时满足，如 `[prod & !demo]`）；[br]
## - 前缀 `!` 表示当前导出预设 **不包含** 指定标签（如 `[!steam]`）。
static func _is_section_active(section_expr: String, feature_set: Dictionary) -> bool:
	if section_expr.is_empty():
		return true

	for or_part: String in section_expr.split(","):
		var group_expr: String = or_part.strip_edges()
		if group_expr.is_empty():
			continue

		var all_matched: bool = true
		var normalized_and: String = group_expr.replace("+", "&")
		for and_part: String in normalized_and.split("&"):
			var token: String = and_part.strip_edges()
			if token.is_empty():
				continue
			if token.begins_with("!"):
				var forbidden_tag: String = token.substr(1).strip_edges()
				if not forbidden_tag.is_empty() and feature_set.has(forbidden_tag):
					all_matched = false
					break
			elif not feature_set.has(token):
				all_matched = false
				break

		if all_matched:
			return true

	return false


## 将单条 `.gitignore` 风格通配模式编译为等价的锚定 `RegEx`：[br]
## - 若模式以 `/`（或 `res://`）开头、或去掉末尾 `/` 后内部仍含 `/`，则锚定至工程根目录 `^`；[br]
## - 若模式不含 `/`（如 `*.md`、`editor/`），则在任意目录层级 `(?:^|/)` 均可匹配；[br]
## - 若模式以 `/` 结尾（`dir_only`），则匹配该目录内任意深度的全部文件 `/.+$`。
static func _compile_gitignore_regex(raw_pattern: String) -> RegEx:
	var pat: String = raw_pattern.strip_edges().replace("\\", "/")
	var anchored: bool = false

	if pat.begins_with("res://"):
		anchored = true
		pat = pat.substr(6)
	if pat.begins_with("/"):
		anchored = true
		pat = pat.trim_prefix("/")

	var dir_only: bool = pat.ends_with("/")
	while pat.ends_with("/"):
		pat = pat.left(pat.length() - 1)
	if pat.is_empty():
		return null

	var has_leading_globstar: bool = false
	if pat == "**":
		var all_re := RegEx.new()
		all_re.compile("^.+$")
		return all_re
	if pat.begins_with("**/"):
		has_leading_globstar = true
		pat = pat.substr(3)
	elif not anchored and pat.contains("/"):
		anchored = true

	var prefix: String = "^(?:.+/)?" if has_leading_globstar else ("^" if anchored else "(?:^|/)")
	var body: String = ""
	var i: int = 0
	var n: int = pat.length()

	# 逐字符扫描转换通配元字符，并对正则特殊符号做字面量转义
	while i < n:
		if i + 4 <= n and pat.substr(i, 4) == "/**/":
			# 中间跨层 `/**/`：匹配零层（`/`）或多层子目录（`/a/b/`）
			body += "(?:/.+/|/)"
			i += 4
		elif i + 3 == n and pat.substr(i, 3) == "/**":
			# 末尾 `/**`：匹配该目录下的全部子级内容
			body += "/.+"
			i += 3
		elif i + 2 <= n and pat.substr(i, 2) == "**":
			body += ".*"
			i += 2
		elif pat[i] == "*":
			# 单星号 `*` 仅在单级目录名/文件名内通配，不跨越 `/`
			body += "[^/]*"
			i += 1
		elif pat[i] == "?":
			body += "[^/]"
			i += 1
		elif ".+^$(){}|[]\\".contains(pat[i]):
			body += "\\" + pat[i]
			i += 1
		else:
			body += pat[i]
			i += 1

	var suffix: String = "/.+$" if dir_only else "(?:/.*)?$"
	var regex := RegEx.new()
	if regex.compile(prefix + body + suffix) != OK:
		return null
	return regex


## 将导出预设传入的特性数组转为小写哈希字典，屏蔽大小写与首尾空格差异。
static func _make_feature_set(features: PackedStringArray) -> Dictionary:
	var d: Dictionary = {}
	for f: String in features:
		var clean: String = f.strip_edges().to_lower()
		if not clean.is_empty():
			d[clean] = true
	return d


## 递归收集全工程参与导出的源文件路径（自动跳过 `.godot`、已含 `.gdignore` 的目录以及 `.import` / `.uid` 伴生元数据）。
static func _collect_project_files(dir_path: String, out_files: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		if entry != "." and entry != ".." and not _IGNORED_SCAN_DIRS.has(entry):
			var full_path: String = (
				"res://" + entry if dir_path == "res://" else dir_path.path_join(entry)
			)
			if dir.current_is_dir():
				if not FileAccess.file_exists(full_path.path_join(".gdignore")):
					_collect_project_files(full_path, out_files)
			elif not entry.ends_with(".import") and not entry.ends_with(".uid"):
				out_files.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()
#endregion
