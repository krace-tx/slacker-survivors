class_name FileUtils
extends RefCounted

## 工业级安全文件 I/O、事务落盘与虚拟文件系统（VFS）工具类。[br]
##
## [b]核心设计（第一性原理）：[/b][br]
## 1. [b]事务级原子写入管线（Transactional Atomic Write）[/b]：支持 [code].tmp[/code] 独立缓冲落盘、写入期底层 I/O 状态强校验、
##    显式句柄锁释放与带回滚保护的原子替换（Safe Replace），彻底杜绝断电/强杀引发的 0 字节坏档（Torn Write）与同路径自删漏洞；[br]
## 2. [b]VFS 双轨透明路由与写保护沙箱[/b]：自动识别编译包内只读卷（[code]res://[/code]）与沙盒可读写卷（[code]user://[/code]），
##    运行期写保护前置拦截，并提供 [method materialize_res_file] 将 PCK/APK 封包内资源按需流式提取为 OS 原生路径供外部插件消费；[br]
## 3. [b]固定分块流式 I/O（Chunked Stream Copy）[/b]：跨虚拟卷复制大文件时采用 64KB 恒定内存块流式传输，消除一次性全量缓冲引发的内存峰值；[br]
## 4. [b]全链路结构化错误契约[/b]：所有可失败 I/O 均返回携带 [code]File.{Reason}[/code] 标准错误码、可重试推导与诊断上下文的 [Result]。


#region Constants & Error Codes

const CHUNK_SIZE: int = 65536 ## 流式分块读写缓冲区大小（64 KB）。
const TMP_SUFFIX: String = ".tmp" ## 原子写入临时文件后缀。
const SWAP_SUFFIX: String = ".swap_bak" ## 覆盖重命名时的安全回滚备份后缀。

const ERR_EMPTY_PATH: String = "File.EmptyPath"
const ERR_INVALID_PATH: String = "File.InvalidPath"
const ERR_READ_ONLY: String = "File.ReadOnly"
const ERR_NOT_FOUND: String = "File.NotFound"
const ERR_OPEN_FAILED: String = "File.OpenFailed"
const ERR_IO_ERROR: String = "File.IOError"
const ERR_PARSE_ERROR: String = "File.ParseError"
const ERR_HASH_MISMATCH: String = "File.HashMismatch"
const ERR_DIR_FAILED: String = "File.DirectoryFailed"

#endregion


#region Core Operator 1: Text, Binary & JSON Read/Write

## 将文本内容写入指定路径的文件。[br]
## 如果目标文件的父目录不存在，会自动递归创建该目录。[br]
## [param filepath] 文件路径（[code]user://[/code]、OS 绝对路径，或编辑器模式下的 [code]res://[/code]）。[br]
## [param content] 待写入的 UTF-8 文本内容。[br]
## [param atomic] 是否启用 [code].tmp[/code] 事务级原子写入（默认 [code]false[/code]；关键配置或存档建议设为 [code]true[/code]）。[br]
## 返回 [Result]：成功时 [member Result.value] 为空；失败时返回携带 [FrameworkError] 的详细错误。
static func write_text(filepath: String, content: String, atomic: bool = false) -> Result:
	return write_bytes(filepath, content.to_utf8_buffer(), atomic)


## 从指定路径的文件中读取 UTF-8 文本内容。[br]
## [param filepath] 文件的绝对路径或 [code]user://[/code] / [code]res://[/code] 路径。[br]
## 返回 [Result]：成功时 [member Result.value] 为读取到的文本字符串；失败时返回详细错误。
static func read_text(filepath: String) -> Result:
	var guard := _validate_read_path(filepath)
	if guard.is_err():
		return guard

	var file := FileAccess.open(filepath, FileAccess.READ)
	if file == null:
		return _err_from_godot(ERR_OPEN_FAILED, "Read failed: cannot open '%s'." % filepath, FileAccess.get_open_error(), {"path": filepath})

	var content := file.get_as_text()
	var io_err := file.get_error()
	file.close()

	if io_err != OK and io_err != ERR_FILE_EOF:
		return _err_from_godot(ERR_IO_ERROR, "Read failed: I/O error while reading '%s'." % filepath, io_err, {"path": filepath})

	return Result.ok(content)


## 在文件末尾追加 UTF-8 文本（文件不存在时自动创建）。
static func append_text(filepath: String, content: String) -> Result:
	return append_bytes(filepath, content.to_utf8_buffer())


## 将二进制字节流写入指定路径。[br]
## 父目录不存在时会自动递归创建；严格校验底层写入状态并显式释放文件句柄。[br]
## [param filepath] 文件路径。[br]
## [param bytes] 待写入的原始字节。[br]
## [param atomic] 是否启用 [code].tmp[/code] 事务级原子落盘。[br]
## 返回 [Result]：成功时 [member Result.value] 为空；失败时返回详细错误。
static func write_bytes(filepath: String, bytes: PackedByteArray, atomic: bool = false) -> Result:
	var guard := _validate_write_path(filepath)
	if guard.is_err():
		return guard

	if not atomic:
		return _write_bytes_direct(filepath, bytes)

	var tmp_path := filepath + TMP_SUFFIX
	var write_res := _write_bytes_direct(tmp_path, bytes)
	if write_res.is_err():
		remove_file(tmp_path)
		return write_res

	var rename_res := rename_file(tmp_path, filepath)
	if rename_res.is_err():
		remove_file(tmp_path)
		return rename_res

	return Result.ok()


