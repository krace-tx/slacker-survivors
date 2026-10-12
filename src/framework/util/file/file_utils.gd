class_name FileUtils
extends RefCounted

## 文件读写与持久化工具类。
##
## 提供基于 Godot 4.x [FileAccess] 的安全文本、JSON 与二进制文件读写，
## 以及文件存在性校验、删除、目录创建等功能。
## 严格遵循项目“可失败操作走 Result，没静默吞错”的规范。


#region Public API
## 将文本内容写入指定路径的文件。[br]
## 如果目标文件的父目录不存在，会自动递归创建该目录。[br]
## [param filepath] 文件的绝对路径或 [code]user://[/code] / [code]res://[/code] 路径。[br]
## [param content] 待写入的文本内容。[br]
## 返回 [Result]：成功时 [member Result.value] 为空；失败时返回详细错误。
static func write_text(filepath: String, content: String) -> Result:
	if filepath.is_empty():
		return Result.err("Write failed: path is empty.")

	# 自动确保父目录存在
	var dir_res := ensure_dir_exists(filepath.get_base_dir())
	if dir_res.is_err():
		return Result.err("Write failed: cannot create parent directory: %s." % dir_res.error)

	var file := FileAccess.open(filepath, FileAccess.WRITE)
	if file == null:
		var err := FileAccess.get_open_error()
		return Result.err("Write failed: cannot open '%s' (err=%d)." % [filepath, err])

	file.store_string(content)
	file.flush()
	return Result.ok()


## 从指定路径的文件中读取文本内容。[br]
## [param filepath] 文件的绝对路径或 [code]user://[/code] / [code]res://[/code] 路径。[br]
## 返回 [Result]：成功时 [member Result.value] 为读取到的文本字符串；失败时返回详细错误。
static func read_text(filepath: String) -> Result:
	if filepath.is_empty():
		return Result.err("Read failed: path is empty.")

	if not FileAccess.file_exists(filepath):
		return Result.err("Read failed: file not found: %s." % filepath)

	var file := FileAccess.open(filepath, FileAccess.READ)
	if file == null:
		var err := FileAccess.get_open_error()
		return Result.err("Read failed: cannot open '%s' (err=%d)." % [filepath, err])

	var content := file.get_as_text()
	return Result.ok(content)


## 将二进制写入指定路径。[br]
## 父目录不存在时会自动递归创建。[br]
## [param filepath] 文件的绝对路径或 [code]user://[/code] / [code]res://[/code] 路径。[br]
## [param bytes] 待写入的原始字节。[br]
## 返回 [Result]：成功时 [member Result.value] 为空；失败时返回详细错误。
static func write_bytes(filepath: String, bytes: PackedByteArray) -> Result:
	if filepath.is_empty():
		return Result.err("Write failed: path is empty.")

	var dir_res := ensure_dir_exists(filepath.get_base_dir())
	if dir_res.is_err():
		return Result.err("Write failed: cannot create parent directory: %s." % dir_res.error)

	var file := FileAccess.open(filepath, FileAccess.WRITE)
	if file == null:
		var err := FileAccess.get_open_error()
		return Result.err("Write failed: cannot open '%s' (err=%d)." % [filepath, err])

	file.store_buffer(bytes)
	file.flush()
	return Result.ok()


## 从指定路径读取二进制。[br]
## [param filepath] 文件的绝对路径或 [code]user://[/code] / [code]res://[/code] 路径。[br]
## 返回 [Result]：成功时 [member Result.value] 为 [PackedByteArray]；失败时返回详细错误。
static func read_bytes(filepath: String) -> Result:
	if filepath.is_empty():
		return Result.err("Read failed: path is empty.")

	if not FileAccess.file_exists(filepath):
		return Result.err("Read failed: file not found: %s." % filepath)

	var file := FileAccess.open(filepath, FileAccess.READ)
	if file == null:
		var err := FileAccess.get_open_error()
		return Result.err("Read failed: cannot open '%s' (err=%d)." % [filepath, err])

	return Result.ok(file.get_buffer(file.get_length()))


