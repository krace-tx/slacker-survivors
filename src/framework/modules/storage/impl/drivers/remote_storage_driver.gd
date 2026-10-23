class_name RemoteStorageDriver
extends StorageDriver

## 远端存储驱动：封装核心 HTTP 云存档与文件流传输操作。[br]
##
## 核心职责：[br]
## 1. 根据上层透传的 [param kwargs]（尤其是 [code]payload_type[/code]）决定走 JSON 请求还是二进制文件上传/下载；[br]
## 2. [b]统一返回类型契约[/b]：`JSON` 模式统一返回解析后的 [Dictionary]/[Array]；`FILE` 模式在流式原子下载落盘后统一返回 [PackedByteArray]，
##    彻底消除 `Tier.REMOTE`（原返回路径 String）与 `Tier.DISK`（返回 PackedByteArray）之间的返回类型分裂问题；[br]
## 3. 所有底层网络交互由显式注入的 [BaseNetworkClient] 提供支持，绝不依赖全局单例。

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


## 校验 URL 不为空
func has(key: StringName) -> Result:
	var url := str(key).strip_edges()
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
## 发起异步读请求（下载文件返回 [PackedByteArray] 或 GET/POST JSON 返回 [Dictionary]/[Array]）。[br]
## [b]kwargs 参数约束：[/b][br]
## - [code]payload_type[/code] (String): [code]"FILE"[/code] 或 [code]"JSON"[/code] (默认)；[br]
## - [code]save_path[/code] (String): 当 [code]payload_type == "FILE"[/code] 时落地保存路径（若为空则使用临时缓冲文件）；[br]
## - [code]use_backup[/code] (bool): 当指定了 `save_path` 时，覆盖前是否将旧文件备份为 `.bak`；[br]
## - [code]on_progress[/code] (Callable): 可选下载进度回调 `func(downloaded: int, total: int)`；[br]
## - [code]expected_md5[/code] (String): 可选文件完整性校验 MD5。
func read_async(key: StringName, kwargs: Dictionary = {}) -> Result:
	if _network_service == null:
		return Result.err_ex(
			StorageError.REMOTE_UNAVAILABLE,
			"Remote read failed: NetworkClient is not available.",
			{"url": String(key)},
			false,
			null,
			FrameworkError.CATEGORY_STATE
		)

	var url := str(key).strip_edges()
	if url.is_empty():
		return Result.err_ex(
			StorageError.INVALID_PARAM,
			"Remote read failed: remote_url is empty.",
			{},
			false,
			null,
			FrameworkError.CATEGORY_PARAM
		)

	var payload_type: String = str(kwargs.get("payload_type", "JSON")).to_upper()
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


## 发起异步写请求（上传文件 或 POST/PUT/GET JSON）。
func write_async(key: StringName, data: Variant, kwargs: Dictionary = {}) -> Result:
	if _network_service == null:
		return Result.err_ex(
			StorageError.REMOTE_UNAVAILABLE,
			"Remote write failed: NetworkClient is not available.",
			{"url": String(key)},
			false,
			null,
			FrameworkError.CATEGORY_STATE
		)

	var url := str(key).strip_edges()
	if url.is_empty():
		return Result.err_ex(
			StorageError.INVALID_PARAM,
			"Remote write failed: remote_url is empty.",
			{},
			false,
			null,
			FrameworkError.CATEGORY_PARAM
		)

	var method: String = str(kwargs.get("method", "POST")).to_upper()
	var payload_type: String = str(kwargs.get("payload_type", "JSON")).to_upper()
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