## 从指定路径读取二进制字节流。[br]
## [param filepath] 文件的绝对路径或 [code]user://[/code] / [code]res://[/code] 路径。[br]
## 返回 [Result]：成功时 [member Result.value] 为 [PackedByteArray]；失败时返回详细错误。
static func read_bytes(filepath: String) -> Result:
	var guard := _validate_read_path(filepath)
	if guard.is_err():
		return guard

	var file := FileAccess.open(filepath, FileAccess.READ)
	if file == null:
		return _err_from_godot(ERR_OPEN_FAILED, "Read failed: cannot open '%s'." % filepath, FileAccess.get_open_error(), {"path": filepath})

	var length := file.get_length()
	if length <= 0:
		file.close()
		return Result.ok(PackedByteArray())

	var buffer := file.get_buffer(length)
	var io_err := file.get_error()
	file.close()

	if (io_err != OK and io_err != ERR_FILE_EOF) or buffer.size() != length:
		return _err_from_godot(
			ERR_IO_ERROR,
			"Read failed: incomplete buffer read for '%s' (%d/%d bytes)." % [filepath, buffer.size(), length],
			io_err if io_err != OK else ERR_FILE_CORRUPT,
			{"path": filepath, "expected_bytes": length, "actual_bytes": buffer.size()}
		)

	return Result.ok(buffer)


## 在文件末尾追加二进制字节流（文件不存在时自动创建并写入）。
static func append_bytes(filepath: String, bytes: PackedByteArray) -> Result:
	var guard := _validate_write_path(filepath)
	if guard.is_err():
		return guard

	if not FileAccess.file_exists(filepath):
		return _write_bytes_direct(filepath, bytes)

	if bytes.is_empty():
		return Result.ok()

	var file := FileAccess.open(filepath, FileAccess.READ_WRITE)
	if file == null:
		return _err_from_godot(ERR_OPEN_FAILED, "Append failed: cannot open '%s'." % filepath, FileAccess.get_open_error(), {"path": filepath})

	file.seek_end()
	var stored := file.store_buffer(bytes)
	file.flush()
	var io_err := file.get_error()
	file.close()

	if not stored or io_err != OK:
		return _err_from_godot(ERR_IO_ERROR, "Append failed: disk write error on '%s'." % filepath, io_err, {"path": filepath})

	return Result.ok()


## 将 [Dictionary] 或 [Array] 序列化为 JSON 并写入文件。[br]
## [param filepath] 文件路径。[br]
## [param data] 待序列化的数据，必须为 [Dictionary] 或 [Array]。[br]
## [param indent] 可选，是否使用缩进进行美化（默认 [code]false[/code] 紧凑格式）。[br]
## [param atomic] 可选，是否启用 [code].tmp[/code] 事务级原子写入（默认 [code]false[/code]）。[br]
## 返回 [Result]：成功时 [member Result.value] 为空；失败时返回详细错误。
static func write_json(filepath: String, data: Variant, indent: bool = false, atomic: bool = false) -> Result:
	if not (data is Dictionary or data is Array):
		return Result.err_ex(
			ERR_PARSE_ERROR,
			"Write JSON failed: root data must be Dictionary or Array.",
			{"path": filepath, "actual_type": type_string(typeof(data))},
			false,
			null,
			FrameworkError.CATEGORY_PARAM
		)

	var json_string := JSON.stringify(data, "\t" if indent else "", false)
	if json_string.is_empty():
		return Result.err_ex(
			ERR_PARSE_ERROR,
			"Write JSON failed: JSON.stringify returned empty string.",
			{"path": filepath},
			false,
			null,
			FrameworkError.CATEGORY_VALIDATION
		)

	return write_text(filepath, json_string, atomic)


## 从文件中读取文本并反序列化为 [Dictionary] 或 [Array]。[br]
## [param filepath] 文件的绝对路径或 [code]user://[/code] / [code]res://[/code] 路径。[br]
## 返回 [Result]：成功时 [member Result.value] 为反序列化后的 [Dictionary] 或 [Array]；失败时返回详细错误。
static func read_json(filepath: String) -> Result:
	var text_res := read_text(filepath)
	if text_res.is_err():
		return text_res

	var raw_text: String = text_res.value
	if raw_text.strip_edges().is_empty():
		return Result.err_ex(
			ERR_PARSE_ERROR,
			"Read JSON failed: file '%s' is empty or whitespace only." % filepath,
			{"path": filepath},
			false,
			null,
			FrameworkError.CATEGORY_VALIDATION
		)

	var json := JSON.new()
	var err := json.parse(raw_text)
	if err != OK:
		return Result.err_ex(
			ERR_PARSE_ERROR,
			"Read JSON failed: parse error in '%s' (line %d: %s)." % [filepath, json.get_error_line(), json.get_error_message()],
			{"path": filepath, "line": json.get_error_line(), "reason": json.get_error_message()},
			false,
			err,
			FrameworkError.CATEGORY_VALIDATION
		)

	var data: Variant = json.data
	if not (data is Dictionary or data is Array):
		return Result.err_ex(
			ERR_PARSE_ERROR,
			"Read JSON failed: root is not Dictionary or Array in '%s'." % filepath,
			{"path": filepath, "root_type": type_string(typeof(data))},
			false,
			null,
			FrameworkError.CATEGORY_VALIDATION
		)

	return Result.ok(data)

