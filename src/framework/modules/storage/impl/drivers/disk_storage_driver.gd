class_name DiskStorageDriver
extends StorageDriver

## 磁盘存储驱动：负责处理本地磁盘的序列化、压缩/加密与容灾自愈读写。[br]
##
## 核心职责：[br]
## 1. 按 [param kwargs] 的 [code]payload_type[/code] 严格分支（不按扩展名猜测）：[br]
##    - [code]JSON[/code]（默认）：读写 [Dictionary] / [Array]；[br]
##    - [code]FILE[/code]：读写不透明二进制（[PackedByteArray]）；[br]
## 2. [b]可选透明压缩与加密[/b]：支持基于 [FileUtils] 的 ZSTD 压缩（[code]compressed = true[/code]）与 AES-256 加密（[code]encryption_key != ""[/code]）；[br]
## 3. [b]事务级原子双写与容灾自愈（Atomic Save & Backup Self-Healing）[/b]：[br]
##    - 写入时：先写 [code].tmp[/code]，成功后将旧主文件安全复制为 [code].bak[/code]，再原子重命名 [code].tmp[/code] 为主文件；[br]
##    - 读取时：主文件缺失或损坏（JSON 解析失败 / 解密失败 / MD5 不匹配）时，自动从 [code].bak[/code] 恢复主文件并返回数据。

const EXT_BAK := ".bak"
const EXT_TMP := ".tmp"

var _log_service: BaseFrameworkLogger


func _init(log_service: BaseFrameworkLogger = null) -> void:
	_log_service = log_service


func set_log_service(log_service: BaseFrameworkLogger) -> void:
	_log_service = log_service


#region Overrides
## 从磁盘读取。[br]
## [b]kwargs 支持项：[/b][br]
## - [code]payload_type[/code]：[code]"JSON"[/code] 或 [code]"FILE"[/code]；[br]
## - [code]use_backup[/code]：主文件异常时是否尝试从 `.bak` 自愈（默认 `true`）；[br]
## - [code]compressed[/code]：是否启用 ZSTD 解压（默认 `false`）；[br]
## - [code]encryption_key[/code]：非空时启用 AES-256 解密；[br]
## - [code]expected_md5[/code]：仅 `FILE` 模式，非空时校验文件 MD5。
func read(key: StringName, kwargs: Dictionary = {}) -> Result:
	var path := str(key).strip_edges()
	if path.is_empty():
		return Result.err_ex(StorageError.INVALID_PARAM, "Disk read failed: path is empty.", {}, false, null, FrameworkError.CATEGORY_PARAM)

	var use_backup: bool = bool(kwargs.get("use_backup", true))
	var primary_err: Result = null

	# 1. 优先尝试读取主文件
	if FileUtils.file_exists(path):
		var primary_res := _read_raw(path, kwargs)
		if primary_res.is_ok():
			return primary_res
		primary_err = primary_res
		if not use_backup:
			return _wrap_disk_error(primary_res, path)
		_warn("Primary file corrupted, trying backup: %s (err: %s)" % [path, primary_res.error_message()])

	# 2. 主文件缺失或损坏，尝试从 .bak 备份自愈
	if use_backup:
		var bak_path := path + EXT_BAK
		if FileUtils.file_exists(bak_path):
			var bak_res := _read_raw(bak_path, kwargs)
			if bak_res.is_ok():
				_warn("Self-healing from backup: %s -> %s" % [bak_path, path])
				var heal_res := FileUtils.copy_file(bak_path, path)
				if heal_res.is_err():
					_warn("Self-healing copy failed for '%s': %s" % [path, heal_res.error_message()])
				return bak_res
			elif primary_err == null:
				primary_err = bak_res

	if primary_err != null:
		return _wrap_disk_error(primary_err, path)

	return Result.err_ex(
		StorageError.NOT_FOUND,
		"Disk file not found: '%s'." % path,
		{"path": path},
		false,
		ERR_DOES_NOT_EXIST,
		FrameworkError.CATEGORY_NOT_FOUND
	)


