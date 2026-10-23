class_name RemoteStorageDriver
extends StorageDriver

## 远端存储驱动：封装自建 HTTP 云存档、文件流传输与 Steam Cloud (`ISteamRemoteStorage`) 双通道存储操作。[br]
##
## 核心职责：[br]
## 1. 支持 [code]http(s)://[/code] 自建网关云存档（由显式注入的 [BaseNetworkClient] 驱动）与 [code]steam://<cloud_file>[/code] Steam Cloud 云存档（由 `GodotSteam` 动态反射驱动）；[br]
## 2. 当同时配置了 HTTP `remote_url` 与 `steam_cloud_file` 时，写入自动双写镜像备份，读取在 HTTP 远端不可用时自动降级回退至 Steam Cloud；[br]
## 3. [b]统一返回类型契约[/b]：`JSON` 模式统一返回解析后的 [Dictionary]/[Array]；`FILE` 模式统一返回 [PackedByteArray]。

const STEAM_SCHEME_PREFIX: String = "steam://"
const _STEAM_SINGLETON_NAME: String = "Steam"

var _network_service: BaseNetworkClient
var _temp_seq: int = 0


func _init(network_service: BaseNetworkClient = null) -> void:
	_network_service = network_service


func set_network_service(network_service: BaseNetworkClient) -> void:
	_network_service = network_service


#region Overrides
## 异步远端读取
func read(key: StringName, kwargs: Dictionary = {}) -> Result:
	return await read_async(key, kwargs)


## 异步远端写入
func write(key: StringName, data: Variant, kwargs: Dictionary = {}) -> Result:
	return await write_async(key, data, kwargs)


## 校验远端路由或 Steam Cloud 文件是否存在
func has(key: StringName) -> Result:
	var url := str(key).strip_edges()
	if url.begins_with(STEAM_SCHEME_PREFIX):
		var cloud_file := url.trim_prefix(STEAM_SCHEME_PREFIX).strip_edges()
		return _has_steam_cloud_file(cloud_file)
	return Result.ok(not url.is_empty())


## 拦截物理删除操作（云端数据防误删安全策略）
func delete(key: StringName) -> Result:
	return Result.err_ex(
		StorageError.REMOTE_DELETE_DISABLED,
		"Remote hard deletion is disabled by default for security reasons ('%s')." % String(key),
		{"url": String(key)},
		false,
		null,
		FrameworkError.CATEGORY_STATE
	)
#endregion


#region Async API
## 发起异步读请求（支持 `steam://` Steam Cloud、自建 HTTP 云存档，以及 HTTP 失败时向 Steam Cloud 自动降级回退）。[br]
## [b]kwargs 参数约束：[/b][br]
## - [code]payload_type[/code] (String): [code]"FILE"[/code] 或 [code]"JSON"[/code] (默认)；[br]
## - [code]steam_cloud_file[/code] (String): 可选的 Steam Cloud 远端文件名（用于双通道回退）；[br]
## - [code]save_path[/code] (String): 当 [code]payload_type == "FILE"[/code] 时落地保存路径（若为空则使用临时缓冲文件）；[br]
## - [code]use_backup[/code] (bool): 当指定了 `save_path` 时，覆盖前是否将旧文件备份为 `.bak`；[br]
## - [code]on_progress[/code] (Callable): 可选下载进度回调 `func(downloaded: int, total: int)`；[br]
## - [code]expected_md5[/code] (String): 可选文件完整性校验 MD5。
func read_async(key: StringName, kwargs: Dictionary = {}) -> Result:
	var url := str(key).strip_edges()
	var steam_cloud_file: String = str(kwargs.get("steam_cloud_file", "")).strip_edges()
	var payload_type: String = str(kwargs.get("payload_type", "JSON")).to_upper()

	# 1. 纯 Steam Cloud 协议路由 (steam://<cloud_file>)
	if url.begins_with(STEAM_SCHEME_PREFIX):
		var target_cloud_file := url.trim_prefix(STEAM_SCHEME_PREFIX).strip_edges()
		if target_cloud_file.is_empty():
			target_cloud_file = steam_cloud_file
		return _read_steam_cloud(target_cloud_file, payload_type)

	if url.is_empty():
		if not steam_cloud_file.is_empty():
			return _read_steam_cloud(steam_cloud_file, payload_type)
		return Result.err_ex(
			StorageError.INVALID_PARAM,
			"Remote read failed: remote_url is empty.",
			{},
			false,
			null,
			FrameworkError.CATEGORY_PARAM
		)

	# 2. HTTP(S) 远端读取（若失败且配置了 steam_cloud_file，自动降级尝试从 Steam Cloud 恢复）
	var http_res := await _read_http_async(url, payload_type, kwargs)
	if http_res.is_ok():
		return http_res

	if not steam_cloud_file.is_empty():
		var steam_res := _read_steam_cloud(steam_cloud_file, payload_type)
		if steam_res.is_ok():
			return steam_res

	return http_res