#endregion


#region Core Operator 2: Compressed & Encrypted I/O

## 将二进制数据压缩后写入文件（默认使用 ZSTD 高速压缩算法）。
static func write_compressed(
	filepath: String,
	bytes: PackedByteArray,
	compression_mode: FileAccess.CompressionMode = FileAccess.COMPRESSION_ZSTD,
	atomic: bool = false
) -> Result:
	var guard := _validate_write_path(filepath)
	if guard.is_err():
		return guard

	var target_path := (filepath + TMP_SUFFIX) if atomic else filepath
	var dir_res := ensure_dir_exists(target_path.get_base_dir())
	if dir_res.is_err():
		return dir_res

	var file := FileAccess.open_compressed(target_path, FileAccess.WRITE, compression_mode)
	if file == null:
		return _err_from_godot(ERR_OPEN_FAILED, "Write compressed failed: cannot open '%s'." % target_path, FileAccess.get_open_error(), {"path": filepath})

	var stored := file.store_buffer(bytes)
	file.flush()
	var io_err := file.get_error()
	file.close()

	if not stored or io_err != OK:
		if atomic:
			remove_file(target_path)
		return _err_from_godot(ERR_IO_ERROR, "Write compressed failed: I/O error on '%s'." % target_path, io_err, {"path": filepath})

	if atomic:
		var rename_res := rename_file(target_path, filepath)
		if rename_res.is_err():
			remove_file(target_path)
			return rename_res

	return Result.ok()


## 从压缩文件中读取并解压还原二进制数据。
static func read_compressed(
	filepath: String,
	compression_mode: FileAccess.CompressionMode = FileAccess.COMPRESSION_ZSTD
) -> Result:
	var guard := _validate_read_path(filepath)
	if guard.is_err():
		return guard

	var file := FileAccess.open_compressed(filepath, FileAccess.READ, compression_mode)
	if file == null:
		return _err_from_godot(ERR_OPEN_FAILED, "Read compressed failed: cannot open '%s'." % filepath, FileAccess.get_open_error(), {"path": filepath})

	var length := file.get_length()
	var buffer := file.get_buffer(length) if length > 0 else PackedByteArray()
	var io_err := file.get_error()
	file.close()

	if io_err != OK and io_err != ERR_FILE_EOF:
		return _err_from_godot(ERR_IO_ERROR, "Read compressed failed: corrupted stream in '%s'." % filepath, io_err, {"path": filepath})

	return Result.ok(buffer)


## 使用口令（AES-256）将二进制数据加密写入文件。
static func write_encrypted(filepath: String, bytes: PackedByteArray, password: String, atomic: bool = false) -> Result:
	var guard := _validate_write_path(filepath)
	if guard.is_err():
		return guard
	if password.is_empty():
		return Result.err_ex(ERR_INVALID_PATH, "Write encrypted failed: password cannot be empty.", {"path": filepath}, false, null, FrameworkError.CATEGORY_PARAM)

	var target_path := (filepath + TMP_SUFFIX) if atomic else filepath
	var dir_res := ensure_dir_exists(target_path.get_base_dir())
	if dir_res.is_err():
		return dir_res

	var file := FileAccess.open_encrypted_with_pass(target_path, FileAccess.WRITE, password)
	if file == null:
		return _err_from_godot(ERR_OPEN_FAILED, "Write encrypted failed: cannot open '%s'." % target_path, FileAccess.get_open_error(), {"path": filepath})

	var stored := file.store_buffer(bytes)
	file.flush()
	var io_err := file.get_error()
	file.close()

	if not stored or io_err != OK:
		if atomic:
			remove_file(target_path)
		return _err_from_godot(ERR_IO_ERROR, "Write encrypted failed: I/O error on '%s'." % target_path, io_err, {"path": filepath})

	if atomic:
		var rename_res := rename_file(target_path, filepath)
		if rename_res.is_err():
			remove_file(target_path)
			return rename_res

	return Result.ok()


## 使用口令（AES-256）读取并解密还原二进制数据。
static func read_encrypted(filepath: String, password: String) -> Result:
	var guard := _validate_read_path(filepath)
	if guard.is_err():
		return guard
	if password.is_empty():
		return Result.err_ex(ERR_INVALID_PATH, "Read encrypted failed: password cannot be empty.", {"path": filepath}, false, null, FrameworkError.CATEGORY_PARAM)

	var file := FileAccess.open_encrypted_with_pass(filepath, FileAccess.READ, password)
	if file == null:
		return _err_from_godot(ERR_OPEN_FAILED, "Read encrypted failed: cannot open or wrong password for '%s'." % filepath, FileAccess.get_open_error(), {"path": filepath})

	var length := file.get_length()
	var buffer := file.get_buffer(length) if length > 0 else PackedByteArray()
	var io_err := file.get_error()
	file.close()

	if io_err != OK and io_err != ERR_FILE_EOF:
		return _err_from_godot(ERR_IO_ERROR, "Read encrypted failed: corrupted cipher stream in '%s'." % filepath, io_err, {"path": filepath})

	return Result.ok(buffer)