## 写入磁盘（默认采用 `.tmp` 原子写入 + `.bak` 容灾备份机制）。
func write(key: StringName, data: Variant, kwargs: Dictionary = {}) -> Result:
	var path := str(key).strip_edges()
	if path.is_empty():
		return Result.err_ex(StorageError.INVALID_PARAM, "Disk write failed: path is empty.", {}, false, null, FrameworkError.CATEGORY_PARAM)

	var use_backup: bool = bool(kwargs.get("use_backup", true))
	if not use_backup:
		var direct_res := _write_raw(path, data, kwargs, true)
		return _wrap_disk_error(direct_res, path) if direct_res.is_err() else Result.ok()

	# 1. 先写入独立 .tmp 临时文件
	var tmp_path := path + EXT_TMP
	var write_res := _write_raw(tmp_path, data, kwargs, false)
	if write_res.is_err():
		FileUtils.remove_file(tmp_path)
		return _wrap_disk_error(write_res, path)

	# 2. 旧主文件存在且非空时，将其安全复制为 .bak 备份
	if FileUtils.file_exists(path) and FileUtils.get_file_size(path) > 0:
		var bak_path := path + EXT_BAK
		var bak_res := FileUtils.copy_file(path, bak_path)
		if bak_res.is_err():
			_warn("Failed to update backup file '%s': %s" % [bak_path, bak_res.error_message()])

	# 3. 将 .tmp 原子提升为主文件
	var rename_res := FileUtils.rename_file(tmp_path, path)
	if rename_res.is_err():
		FileUtils.remove_file(tmp_path)
		return _wrap_disk_error(rename_res, path)

	return Result.ok()


## 检查文件是否存在（主文件或有效 `.bak` 备份存在即视为存在）
func has(key: StringName) -> Result:
	var path := str(key).strip_edges()
	if path.is_empty():
		return Result.ok(false)
	var exists := FileUtils.file_exists(path) or FileUtils.file_exists(path + EXT_BAK)
	return Result.ok(exists)


## 删除物理文件（幂等清理主文件、`.bak` 备份与 `.tmp` 临时文件）
func delete(key: StringName) -> Result:
	var path := str(key).strip_edges()
	if path.is_empty():
		return Result.ok()

	var r1 := FileUtils.remove_file(path)
	var r2 := FileUtils.remove_file(path + EXT_BAK)
	var r3 := FileUtils.remove_file(path + EXT_TMP)

	if r1.is_err():
		return _wrap_disk_error(r1, path)
	if r2.is_err():
		return _wrap_disk_error(r2, path + EXT_BAK)
	if r3.is_err():
		return _wrap_disk_error(r3, path + EXT_TMP)

	return Result.ok()
#endregion


#region Private Read / Write Operators
func _warn(message: String) -> void:
	if _log_service != null:
		_log_service.warn("DiskStorageDriver", message)
	else:
		push_warning("DiskStorageDriver: %s" % message)


func _payload_type(kwargs: Dictionary) -> String:
	return str(kwargs.get("payload_type", "JSON")).to_upper()


func _read_raw(path: String, kwargs: Dictionary) -> Result:
	if _payload_type(kwargs) == "FILE":
		return _read_file_payload(path, kwargs)
	return _read_json_payload(path, kwargs)


func _write_raw(path: String, data: Variant, kwargs: Dictionary, atomic: bool) -> Result:
	if _payload_type(kwargs) == "FILE":
		return _write_file_payload(path, data, kwargs, atomic)
	return _write_json_payload(path, data, kwargs, atomic)


func _read_json_payload(path: String, kwargs: Dictionary) -> Result:
	var enc_key := str(kwargs.get("encryption_key", ""))
	var compressed := bool(kwargs.get("compressed", false))

	if enc_key.is_empty() and not compressed:
		return FileUtils.read_json(path)

	var bytes_res: Result
	if not enc_key.is_empty():
		bytes_res = FileUtils.read_encrypted(path, enc_key)
	else:
		bytes_res = FileUtils.read_compressed(path)

	if bytes_res.is_err():
		return bytes_res

	var raw_bytes: PackedByteArray = bytes_res.value
	var text := raw_bytes.get_string_from_utf8().strip_edges()
	if text.is_empty():
		return Result.err_ex(StorageError.PARSE_ERROR, "Decoded JSON file '%s' is empty." % path, {"path": path}, false, null, FrameworkError.CATEGORY_VALIDATION)

	var json := JSON.new()
	var parse_err := json.parse(text)
	if parse_err != OK or not (json.data is Dictionary or json.data is Array):
		return Result.err_ex(
			StorageError.PARSE_ERROR,
			"Invalid JSON in '%s' (line %d: %s)." % [path, json.get_error_line(), json.get_error_message()],
			{"path": path, "line": json.get_error_line()},
			false,
			parse_err,
			FrameworkError.CATEGORY_VALIDATION
		)
	return Result.ok(json.data)


