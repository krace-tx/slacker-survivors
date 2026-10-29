@tool
class_name ReverseDependencyScanner
extends RefCounted

## 跨层反向依赖断路扫描器（位于 [code]addons/build_isolation/core/[/code]）。[br]
##
## [b]核心定位：[/b][br]
## 在导出前置阶段静态核查所有【保留区文件】是否误引用了已被 [code].exportignore[/code] 标记剥离的文件，防止导出包运行期出现断链或脚本编译崩溃：[br]
## 1. [code]res://...[/code] 物理路径引用与 [code]preload("res://...")[/code] 编译期硬加载；[br]
## 2. [code]uid://...[/code] 资源唯一标识符（防止 [code].tscn[/code] / [code].tres[/code] 通过 UID 隐式挂载测试或编辑器资源而漏检）；[br]
## 3. 全局 [code]class_name[/code] 类标识符（防止正式脚本静态类型注解引用已剔除的测试类或编辑器类）。

#region Constants
## 需要扫描文本引用关系的运行时代码与序列化资源后缀白名单
const _INSPECT_EXTS: Array[String] = [".gd", ".tscn", ".tres"]

## 允许在 `.gd` 代码中保留受 `ResourceLoader.exists()` 保护的软字符串路由常量的条件剥离类别
## （例如 `[prod]` 段落剥离 `env_local.tres` 后，`GameEnvService` 中未调用 `preload` 的路径常量属于合法懒路由）
const _CONDITIONAL_SOFT_OK_CATEGORIES: Array[String] = [
	"conditional",
]
#endregion


#region Public Scan API
## 扫描 [param kept_files]（保留区）对 [param stripped_files]（剥离区）的所有违规引用。[br]
## - 对全局无条件剥离项（如 [code]src/test/[/code]、研发插件）：任何路径（含软字符串）、UID、[code]class_name[/code] 均视为违规；[br]
## - 对 [code][tag][/code] 条件段落剥离项（如多环境 [code]env_*.tres[/code]、Demo 锁章节）：拦截 [code].tscn[/code]/[code].tres[/code] 外部依赖、[code]preload(...)[/code] 编译期硬引用、UID 与 [code]class_name[/code]，放行动态路由软字符串常量。[br]
## 返回违规字典数组，每项包含 [code]source_file[/code]、[code]line[/code]、[code]kind[/code]、[code]symbol[/code]、[code]target_file[/code]。
static func scan_leaks(
	kept_files: PackedStringArray,
	stripped_files: PackedStringArray,
	stripped_categories: Dictionary = {}
) -> Array[Dictionary]:
	var leaks: Array[Dictionary] = []
	if kept_files.is_empty() or stripped_files.is_empty():
		return leaks

	# 1. 构建被剥离文件的「路径集合」、「UID -> 路径索引」与「全局 class_name -> 路径索引」三张查找表
	var stripped_path_set: Dictionary = {}
	var stripped_uid_map: Dictionary = {}
	var stripped_class_map: Dictionary = {}

	for spath: String in stripped_files:
		stripped_path_set[spath] = true
		var uid_str: String = _extract_associated_uid(spath)
		if not uid_str.is_empty():
			stripped_uid_map[uid_str] = spath
		if spath.ends_with(".gd"):
			var cname: String = _extract_gd_class_name(spath)
			if not cname.is_empty():
				stripped_class_map[cname] = spath

	# 2. 预编译路径、preload()、UID 与单词边界 class_name 匹配正则
	var re_res := RegEx.new()
	re_res.compile("res://[A-Za-z0-9_./-]+")
	var re_preload := RegEx.new()
	re_preload.compile("preload\\s*\\(\\s*[\"'](res://[A-Za-z0-9_./-]+)[\"']\\s*\\)")
	var re_uid := RegEx.new()
	re_uid.compile("uid://[a-z0-9]+")

	var class_regex: RegEx = null
	if not stripped_class_map.is_empty():
		var escaped_names: PackedStringArray = PackedStringArray()
		for cname: String in stripped_class_map.keys():
			escaped_names.append(cname)
		class_regex = RegEx.new()
		class_regex.compile("\\b(" + "|".join(escaped_names) + ")\\b")

	# 3. 逐个扫描保留区脚本与场景/资源文本，精确定位违规行号
	for kpath: String in kept_files:
		if not _is_inspectable_text_file(kpath) or not FileAccess.file_exists(kpath):
			continue
		var raw_text: String = FileAccess.get_file_as_string(kpath)
		if raw_text.is_empty():
			continue

		var is_gd: bool = kpath.ends_with(".gd")
		var lines: PackedStringArray = raw_text.split("\n")
		for idx: int in range(lines.size()):
			# 对 GDScript 剥离行尾 `#` 注释，避免文档注释中提及的路径或类名产生误报
			var line_text: String = _strip_gd_line_comment(lines[idx]) if is_gd else lines[idx]
			if line_text.strip_edges().is_empty():
				continue

			var preload_hits: Dictionary = {}
			if is_gd:
				for m_pre: RegExMatch in re_preload.search_all(line_text):
					preload_hits[m_pre.get_string(1)] = true

			# 3.1 检查 res:// 路径引用
			for m: RegExMatch in re_res.search_all(line_text):
				var hit_path: String = m.get_string(0)
				if stripped_path_set.has(hit_path):
					var cat: String = str(stripped_categories.get(hit_path, ""))
					var is_soft_conditional: bool = (
						is_gd
						and not preload_hits.has(hit_path)
						and _CONDITIONAL_SOFT_OK_CATEGORIES.has(cat)
					)
					if is_soft_conditional:
						continue
					leaks.append({
						"source_file": kpath,
						"line": idx + 1,
						"kind": "preload" if preload_hits.has(hit_path) else "path",
						"symbol": hit_path,
						"target_file": hit_path,
					})

			# 3.2 检查 uid:// 隐式引用（.tscn / .tres 的 ext_resource 挂载）
			for m_uid: RegExMatch in re_uid.search_all(line_text):
				var hit_uid: String = m_uid.get_string(0)
				if stripped_uid_map.has(hit_uid):
					var target_p: String = str(stripped_uid_map[hit_uid])
					leaks.append({
						"source_file": kpath,
						"line": idx + 1,
						"kind": "uid",
						"symbol": hit_uid,
						"target_file": target_p,
					})

			# 3.3 检查 GDScript 代码体（剔除字符串字面量后）是否静态引用了已剥离的全局 class_name
			if is_gd and class_regex != null:
				var cleaned_code: String = _strip_string_literals(line_text)
				for m_cls: RegExMatch in class_regex.search_all(cleaned_code):
					var hit_cls: String = m_cls.get_string(1)
					if stripped_class_map.has(hit_cls):
						leaks.append({
							"source_file": kpath,
							"line": idx + 1,
							"kind": "class_name",
							"symbol": hit_cls,
							"target_file": str(stripped_class_map[hit_cls]),
						})

	return leaks