## 将 Dictionary 或 Array 序列化为 JSON 并写入文件。[br]
## [param filepath] 文件的绝对路径或 [code]user://[/code] / [code]res://[/code] 路径。[br]
## [param data] 待序列化的数据，通常为 Dictionary 或 Array。[br]
## [param indent] 可选，是否使用缩进进行美化（默认 [code]false[/code] 紧凑格式）。[br]
## 返回 [Result]：成功时 [member Result.value] 为空；失败时返回详细错误。
static func write_json(filepath: String, data: Variant, indent: bool = false) -> Result:
	if not (data is Dictionary or data is Array):
		return Result.err("Write JSON failed: data must be Dictionary or Array.")

	var json_string := JSON.stringify(data, "\t" if indent else "")
	if json_string.is_empty():
		return Result.err("Write JSON failed: stringify returned empty.")

	return write_text(filepath, json_string)


## 从文件中读取文本并反序列化为 Dictionary 或 Array。[br]
## [param filepath] 文件的绝对路径或 [code]user://[/code] / [code]res://[/code] 路径。[br]
## 返回 [Result]：成功时 [member Result.value] 为反序列化后的 Dictionary 或 Array；失败时返回详细错误。
static func read_json(filepath: String) -> Result:
	var text_res := read_text(filepath)
	if text_res.is_err():
		return text_res

	var json := JSON.new()
	var err := json.parse(text_res.value)
	if err != OK:
		return Result.err("Read JSON failed: parse error (line %d: %s)." % [json.get_error_line(), json.get_error_message()])

	var data: Variant = json.data
	if not (data is Dictionary or data is Array):
		return Result.err("Read JSON failed: root is not Dictionary or Array.")

	return Result.ok(data)


## 确保指定的目录路径存在。如果不存在，会自动递归创建。[br]
## [param dirpath] 目录路径，例如 [code]user://saves[/code]。[br]
## 返回 [Result]：成功时 [member Result.value] 为空；失败时返回详细错误。
static func ensure_dir_exists(dirpath: String) -> Result:
	if dirpath.is_empty():
		return Result.ok() # 空路径视为无需创建

	if not DirAccess.dir_exists_absolute(dirpath):
		var err := DirAccess.make_dir_recursive_absolute(dirpath)
		if err != OK:
			return Result.err("Create directory failed: '%s' (err=%d)." % [dirpath, err])
	
	return Result.ok()


## 安全地删除指定路径的文件。[br]
## 如果文件不存在，会直接返回成功，不会抛出错误。[br]
## [param filepath] 文件的绝对路径或 [code]user://[/code] / [code]res://[/code] 路径。[br]
## 返回 [Result]：成功时 [member Result.value] 为空；失败时返回详细错误。
static func remove_file(filepath: String) -> Result:
	if filepath.is_empty():
		return Result.err("Delete failed: path is empty.")

	if not FileAccess.file_exists(filepath):
		return Result.ok() # 文件不存在直接视为删除成功

	var err := DirAccess.remove_absolute(filepath)
	if err != OK:
		return Result.err("Delete failed: cannot remove '%s' (err=%d)." % [filepath, err])

	return Result.ok()


## 复制文件。[br]
## [param src_path] 源文件路径。[br]
## [param dst_path] 目标文件路径，父目录不存在时自动创建。[br]
## 返回 [Result]：成功时为空；失败时返回详细错误。
static func copy_file(src_path: String, dst_path: String) -> Result:
	if src_path.is_empty() or dst_path.is_empty():
		return Result.err("Copy failed: path is empty.")
	if not FileAccess.file_exists(src_path):
		return Result.err("Copy failed: source file not found: %s" % src_path)
	var dir_res := ensure_dir_exists(dst_path.get_base_dir())
	if dir_res.is_err():
		return dir_res
	var err := DirAccess.copy_absolute(src_path, dst_path)
	if err != OK:
		return Result.err("Copy failed: from '%s' to '%s' (err=%d)." % [src_path, dst_path, err])
	return Result.ok()