#endregion


#region Core Operator 3: File Lifecycle & Safe Replacement

## 安全地删除指定路径的文件（幂等操作：若文件不存在直接视为成功）。[br]
## [param filepath] 待删除的文件路径。[br]
## 返回 [Result]：成功时为空；失败时返回详细错误。
static func remove_file(filepath: String) -> Result:
	var guard := _validate_write_path(filepath)
	if guard.is_err():
		return guard

	if not FileAccess.file_exists(filepath):
		return Result.ok()

	var err := DirAccess.remove_absolute(filepath)
	if err != OK:
		return _err_from_godot(ERR_IO_ERROR, "Delete failed: cannot remove '%s' (err=%d)." % [filepath, err], err, {"path": filepath})

	return Result.ok()


## 复制文件（支持跨虚拟卷与大文件 64KB 流式分块复制回退）。[br]
## [param src_path] 源文件路径。[br]
## [param dst_path] 目标文件路径，父目录不存在时自动递归创建。[br]
## 返回 [Result]：成功时为空；失败时返回详细错误。
static func copy_file(src_path: String, dst_path: String) -> Result:
	var read_guard := _validate_read_path(src_path)
	if read_guard.is_err():
		return read_guard
	var write_guard := _validate_write_path(dst_path)
	if write_guard.is_err():
		return write_guard

	# 同路径自复制幂等短路
	if _is_same_path(src_path, dst_path):
		return Result.ok()

	var dir_res := ensure_dir_exists(dst_path.get_base_dir())
	if dir_res.is_err():
		return dir_res

	# 优先尝试操作系统级原生快速复制；若跨 PCK 虚拟卷失败则无缝降级为 64KB 分块流式复制
	if not src_path.begins_with("res://") or OS.has_feature("editor"):
		var err := DirAccess.copy_absolute(src_path, dst_path)
		if err == OK:
			return Result.ok()

	return _stream_copy_file(src_path, dst_path)


## 安全重命名 / 移动文件（内置同路径自毁拦截与 Windows 平台事务回滚替换保护）。[br]
## [param src_path] 源文件路径。[br]
## [param dst_path] 目标文件路径，父目录不存在时自动创建。[br]
## 返回 [Result]：成功时为空；失败时返回详细错误。
static func rename_file(src_path: String, dst_path: String) -> Result:
	var src_guard := _validate_write_path(src_path)
	if src_guard.is_err():
		return src_guard
	var dst_guard := _validate_write_path(dst_path)
	if dst_guard.is_err():
		return dst_guard

	if not FileAccess.file_exists(src_path):
		return Result.err_ex(ERR_NOT_FOUND, "Rename failed: source file not found: '%s'." % src_path, {"src": src_path, "dst": dst_path}, false, ERR_FILE_NOT_FOUND, FrameworkError.CATEGORY_NOT_FOUND)

	# 关键防御：拦截同路径自重命名，防止后续清理目标文件时将源文件自身误删
	if _is_same_path(src_path, dst_path):
		return Result.ok()

	var dir_res := ensure_dir_exists(dst_path.get_base_dir())
	if dir_res.is_err():
		return dir_res

	# 1. 目标不存在时直接重命名
	if not FileAccess.file_exists(dst_path):
		var direct_err := DirAccess.rename_absolute(src_path, dst_path)
		if direct_err != OK:
			return _err_from_godot(ERR_IO_ERROR, "Rename failed: from '%s' to '%s' (err=%d)." % [src_path, dst_path, direct_err], direct_err, {"src": src_path, "dst": dst_path})
		return Result.ok()

	# 2. 目标已存在：先尝试 POSIX 原生原子覆盖 rename
	var overwrite_err := DirAccess.rename_absolute(src_path, dst_path)
	if overwrite_err == OK:
		return Result.ok()

	# 3. Windows 等平台不支持直接覆盖已存在文件：采用 Swap 备份回滚协议，绝不裸删目标文件
	var swap_path := dst_path + SWAP_SUFFIX
	if FileAccess.file_exists(swap_path):
		DirAccess.remove_absolute(swap_path)

	var backup_err := DirAccess.rename_absolute(dst_path, swap_path)
	if backup_err != OK:
		return _err_from_godot(ERR_IO_ERROR, "Rename failed: target '%s' is locked or cannot be replaced (err=%d)." % [dst_path, backup_err], backup_err, {"src": src_path, "dst": dst_path})

	var promote_err := DirAccess.rename_absolute(src_path, dst_path)
	if promote_err != OK:
		# 新文件就位失败：立即将原目标文件从 swap 恢复，确保目标数据不丢失
		DirAccess.rename_absolute(swap_path, dst_path)
		return _err_from_godot(ERR_IO_ERROR, "Rename failed: from '%s' to '%s', rolled back target (err=%d)." % [src_path, dst_path, promote_err], promote_err, {"src": src_path, "dst": dst_path})

	DirAccess.remove_absolute(swap_path)
	return Result.ok()