## 发起异步写请求（支持 `steam://` Steam Cloud、自建 HTTP 云存档，以及双通道同步写入）。
func write_async(key: StringName, data: Variant, kwargs: Dictionary = {}) -> Result:
	var url := str(key).strip_edges()
	var steam_cloud_file: String = str(kwargs.get("steam_cloud_file", "")).strip_edges()
	var payload_type: String = str(kwargs.get("payload_type", "JSON")).to_upper()

	# 1. 纯 Steam Cloud 协议路由 (steam://<cloud_file>)
	if url.begins_with(STEAM_SCHEME_PREFIX):
		var target_cloud_file := url.trim_prefix(STEAM_SCHEME_PREFIX).strip_edges()
		if target_cloud_file.is_empty():
			target_cloud_file = steam_cloud_file
		return _write_steam_cloud(target_cloud_file, data, payload_type)

	if url.is_empty():
		if not steam_cloud_file.is_empty():
			return _write_steam_cloud(steam_cloud_file, data, payload_type)
		return Result.err_ex(
			StorageError.INVALID_PARAM,
			"Remote write failed: remote_url is empty.",
			{},
			false,
			null,
			FrameworkError.CATEGORY_PARAM
		)

	# 2. 若同时启用了 Steam Cloud 镜像备份，先静默尝试写入 Steam RemoteStorage
	var steam_synced := false
	if not steam_cloud_file.is_empty():
		var steam_res := _write_steam_cloud(steam_cloud_file, data, payload_type)
		steam_synced = steam_res.is_ok()

	# 3. 执行自建 HTTP 后端云存档写入
	var http_res := await _write_http_async(url, data, payload_type, kwargs)
	if http_res.is_ok() or not steam_synced:
		return http_res
	# 若 HTTP 网关暂不可达但 Steam Cloud 已成功同步，返回成功以保障离线/单机模式平滑体验
	return Result.ok()
#endregion


#region Internal HTTP Transport
func _read_http_async(url: String, payload_type: String, kwargs: Dictionary) -> Result:
	if _network_service == null:
		return Result.err_ex(
			StorageError.REMOTE_UNAVAILABLE,
			"Remote read failed: NetworkClient is not available.",
			{"url": url},
			false,
			null,
			FrameworkError.CATEGORY_STATE
		)

	var custom_headers: PackedStringArray = kwargs.get("headers", PackedStringArray())
	var cancel_token: CancellationToken = kwargs.get("cancel_token", null)

	if payload_type == "FILE":
		var save_path: String = str(kwargs.get("save_path", "")).strip_edges()
		var is_temp_target := save_path.is_empty()
		if is_temp_target:
			_temp_seq += 1
			FileUtils.ensure_dir_exists(FileUtils.USER_STORAGE_TMP_DIR)
			save_path = "%s/remote_dl_%d_%d.tmp" % [FileUtils.USER_STORAGE_TMP_DIR, Time.get_ticks_msec(), _temp_seq]
		elif bool(kwargs.get("use_backup", true)) and FileUtils.file_exists(save_path) and FileUtils.get_file_size(save_path) > 0:
			FileUtils.copy_file(save_path, save_path + DiskStorageDriver.EXT_BAK)

		var on_progress: Callable = kwargs.get("on_progress", Callable())
		var expected_md5: String = str(kwargs.get("expected_md5", "")).strip_edges()

		var dl_res: Result
		if not expected_md5.is_empty():
			dl_res = await _network_service.download_file_with_md5(url, save_path, expected_md5, on_progress, custom_headers, cancel_token)
		else:
			dl_res = await _network_service.download_file(url, save_path, on_progress, custom_headers, cancel_token)

		if dl_res.is_err():
			if is_temp_target:
				FileUtils.remove_file(save_path)
			return dl_res

		var bytes_res := FileUtils.read_bytes(save_path)
		if is_temp_target:
			FileUtils.remove_file(save_path)
		return bytes_res

	var method: String = str(kwargs.get("method", "GET")).to_upper()
	var query_or_body: Dictionary = kwargs.get("params", {})
	if method == "POST":
		return await _network_service.post_request(url, query_or_body, custom_headers, cancel_token)
	return await _network_service.get_request(url, query_or_body, custom_headers, cancel_token)


