class_name DiskStorageDriver
extends StorageDriver

## 磁盘存储驱动：负责处理本地磁盘的序列化写入和读取。[br]
##
## 本驱动将传入的 [param key] 视为本地合法路径（如 [code]user://[/code] 或 [code]res://[/code]）。[br]
## 按 [param kwargs] 的 [code]payload_type[/code] 分支，不按扩展名嗅探类型：[br]
## - [code]JSON[/code]（默认）：读写 Dictionary / Array。[br]
## - [code]FILE[/code]：读写不透明二进制（[PackedByteArray]），不做图片/音频解码。[br]
##
## 内置工业级原子双写与容灾备份自愈机制（Atomic Save & Backup Self-Healing）：[br]
## - 写入时：先写 .tmp，成功后将旧主文件备份为 .bak，再原子重命名 .tmp 为主文件，彻底消除断电/强杀导致的坏档 (Torn Write)。[br]
## - 读取时：主文件损坏（非法 JSON / 0 字节等）时，自动尝试从 .bak 恢复自愈，保障数据高可用。[br]
## - 控制项：kwargs["use_backup"]（默认 true，大文件/临时缓存可传 false 关闭）。

const EXT_BAK := ".bak"
const EXT_TMP := ".tmp"

var _log_service: BaseFrameworkLogger


func _init(log_service: BaseFrameworkLogger = null) -> void:
	_log_service = log_service


func set_log_service(log_service: BaseFrameworkLogger) -> void:
	_log_service = log_service


#region Overrides
## 从磁盘读取。[br]
## [b]kwargs：[/b][br]
## - [code]payload_type[/code]：[code]"JSON"[/code] 或 [code]"FILE"[/code]。[br]
## - [code]expected_md5[/code]：仅 FILE，非空时校验磁盘文件 md5，不匹配则失败。[br]
## - [code]use_backup[/code]：主文件异常时是否尝试自愈，默认 true。
func read(key: StringName, kwargs: Dictionary = {}) -> Result:
	var path := str(key)
	var use_backup: bool = bool(kwargs.get("use_backup", true))

	# 1. 优先尝试读取主文件
	if FileUtils.file_exists(path):
		var primary_res := _read_raw(path, kwargs)
		if primary_res.is_ok():
			return primary_res
		# 主文件存在但解析损坏 (Parse error/MD5 mismatch/0字节)
		if not use_backup:
			return primary_res
		_warn("Primary file corrupted, trying backup: %s (err: %s)" % [path, primary_res.error])

	# 2. 主文件缺失或损坏，尝试从 .bak 备份自愈
	if use_backup:
		var bak_path := path + EXT_BAK
		if FileUtils.file_exists(bak_path):
			var bak_res := _read_raw(bak_path, kwargs)
			if bak_res.is_ok():
				_warn("Self-healing from backup: %s -> %s" % [bak_path, path])
				FileUtils.copy_file(bak_path, path)
				return bak_res

	return Result.err(ERR_DOES_NOT_EXIST)


## 写入磁盘。[br]
## FILE 时 [param data] 必须是 [PackedByteArray]。[br]
## 默认采用原子临时写入 + .bak 备份机制。
func write(key: StringName, data: Variant, kwargs: Dictionary = {}) -> Result:
	var path := str(key)
	var use_backup: bool = bool(kwargs.get("use_backup", true))

	if not use_backup:
		return _write_raw(path, data, kwargs)

	# 1. 写入临时文件
	var tmp_path := path + EXT_TMP
	var write_res := _write_raw(tmp_path, data, kwargs)
	if write_res.is_err():
		FileUtils.remove_file(tmp_path)
		return write_res

	# 2. 主文件存在时，将其安全复制为 .bak 备份
	if FileUtils.file_exists(path):
		var bak_path := path + EXT_BAK
		FileUtils.copy_file(path, bak_path)

	# 3. 将 .tmp 原子提升为主文件
	var rename_res := FileUtils.rename_file(tmp_path, path)
	if rename_res.is_err():
		FileUtils.remove_file(tmp_path)
		return rename_res

	return Result.ok()


## 检查文件是否存在（主文件或有效备份存在即视为存在）
func has(key: StringName) -> Result:
	var path := str(key)
	var exists := FileUtils.file_exists(path) or FileUtils.file_exists(path + EXT_BAK)
	return Result.ok(exists)


## 删除物理文件（同时安全清理主文件、.bak 备份与 .tmp 临时文件）
func delete(key: StringName) -> Result:
	var path := str(key)
	var main_exists := FileUtils.file_exists(path)
	var bak_exists := FileUtils.file_exists(path + EXT_BAK)
	var tmp_exists := FileUtils.file_exists(path + EXT_TMP)

	if not (main_exists or bak_exists or tmp_exists):
		return Result.err(ERR_DOES_NOT_EXIST)

	FileUtils.remove_file(path)
	FileUtils.remove_file(path + EXT_BAK)
	FileUtils.remove_file(path + EXT_TMP)
	return Result.ok()
#endregion

#region Private Helpers
func _warn(message: String) -> void:
	if _log_service != null:
		_log_service.warn("DiskStorageDriver", message)
	else:
		push_warning("DiskStorageDriver: %s" % message)


func _payload_type(kwargs: Dictionary) -> String:
	return str(kwargs.get("payload_type", "JSON")).to_upper()


func _read_raw(path: String, kwargs: Dictionary) -> Result:
	if _payload_type(kwargs) == "FILE":
		return _read_file(path, kwargs)
	return FileUtils.read_json(path)


func _write_raw(path: String, data: Variant, kwargs: Dictionary) -> Result:
	if _payload_type(kwargs) == "FILE":
		return _write_file(path, data)
	return FileUtils.write_json(path, data)


func _read_file(path: String, kwargs: Dictionary) -> Result:
	var expected_md5: String = str(kwargs.get("expected_md5", ""))
	if not expected_md5.is_empty() and FileAccess.get_md5(path) != expected_md5:
		return Result.err("Disk FILE md5 mismatch: %s" % path)
	return FileUtils.read_bytes(path)


func _write_file(path: String, data: Variant) -> Result:
	if not data is PackedByteArray:
		return Result.err("Disk FILE write expects PackedByteArray.")
	return FileUtils.write_bytes(path, data)
#endregion