#endregion


#region Internal Lexing & Metadata Helpers
## 判断文件扩展名是否属于需要做反向引用检查的文本资产类型。
static func _is_inspectable_text_file(path: String) -> bool:
	for ext: String in _INSPECT_EXTS:
		if path.ends_with(ext):
			return true
	return false


## 提取被剥离资产关联的 `uid://` 唯一标识（依次检查 `.uid` 伴生文件、`.import` 头部与 `.tscn`/`.tres` 首行声明）。
static func _extract_associated_uid(res_path: String) -> String:
	var uid_sidecar: String = res_path + ".uid"
	if FileAccess.file_exists(uid_sidecar):
		var sidecar_txt: String = FileAccess.get_file_as_string(uid_sidecar).strip_edges()
		if sidecar_txt.begins_with("uid://"):
			return sidecar_txt

	var import_sidecar: String = res_path + ".import"
	if FileAccess.file_exists(import_sidecar):
		var head: String = _read_first_lines(import_sidecar, 12)
		var uid_val: String = _match_first_uid(head)
		if not uid_val.is_empty():
			return uid_val

	if res_path.ends_with(".tscn") or res_path.ends_with(".tres"):
		var scene_head: String = _read_first_lines(res_path, 3)
		return _match_first_uid(scene_head)

	return ""


## 从 `.gd` 脚本文件前 30 行提取顶层 `class_name` 声明（无声明则返回空字符串）。
static func _extract_gd_class_name(gd_path: String) -> String:
	var head: String = _read_first_lines(gd_path, 30)
	var re := RegEx.new()
	re.compile("(?m)^\\s*class_name\\s+([A-Za-z_][A-Za-z0-9_]*)")
	var m: RegExMatch = re.search(head)
	if m != null:
		return m.get_string(1)
	return ""


## 只读读取文件前 [param max_lines] 行，避免为提取头部元数据而加载整个大文件。
static func _read_first_lines(path: String, max_lines: int) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var out: PackedStringArray = PackedStringArray()
	var count: int = 0
	while not f.eof_reached() and count < max_lines:
		out.append(f.get_line())
		count += 1
	f.close()
	return "\n".join(out)


## 从文本片段中提取首个 `uid://...` 字符串。
static func _match_first_uid(text: String) -> String:
	var re := RegEx.new()
	re.compile("uid://[a-z0-9]+")
	var m: RegExMatch = re.search(text)
	return m.get_string(0) if m != null else ""


## 剥离单行 GDScript 中位于单/双引号字符串字面量之外的 `#` 行尾注释（保留字符串内的 `#` 如颜色码 `"#ff0000"`）。
static func _strip_gd_line_comment(line: String) -> String:
	var in_single: bool = false
	var in_double: bool = false
	var escaped: bool = false
	for i: int in range(line.length()):
		var ch: String = line[i]
		if escaped:
			escaped = false
			continue
		if ch == "\\":
			escaped = true
			continue
		if ch == "'" and not in_double:
			in_single = not in_single
		elif ch == "\"" and not in_single:
			in_double = not in_double
		elif ch == "#" and not in_single and not in_double:
			return line.substr(0, i)
	return line


## 将单行代码中的单/双引号字符串内容替换为空格，仅保留纯代码标识符供 `class_name` 精确扫描（避免日志文本误报）。
static func _strip_string_literals(line: String) -> String:
	var out: String = ""
	var in_single: bool = false
	var in_double: bool = false
	var escaped: bool = false
	for i: int in range(line.length()):
		var ch: String = line[i]
		if escaped:
			escaped = false
			continue
		if ch == "\\":
			escaped = true
			continue
		if ch == "'" and not in_double:
			in_single = not in_single
			out += " "
		elif ch == "\"" and not in_single:
			in_double = not in_double
			out += " "
		elif not in_single and not in_double:
			out += ch
		else:
			out += " "
	return out
#endregion