func _write_http_async(url: String, data: Variant, payload_type: String, kwargs: Dictionary) -> Result:
	if _network_service == null:
		return Result.err_ex(
			StorageError.REMOTE_UNAVAILABLE,
			"Remote write failed: NetworkClient is not available.",
			{"url": url},
			false,
			null,
			FrameworkError.CATEGORY_STATE
		)

	var method: String = str(kwargs.get("method", "POST")).to_upper()
	var custom_headers: PackedStringArray = kwargs.get("headers", PackedStringArray())
	var cancel_token: CancellationToken = kwargs.get("cancel_token", null)

	if payload_type == "FILE":
		if not (data is PackedByteArray):
			return Result.err_ex(
				StorageError.INVALID_PARAM,
				"RemoteStorageDriver file upload expects data to be PackedByteArray.",
				{"url": url, "actual_type": type_string(typeof(data))},
				false,
				null,
				FrameworkError.CATEGORY_PARAM
			)

		var file_bytes := data as PackedByteArray
		var filename: String = str(kwargs.get("filename", "upload.bin"))
		var mime_type: String = str(kwargs.get("mime_type", "application/octet-stream"))
		return await _network_service.upload_file(url, "file", file_bytes, filename, mime_type, custom_headers, 15.0, cancel_token)

	var dict_payload: Dictionary = data as Dictionary if data is Dictionary else {"data": data}
	if method == "GET":
		return await _network_service.get_request(url, dict_payload, custom_headers, cancel_token)
	elif method == "PUT":
		return await _network_service.put_request(url, dict_payload, custom_headers, cancel_token)
	return await _network_service.post_request(url, dict_payload, custom_headers, cancel_token)
#endregion


#region Internal Steam Cloud (ISteamRemoteStorage) Bridge
## 检测当前运行时 Steam Cloud 是否可用且已开启
func is_steam_cloud_available() -> bool:
	return _get_steam_cloud_singleton() != null


func _get_steam_cloud_singleton() -> Object:
	if not Engine.has_singleton(_STEAM_SINGLETON_NAME):
		return null
	var steam: Object = Engine.get_singleton(_STEAM_SINGLETON_NAME)
	if steam == null:
		return null
	if steam.has_method("isSteamRunning") and not bool(steam.call("isSteamRunning")):
		return null
	if steam.has_method("isCloudEnabledForAccount") and not bool(steam.call("isCloudEnabledForAccount")):
		return null
	if steam.has_method("isCloudEnabledForApp") and not bool(steam.call("isCloudEnabledForApp")):
		return null
	return steam


func _has_steam_cloud_file(cloud_filename: String) -> Result:
	if cloud_filename.is_empty():
		return Result.ok(false)
	var steam := _get_steam_cloud_singleton()
	if steam == null or not steam.has_method("fileExists"):
		return Result.ok(false)
	return Result.ok(bool(steam.call("fileExists", cloud_filename)))