#endregion


#region Core Operator 4: Cryptographic Integrity & Hashing (MD5 / SHA-256)

## 计算指定文件的 32 位小写十六进制 MD5 摘要。[br]
## 成功时 [member Result.value] 为小写 MD5 字符串。
static func md5(filepath: String) -> Result:
	var guard := _validate_read_path(filepath)
	if guard.is_err():
		return guard

	var digest := FileAccess.get_md5(filepath).strip_edges().to_lower()
	if digest.is_empty():
		return Result.err_ex(ERR_IO_ERROR, "MD5 calculation failed for '%s'." % filepath, {"path": filepath}, false, null, FrameworkError.CATEGORY_IO)
	return Result.ok(digest)


## 计算指定文件的 64 位小写十六进制 SHA-256 摘要。[br]
## 成功时 [member Result.value] 为小写 SHA-256 字符串。
static func sha256(filepath: String) -> Result:
	var guard := _validate_read_path(filepath)
	if guard.is_err():
		return guard

	var digest := FileAccess.get_sha256(filepath).strip_edges().to_lower()
	if digest.is_empty():
		return Result.err_ex(ERR_IO_ERROR, "SHA-256 calculation failed for '%s'." % filepath, {"path": filepath}, false, null, FrameworkError.CATEGORY_IO)
	return Result.ok(digest)


## 校验文件 MD5 是否与预期值匹配（自动忽略大小写与首尾空白）。[br]
## 成功时 [member Result.value] 为实际的小写 MD5 字符串；不匹配时返回 [constant ERR_HASH_MISMATCH]。
static func verify_md5(filepath: String, expected_md5: String) -> Result:
	var expected_norm := expected_md5.strip_edges().to_lower()
	if expected_norm.is_empty():
		return Result.err_ex(ERR_INVALID_PATH, "Verify MD5 failed: expected_md5 is empty.", {"path": filepath}, false, null, FrameworkError.CATEGORY_PARAM)

	var md5_res := md5(filepath)
	if md5_res.is_err():
		return md5_res

	var actual_md5: String = md5_res.value
	if actual_md5 != expected_norm:
		return Result.err_ex(
			ERR_HASH_MISMATCH,
			"MD5 mismatch for '%s' (expected %s, got %s)." % [filepath, expected_norm, actual_md5],
			{"path": filepath, "expected": expected_norm, "actual": actual_md5},
			true,
			ERR_FILE_CORRUPT,
			FrameworkError.CATEGORY_VALIDATION
		)

	return Result.ok(actual_md5)

#endregion


#region Core Operator 5: VFS Introspection, Metadata & Resource Materialization

## 判断指定路径的物理或虚拟文件是否存在。
static func file_exists(filepath: String) -> bool:
	if filepath.is_empty():
		return false
	return FileAccess.file_exists(filepath)


## 判断文件或导出包内已编译资源是否存在（兼容导出后被转为 [code].remap[/code] / [code].ctex[/code] 的 [code]res://[/code] 资产）。
static func resource_or_file_exists(filepath: String) -> bool:
	if filepath.is_empty():
		return false
	if FileAccess.file_exists(filepath):
		return true
	return filepath.begins_with("res://") and ResourceLoader.exists(filepath)


## 判断指定目录是否存在（兼容 [code]res://[/code] 导出包与本地目录）。
static func dir_exists(dirpath: String) -> bool:
	if dirpath.is_empty():
		return false
	if DirAccess.dir_exists_absolute(dirpath):
		return true
	if dirpath.begins_with("res://"):
		return not ResourceLoader.list_directory(_normalize_res_dir(dirpath)).is_empty()
	return false


## 零拷贝获取文件字节大小（文件不存在或无法打开时返回 [code]-1[/code]）。
static func get_file_size(filepath: String) -> int:
	if filepath.is_empty() or not FileAccess.file_exists(filepath):
		return -1
	var file := FileAccess.open(filepath, FileAccess.READ)
	if file == null:
		return -1
	var size := int(file.get_length())
	file.close()
	return size


## 获取文件最后修改的 Unix 时间戳（秒；文件不存在时返回 [code]0[/code]）。
static func get_modified_time(filepath: String) -> int:
	if filepath.is_empty() or not FileAccess.file_exists(filepath):
		return 0
	return int(FileAccess.get_modified_time(filepath))


## 将虚拟路径（[code]res://[/code] 或 [code]user://[/code]）解析为操作系统原生绝对路径。
static func globalize_path(filepath: String) -> String:
	if filepath.is_empty():
		return ""
	if filepath.begins_with("res://") or filepath.begins_with("user://"):
		return ProjectSettings.globalize_path(filepath)
	return filepath