## 重命名 / 移动文件。[br]
## [param src_path] 源文件路径。[br]
## [param dst_path] 目标文件路径，父目录不存在时自动创建。[br]
## 返回 [Result]：成功时为空；失败时返回详细错误。
static func rename_file(src_path: String, dst_path: String) -> Result:
	if src_path.is_empty() or dst_path.is_empty():
		return Result.err("Rename failed: path is empty.")
	if not FileAccess.file_exists(src_path):
		return Result.err("Rename failed: source file not found: %s" % src_path)
	var dir_res := ensure_dir_exists(dst_path.get_base_dir())
	if dir_res.is_err():
		return dir_res
	# 目标已存在时，部分平台（如 Windows）rename_absolute 会失败，先安全清理目标
	if FileAccess.file_exists(dst_path):
		DirAccess.remove_absolute(dst_path)
	var err := DirAccess.rename_absolute(src_path, dst_path)
	if err != OK:
		return Result.err("Rename failed: from '%s' to '%s' (err=%d)." % [src_path, dst_path, err])
	return Result.ok()


## 判断指定路径的文件是否存在。[br]
## [param filepath] 文件路径。[br]
## 返回 [code]true[/code] 表示存在，[code]false[/code] 表示不存在。
static func file_exists(filepath: String) -> bool:
	if filepath.is_empty():
		return false
	return FileAccess.file_exists(filepath)


## 列举目录下文件（不含子目录），按文件名排序。[br]
## [code]res://[/code] 路径使用 [method ResourceLoader.list_directory]，导出包内可正确枚举资源。
static func list_files(dir_path: String, exclude_import: bool = true) -> Array[String]:
	if dir_path.begins_with("res://"):
		return _list_res_files(dir_path, exclude_import)

	var file_names: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("FileUtils: Failed to open directory: %s" % dir_path)
		return file_names

	file_names.assign(dir.get_files())
	file_names.sort()
	if not exclude_import:
		return file_names

	var filtered: Array[String] = []
	for file_name in file_names:
		if not file_name.ends_with(".import"):
			filtered.append(file_name)
	return filtered


## 列举目录下文件的完整路径。
static func list_file_paths(dir_path: String, exclude_import: bool = true) -> Array[String]:
	var paths: Array[String] = []
	for file_name in list_files(dir_path, exclude_import):
		paths.append(dir_path + file_name)
	return paths


## 列举目录下子文件夹，按名称排序。[br]
## [code]res://[/code] 路径使用 [method ResourceLoader.list_directory]，导出包内可正确枚举资源。
static func list_subdirs(dir_path: String) -> Array[String]:
	if dir_path.begins_with("res://"):
		return _list_res_subdirs(dir_path)

	var subdirs: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("FileUtils: Failed to open directory: %s" % dir_path)
		return subdirs

	subdirs.assign(dir.get_directories())
	subdirs.sort()
	return subdirs
#endregion


#region Private Helpers

static func _normalize_res_dir(dir_path: String) -> String:
	return dir_path if dir_path.ends_with("/") else dir_path + "/"


static func _list_res_files(dir_path: String, exclude_import: bool) -> Array[String]:
	var file_names: Array[String] = []
	for entry: String in ResourceLoader.list_directory(_normalize_res_dir(dir_path)):
		if entry.ends_with("/"):
			continue
		if exclude_import and (entry.ends_with(".import") or entry.ends_with(".remap")):
			continue
		file_names.append(entry)
	file_names.sort()
	return file_names


static func _list_res_subdirs(dir_path: String) -> Array[String]:
	var subdirs: Array[String] = []
	for entry: String in ResourceLoader.list_directory(_normalize_res_dir(dir_path)):
		if not entry.ends_with("/"):
			continue
		subdirs.append(entry.trim_suffix("/"))
	subdirs.sort()
	return subdirs

#endregion