func _read_steam_cloud(cloud_filename: String, payload_type: String) -> Result:
	if cloud_filename.is_empty():
		return Result.err_ex(
			StorageError.INVALID_PARAM,
			"Steam Cloud read failed: cloud_filename is empty.",
			{},
			false,
			null,
			FrameworkError.CATEGORY_PARAM
		)

	var steam := _get_steam_cloud_singleton()
	if steam == null:
		return Result.err_ex(
			StorageError.REMOTE_UNAVAILABLE,
			"Steam Cloud is unavailable or disabled for '%s'." % cloud_filename,
			{"cloud_filename": cloud_filename},
			false,
			null,
			FrameworkError.CATEGORY_STATE
		)

	if steam.has_method("fileExists") and not bool(steam.call("fileExists", cloud_filename)):
		return Result.err_ex(
			StorageError.NOT_FOUND,
			"Steam Cloud file does not exist: '%s'." % cloud_filename,
			{"cloud_filename": cloud_filename},
			false,
			ERR_DOES_NOT_EXIST,
			FrameworkError.CATEGORY_NOT_FOUND
		)

	var file_size: int = 0
	if steam.has_method("getFileSize"):
		file_size = int(steam.call("getFileSize", cloud_filename))
	if file_size <= 0 or not steam.has_method("fileRead"):
		return Result.err_ex(
			StorageError.NOT_FOUND,
			"Steam Cloud file is empty or unreadable: '%s'." % cloud_filename,
			{"cloud_filename": cloud_filename, "file_size": file_size},
			false,
			ERR_DOES_NOT_EXIST,
			FrameworkError.CATEGORY_NOT_FOUND
		)

	var read_ret: Variant = steam.call("fileRead", cloud_filename, file_size)
	var raw_bytes := PackedByteArray()
	if read_ret is Dictionary:
		var ret_dict := read_ret as Dictionary
		if not bool(ret_dict.get("ret", false)):
			return Result.err_ex(
				StorageError.IO_ERROR,
				"Steam Cloud fileRead returned false for '%s'." % cloud_filename,
				{"cloud_filename": cloud_filename},
				true,
				ERR_FILE_CANT_READ,
				FrameworkError.CATEGORY_IO
			)
		var buf_var: Variant = ret_dict.get("buf", PackedByteArray())
		if buf_var is PackedByteArray:
			raw_bytes = buf_var
	elif read_ret is PackedByteArray:
		raw_bytes = read_ret

	if raw_bytes.is_empty():
		return Result.err_ex(
			StorageError.IO_ERROR,
			"Steam Cloud returned empty byte buffer for '%s'." % cloud_filename,
			{"cloud_filename": cloud_filename},
			false,
			ERR_FILE_CORRUPT,
			FrameworkError.CATEGORY_IO
		)

	if payload_type == "FILE":
		return Result.ok(raw_bytes)

	var json_text := raw_bytes.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(json_text)
	if parsed == null or (not (parsed is Dictionary) and not (parsed is Array)):
		return Result.err_ex(
			StorageError.PARSE_ERROR,
			"Steam Cloud JSON parse failed for '%s'." % cloud_filename,
			{"cloud_filename": cloud_filename},
			false,
			ERR_PARSE_ERROR,
			FrameworkError.CATEGORY_VALIDATION
		)
	return Result.ok(parsed)


func _write_steam_cloud(cloud_filename: String, data: Variant, payload_type: String) -> Result:
	if cloud_filename.is_empty():
		return Result.err_ex(
			StorageError.INVALID_PARAM,
			"Steam Cloud write failed: cloud_filename is empty.",
			{},
			false,
			null,
			FrameworkError.CATEGORY_PARAM
		)

	var steam := _get_steam_cloud_singleton()
	if steam == null or not steam.has_method("fileWrite"):
		return Result.err_ex(
			StorageError.REMOTE_UNAVAILABLE,
			"Steam Cloud is unavailable or disabled for '%s'." % cloud_filename,
			{"cloud_filename": cloud_filename},
			false,
			null,
			FrameworkError.CATEGORY_STATE
		)

	var raw_bytes := PackedByteArray()
	if payload_type == "FILE":
		if not (data is PackedByteArray):
			return Result.err_ex(
				StorageError.INVALID_PARAM,
				"Steam Cloud FILE write expects PackedByteArray.",
				{"cloud_filename": cloud_filename, "actual_type": type_string(typeof(data))},
				false,
				null,
				FrameworkError.CATEGORY_PARAM
			)
		raw_bytes = data as PackedByteArray
	else:
		var json_str := JSON.stringify(data, "\t")
		raw_bytes = json_str.to_utf8_buffer()

	var ok: bool = bool(steam.call("fileWrite", cloud_filename, raw_bytes, raw_bytes.size()))
	if not ok:
		return Result.err_ex(
			StorageError.IO_ERROR,
			"Steam Cloud fileWrite failed for '%s' (%d bytes)." % [cloud_filename, raw_bytes.size()],
			{"cloud_filename": cloud_filename, "size": raw_bytes.size()},
			true,
			ERR_FILE_CANT_WRITE,
			FrameworkError.CATEGORY_IO
		)
	return Result.ok()
#endregion