## 将 [code]res://[/code] 封包内文件实体化（Materialize）为操作系统可直接访问的真实物理文件路径。[br]
## - 若文件在 OS 文件系统中已直接存在（如编辑器环境或 [code]user://[/code]），直接返回其绝对路径；[br]
## - 若文件位于导出后的只读 PCK / APK 封包内，自动按路径 MD5 指纹流式解包至 [param cache_dir] 并返回缓存绝对路径。
static func materialize_res_file(
	file_path: String,
	cache_dir: String = "user://res_cache"
) -> Result:
	if file_path.is_empty():
		return Result.err_ex(ERR_EMPTY_PATH, "Materialize failed: file_path is empty.", {}, false, null, FrameworkError.CATEGORY_PARAM)

	if not file_path.begins_with("res://") and not file_path.begins_with("user://"):
		return Result.ok(file_path)

	var global_path := ProjectSettings.globalize_path(file_path)
	if FileAccess.file_exists(global_path):
		return Result.ok(global_path)

	if not file_path.begins_with("res://"):
		return Result.err_ex(ERR_NOT_FOUND, "Materialize failed: file not found at '%s'." % file_path, {"path": file_path}, false, ERR_FILE_NOT_FOUND, FrameworkError.CATEGORY_NOT_FOUND)

	var ext := file_path.get_extension()
	var cache_name := file_path.md5_text() + ("." + ext if not ext.is_empty() else "")
	var cache_virtual := cache_dir.path_join(cache_name)
	var cache_absolute := ProjectSettings.globalize_path(cache_virtual)

	if FileAccess.file_exists(cache_absolute) and get_file_size(cache_virtual) > 0:
		return Result.ok(cache_absolute)

	var copy_res := _stream_copy_file(file_path, cache_virtual)
	if copy_res.is_err():
		return copy_res

	return Result.ok(cache_absolute)

#endregion


#region Core Operator 6: Directory Tree Lifecycle & Traversal

## 确保指定的目录路径存在。如果不存在，会自动递归创建。[br]
## [param dirpath] 目录路径，例如 [code]user://saves[/code]。[br]
## 返回 [Result]：成功时 [member Result.value] 为空；失败时返回详细错误。
static func ensure_dir_exists(dirpath: String) -> Result:
	if dirpath.is_empty() or dirpath == "res://" or dirpath == "user://":
		return Result.ok()

	var guard := _validate_write_path(dirpath)
	if guard.is_err():
		return guard

	if not DirAccess.dir_exists_absolute(dirpath):
		var err := DirAccess.make_dir_recursive_absolute(dirpath)
		if err != OK:
			return _err_from_godot(ERR_DIR_FAILED, "Create directory failed: '%s' (err=%d)." % [dirpath, err], err, {"path": dirpath})

	return Result.ok()


## 清空指定目录下的所有文件与子目录，但保留该目录本身（目录不存在时视为空操作返回成功）。
static func clear_dir(dirpath: String) -> Result:
	var guard := _validate_write_path(dirpath)
	if guard.is_err():
		return guard

	if not DirAccess.dir_exists_absolute(dirpath):
		return Result.ok()

	var dir := DirAccess.open(dirpath)
	if dir == null:
		return _err_from_godot(ERR_DIR_FAILED, "Clear directory failed: cannot open '%s'." % dirpath, DirAccess.get_open_error(), {"path": dirpath})

	for file_name in dir.get_files():
		var file_path := dirpath.path_join(file_name)
		var rm_res := remove_file(file_path)
		if rm_res.is_err():
			return rm_res

	for subdir_name in dir.get_directories():
		var subdir_path := dirpath.path_join(subdir_name)
		var sub_res := remove_dir_recursive(subdir_path)
		if sub_res.is_err():
			return sub_res

	return Result.ok()


## 递归删除目录及其包含的所有文件与子目录（内置根卷防呆保护，禁止直接删除 [code]user://[/code] 或 [code]res://[/code] 根）。
static func remove_dir_recursive(dirpath: String) -> Result:
	var clean_dir := dirpath.strip_edges().trim_suffix("/")
	if clean_dir.is_empty() or clean_dir == "user:" or clean_dir == "res:":
		return Result.err_ex(ERR_INVALID_PATH, "Remove directory refused: cannot delete root volume '%s'." % dirpath, {"path": dirpath}, false, null, FrameworkError.CATEGORY_PARAM)

	var clear_res := clear_dir(dirpath)
	if clear_res.is_err():
		return clear_res

	if DirAccess.dir_exists_absolute(dirpath):
		var err := DirAccess.remove_absolute(dirpath)
		if err != OK:
			return _err_from_godot(ERR_DIR_FAILED, "Remove directory failed: cannot remove '%s' (err=%d)." % [dirpath, err], err, {"path": dirpath})

	return Result.ok()