func _write_json_payload(path: String, data: Variant, kwargs: Dictionary, atomic: bool) -> Result:
	if not (data is Dictionary or data is Array):
		return Result.err_ex(
			StorageError.INVALID_PARAM,
			"Disk JSON write expects Dictionary or Array for '%s'." % path,
			{"path": path, "actual_type": type_string(typeof(data))},
			false,
			null,
			FrameworkError.CATEGORY_PARAM
		)

	var enc_key := str(kwargs.get("encryption_key", ""))
	var compressed := bool(kwargs.get("compressed", false))

	if enc_key.is_empty() and not compressed:
		return FileUtils.write_json(path, data, false, atomic)

	var json_str := JSON.stringify(data)
	if json_str.is_empty():
		return Result.err_ex(StorageError.PARSE_ERROR, "Failed to serialize JSON for '%s'." % path, {"path": path}, false, null, FrameworkError.CATEGORY_VALIDATION)

	var raw_bytes := json_str.to_utf8_buffer()
	if not enc_key.is_empty():
		return FileUtils.write_encrypted(path, raw_bytes, enc_key, atomic)
	return FileUtils.write_compressed(path, raw_bytes, FileAccess.COMPRESSION_ZSTD, atomic)


func _read_file_payload(path: String, kwargs: Dictionary) -> Result:
	var expected_md5: String = str(kwargs.get("expected_md5", "")).strip_edges()
	if not expected_md5.is_empty():
		var md5_res := FileUtils.verify_md5(path, expected_md5)
		if md5_res.is_err():
			return Result.err_ex(
				StorageError.HASH_MISMATCH,
				md5_res.error_message(),
				{"path": path, "expected_md5": expected_md5},
				false,
				md5_res.error,
				FrameworkError.CATEGORY_VALIDATION
			)

	var enc_key := str(kwargs.get("encryption_key", ""))
	var compressed := bool(kwargs.get("compressed", false))
	if not enc_key.is_empty():
		return FileUtils.read_encrypted(path, enc_key)
	if compressed:
		return FileUtils.read_compressed(path)
	return FileUtils.read_bytes(path)


func _write_file_payload(path: String, data: Variant, kwargs: Dictionary, atomic: bool) -> Result:
	if not (data is PackedByteArray):
		return Result.err_ex(
			StorageError.INVALID_PARAM,
			"Disk FILE write expects PackedByteArray for '%s'." % path,
			{"path": path, "actual_type": type_string(typeof(data))},
			false,
			null,
			FrameworkError.CATEGORY_PARAM
		)

	var bytes := data as PackedByteArray
	var enc_key := str(kwargs.get("encryption_key", ""))
	var compressed := bool(kwargs.get("compressed", false))
	if not enc_key.is_empty():
		return FileUtils.write_encrypted(path, bytes, enc_key, atomic)
	if compressed:
		return FileUtils.write_compressed(path, bytes, FileAccess.COMPRESSION_ZSTD, atomic)
	return FileUtils.write_bytes(path, bytes, atomic)


static func _wrap_disk_error(res: Result, path: String) -> Result:
	var code := res.error_code()
	if code.begins_with("Storage."):
		return res
	if code == FileUtils.ERR_HASH_MISMATCH:
		return Result.err_ex(StorageError.HASH_MISMATCH, res.error_message(), {"path": path}, false, res.error, FrameworkError.CATEGORY_VALIDATION)
	if code == FileUtils.ERR_PARSE_ERROR:
		return Result.err_ex(StorageError.PARSE_ERROR, res.error_message(), {"path": path}, false, res.error, FrameworkError.CATEGORY_VALIDATION)
	if code == FileUtils.ERR_NOT_FOUND:
		return Result.err_ex(StorageError.NOT_FOUND, res.error_message(), {"path": path}, false, res.error, FrameworkError.CATEGORY_NOT_FOUND)
	return Result.err_ex(StorageError.IO_ERROR, res.error_message(), {"path": path}, res.is_retryable(), res.error, FrameworkError.CATEGORY_IO)
#endregion