## 显式返回 [Result] 的目录文件扫描算子（区分“空目录”与“目录不存在/无权限”）。[br]
## [param dir_path] 目标目录路径。[br]
## [param exclude_import] 是否过滤 Godot 编译伴生文件（[code].import[/code] / [code].remap[/code] / [code].uid[/code]）。[br]
## [param recursive] 是否递归扫描所有子目录（递归时返回相对于 [param dir_path] 的子路径）。[br]
## [param extensions] 可选扩展名白名单（如 [code]["json", "tres"][/code]，不含点号，大小写不敏感）。[br]
## 成功时 [member Result.value] 为 [code]Array[String][/code]。
static func scan_files(
	dir_path: String,
	exclude_import: bool = true,
	recursive: bool = false,
	extensions: PackedStringArray = PackedStringArray()
) -> Result:
	if dir_path.is_empty():
		return Result.err_ex(ERR_EMPTY_PATH, "Scan directory failed: dir_path is empty.", {}, false, null, FrameworkError.CATEGORY_PARAM)

	if not dir_exists(dir_path):
		return Result.err_ex(ERR_NOT_FOUND, "Scan directory failed: directory not found '%s'." % dir_path, {"path": dir_path}, false, ERR_FILE_NOT_FOUND, FrameworkError.CATEGORY_NOT_FOUND)

	var out: Array[String] = []
	_collect_files_internal(dir_path, "", exclude_import, recursive, extensions, out)
	out.sort()
	return Result.ok(out)


## 列举目录下文件（不含子目录），按文件名排序。[br]
## [code]res://[/code] 路径优先使用 [method ResourceLoader.list_directory]，导出包内可正确枚举资源；[br]
## 自动统一过滤 [code].import[/code]、[code].remap[/code] 与 [code].uid[/code] 引擎伴生文件。
static func list_files(dir_path: String, exclude_import: bool = true) -> Array[String]:
	if dir_path.is_empty():
		return []
	var out: Array[String] = []
	_collect_files_internal(dir_path, "", exclude_import, false, PackedStringArray(), out)
	out.sort()
	return out


## 列举目录下文件的完整路径（使用 [method String.path_join] 安全拼接，支持递归遍历与扩展名过滤）。
static func list_file_paths(
	dir_path: String,
	exclude_import: bool = true,
	recursive: bool = false,
	extensions: PackedStringArray = PackedStringArray()
) -> Array[String]:
	if dir_path.is_empty():
		return []
	var rel_files: Array[String] = []
	_collect_files_internal(dir_path, "", exclude_import, recursive, extensions, rel_files)
	rel_files.sort()

	var paths: Array[String] = []
	paths.resize(rel_files.size())
	for i in rel_files.size():
		paths[i] = dir_path.path_join(rel_files[i])
	return paths


## 列举目录下子文件夹，按名称排序。[br]
## [code]res://[/code] 路径使用 [method ResourceLoader.list_directory]，导出包内可正确枚举资源。
static func list_subdirs(dir_path: String) -> Array[String]:
	if dir_path.is_empty():
		return []
	if dir_path.begins_with("res://"):
		return _list_res_subdirs(dir_path)

	var subdirs: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return subdirs

	subdirs.assign(dir.get_directories())
	subdirs.sort()
	return subdirs

#endregion


#region Private Atomic & VFS Helpers

static func _write_bytes_direct(filepath: String, bytes: PackedByteArray) -> Result:
	var dir_res := ensure_dir_exists(filepath.get_base_dir())
	if dir_res.is_err():
		return dir_res

	var file := FileAccess.open(filepath, FileAccess.WRITE)
	if file == null:
		return _err_from_godot(ERR_OPEN_FAILED, "Write failed: cannot open '%s'." % filepath, FileAccess.get_open_error(), {"path": filepath})

	var stored := true
	if not bytes.is_empty():
		stored = file.store_buffer(bytes)
	file.flush()
	var io_err := file.get_error()
	file.close()

	if not stored or io_err != OK:
		return _err_from_godot(ERR_IO_ERROR, "Write failed: I/O error while writing '%s'." % filepath, io_err if io_err != OK else ERR_FILE_CANT_WRITE, {"path": filepath, "bytes": bytes.size()})

	return Result.ok()


static func _stream_copy_file(src_path: String, dst_path: String) -> Result:
	var dir_res := ensure_dir_exists(dst_path.get_base_dir())
	if dir_res.is_err():
		return dir_res

	var src := FileAccess.open(src_path, FileAccess.READ)
	if src == null:
		return _err_from_godot(ERR_OPEN_FAILED, "Copy failed: cannot open source '%s'." % src_path, FileAccess.get_open_error(), {"src": src_path, "dst": dst_path})

	var tmp_dst := dst_path + TMP_SUFFIX
	var dst := FileAccess.open(tmp_dst, FileAccess.WRITE)
	if dst == null:
		src.close()
		return _err_from_godot(ERR_OPEN_FAILED, "Copy failed: cannot open destination '%s'." % tmp_dst, FileAccess.get_open_error(), {"src": src_path, "dst": dst_path})

	var total_len := src.get_length()
	var remaining := total_len
	var io_ok := true

	while remaining > 0:
		var step := mini(remaining, CHUNK_SIZE)
		var chunk := src.get_buffer(step)
		if chunk.size() != step or not dst.store_buffer(chunk):
			io_ok = false
			break
		remaining -= step

	dst.flush()
	var src_err := src.get_error()
	var dst_err := dst.get_error()
	src.close()
	dst.close()

	if not io_ok or (src_err != OK and src_err != ERR_FILE_EOF) or dst_err != OK:
		remove_file(tmp_dst)
		return _err_from_godot(
			ERR_IO_ERROR,
			"Copy failed: stream transfer interrupted from '%s' to '%s'." % [src_path, dst_path],
			dst_err if dst_err != OK else src_err,
			{"src": src_path, "dst": dst_path}
		)

	var rename_res := rename_file(tmp_dst, dst_path)
	if rename_res.is_err():
		remove_file(tmp_dst)
		return rename_res

	return Result.ok()


static func _validate_read_path(filepath: String) -> Result:
	if filepath.is_empty():
		return Result.err_ex(ERR_EMPTY_PATH, "Read failed: path is empty.", {}, false, null, FrameworkError.CATEGORY_PARAM)
	if not FileAccess.file_exists(filepath):
		return Result.err_ex(ERR_NOT_FOUND, "Read failed: file not found: %s." % filepath, {"path": filepath}, false, ERR_FILE_NOT_FOUND, FrameworkError.CATEGORY_NOT_FOUND)
	return Result.ok()


static func _validate_write_path(filepath: String) -> Result:
	if filepath.is_empty():
		return Result.err_ex(ERR_EMPTY_PATH, "Write failed: path is empty.", {}, false, null, FrameworkError.CATEGORY_PARAM)
	if filepath.begins_with("res://") and not OS.has_feature("editor"):
		return Result.err_ex(
			ERR_READ_ONLY,
			"Write failed: 'res://' volume is read-only in exported builds ('%s')." % filepath,
			{"path": filepath},
			false,
			ERR_FILE_NO_PERMISSION,
			FrameworkError.CATEGORY_IO
		)
	return Result.ok()


static func _is_same_path(path_a: String, path_b: String) -> bool:
	if path_a == path_b:
		return true
	var norm_a := globalize_path(path_a).simplify_path()
	var norm_b := globalize_path(path_b).simplify_path()
	if OS.get_name() == "Windows" or OS.get_name() == "macOS":
		return norm_a.to_lower() == norm_b.to_lower()
	return norm_a == norm_b


static func _err_from_godot(
	code: String,
	message: String,
	godot_err: Error,
	context: Dictionary = {}
) -> Result:
	var ctx := context.duplicate()
	ctx["godot_err"] = int(godot_err)
	ctx["godot_err_str"] = error_string(godot_err)
	var retryable := (godot_err == ERR_BUSY or godot_err == ERR_LOCKED or godot_err == ERR_TIMEOUT)
	var category := FrameworkError.CATEGORY_NOT_FOUND if godot_err == ERR_FILE_NOT_FOUND else FrameworkError.CATEGORY_IO
	return Result.err_ex(code, "%s (err=%d: %s)" % [message, godot_err, error_string(godot_err)], ctx, retryable, godot_err, category)


static func _is_engine_sidecar_file(file_name: String) -> bool:
	return file_name.ends_with(".import") or file_name.ends_with(".remap") or file_name.ends_with(".uid")


static func _matches_extensions(file_name: String, extensions: PackedStringArray) -> bool:
	if extensions.is_empty():
		return true
	var ext := file_name.get_extension().to_lower()
	for allowed in extensions:
		if ext == allowed.trim_prefix(".").to_lower():
			return true
	return false


static func _collect_files_internal(
	root_dir: String,
	rel_prefix: String,
	exclude_import: bool,
	recursive: bool,
	extensions: PackedStringArray,
	out_files: Array[String]
) -> void:
	var current_dir := root_dir if rel_prefix.is_empty() else root_dir.path_join(rel_prefix)
	var entries: Array[String] = _list_res_files(current_dir, exclude_import) if current_dir.begins_with("res://") else _list_os_files(current_dir, exclude_import)

	for file_name in entries:
		if not _matches_extensions(file_name, extensions):
			continue
		out_files.append(file_name if rel_prefix.is_empty() else rel_prefix.path_join(file_name))

	if not recursive:
		return

	var subdirs: Array[String] = _list_res_subdirs(current_dir) if current_dir.begins_with("res://") else _list_os_subdirs(current_dir)
	for subdir in subdirs:
		var next_prefix := subdir if rel_prefix.is_empty() else rel_prefix.path_join(subdir)
		_collect_files_internal(root_dir, next_prefix, exclude_import, true, extensions, out_files)


static func _normalize_res_dir(dir_path: String) -> String:
	return dir_path if dir_path.ends_with("/") else dir_path + "/"


static func _list_res_files(dir_path: String, exclude_import: bool) -> Array[String]:
	var file_names: Array[String] = []
	for entry: String in ResourceLoader.list_directory(_normalize_res_dir(dir_path)):
		if entry.ends_with("/"):
			continue
		if exclude_import and _is_engine_sidecar_file(entry):
			continue
		file_names.append(entry)
	file_names.sort()
	return file_names


static func _list_os_files(dir_path: String, exclude_import: bool) -> Array[String]:
	var file_names: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return file_names

	for file_name: String in dir.get_files():
		if exclude_import and _is_engine_sidecar_file(file_name):
			continue
		file_names.append(file_name)
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


static func _list_os_subdirs(dir_path: String) -> Array[String]:
	var subdirs: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return subdirs
	subdirs.assign(dir.get_directories())
	subdirs.sort()
	return subdirs

#endregion
