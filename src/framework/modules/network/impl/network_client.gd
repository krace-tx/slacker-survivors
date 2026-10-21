class_name NetworkClient
extends BaseNetworkClient

## HTTP 网络通信客户端实现（对外门面为 [code]App.net[/code]）。[br]
##
## 核心职责：[br]
## 1. [b]配置与鉴权中心[/b]：管理 [code]base_url[/code]、全局默认 Header、Bearer Token 以及 401 鉴权刷新拦截器；[br]
## 2. [b]有界并发请求调度[/b]：委托 [RequestQueue] 执行 `GET`/`POST`/`PUT`/`DELETE` 请求，支持 URL Query 编码、带抖动指数退避重试与协作式取消；[br]
## 3. [b]事务级原子文件传输[/b]：支持 `multipart/form-data` 二进制上传，以及先写 `.tmp` 临时文件、校验 2xx 状态码与 MD5 完整性后再通过 [method FileUtils.rename_file] 原子落盘的流式下载；[br]
## 4. [b]优雅退出与取消守卫[/b]：响应 [method shutdown_async] 与 [method dispose]，退出时主动中止所有进行中的请求与传输并清理 `.tmp` 残卷。

signal _transfer_changed

#region Module Dependency Manifest
const MODULE_ID: StringName = &"net"
const REQUIRED_MODULES: Array[StringName] = []
const OPTIONAL_MODULES: Array[StringName] = [&"logger", &"env"]
#endregion

#region Configurable Budgets & Defaults
## 单次普通请求默认超时（秒）
var request_timeout: float = 5.0
## 网络层失败或 5xx 时的默认最大重试次数（不含首次）
var max_retries: int = 2
## 指数退避默认基数（秒）
var retry_backoff_base: float = 0.3
#endregion

#region Internal State
var _logger: BaseFrameworkLogger
var _env: BaseRuntimeEnvironment
var _queue: RequestQueue

var _base_url: String = ""
var _auth_token: String = ""
var _default_headers: Dictionary = {}
var _unauthorized_handler: Callable = Callable()

var _active_transfers: Dictionary = {} ## int (transfer_id) -> Dictionary {hr, timer, tmp_path}
var _next_transfer_id: int = 0
var _transfer_epoch: int = 0
var _disposed: bool = false
#endregion


#region Lifecycle
func _init(
	logger: BaseFrameworkLogger = null,
	env: BaseRuntimeEnvironment = null
) -> void:
	_logger = logger
	_env = env
	_queue = RequestQueue.new(self, _logger)


func initialize() -> Result:
	_disposed = false
	return Result.ok()


func shutdown_async() -> Result:
	cancel_all_requests("NetworkClient shutting down.")
	return Result.ok()


func dispose() -> void:
	if _disposed:
		return
	_disposed = true
	_abort_all_transfers("NetworkClient disposed.")
	if _queue != null:
		_queue.dispose()


func _exit_tree() -> void:
	dispose()


func set_logger(logger: BaseFrameworkLogger) -> void:
	_logger = logger
	if _queue != null:
		_queue.set_logger(logger)


func set_env(env: BaseRuntimeEnvironment) -> void:
	_env = env
#endregion


#region Configuration & Authentication
func set_base_url(base_url: String) -> void:
	_base_url = base_url.strip_edges().trim_suffix("/")


func get_base_url() -> String:
	return _base_url


func set_auth_token(token: String) -> void:
	_auth_token = token.strip_edges()


func get_auth_token() -> String:
	return _auth_token


func set_default_header(key: String, value: String) -> void:
	var clean_key := key.strip_edges()
	if clean_key.is_empty():
		return
	var clean_val := value.strip_edges()
	if clean_val.is_empty():
		_default_headers.erase(clean_key)
	else:
		_default_headers[clean_key] = clean_val


func remove_default_header(key: String) -> void:
	_default_headers.erase(key.strip_edges())


func clear_default_headers() -> void:
	_default_headers.clear()


func set_unauthorized_handler(handler: Callable) -> void:
	_unauthorized_handler = handler
#endregion


#region HTTP Requests
func send_request(request: NetworkRequest) -> Result:
	return await _queue.execute(
		request,
		_base_url,
		get_auth_token,
		_default_headers,
		_unauthorized_handler,
		set_auth_token
	)


func get_request(
	url: String,
	params: Dictionary = {},
	custom_headers: PackedStringArray = [],
	cancel_token: CancellationToken = null
) -> Result:
	var req := NetworkRequest.new(url, "GET", {}, custom_headers).with_query(params)
	req.timeout = request_timeout
	req.max_retries = max_retries
	req.retry_backoff_base = retry_backoff_base
	req.cancel_token = cancel_token
	return await send_request(req)


func post_request(
	url: String,
	body: Dictionary = {},
	custom_headers: PackedStringArray = [],
	cancel_token: CancellationToken = null
) -> Result:
	var req := NetworkRequest.new(url, "POST", body, custom_headers)
	req.timeout = request_timeout
	req.max_retries = max_retries
	req.retry_backoff_base = retry_backoff_base
	req.cancel_token = cancel_token
	return await send_request(req)


func put_request(
	url: String,
	body: Dictionary = {},
	custom_headers: PackedStringArray = [],
	cancel_token: CancellationToken = null
) -> Result:
	var req := NetworkRequest.new(url, "PUT", body, custom_headers)
	req.timeout = request_timeout
	req.max_retries = max_retries
	req.retry_backoff_base = retry_backoff_base
	req.cancel_token = cancel_token
	return await send_request(req)


func delete_request(
	url: String,
	params: Dictionary = {},
	custom_headers: PackedStringArray = [],
	cancel_token: CancellationToken = null
) -> Result:
	var req := NetworkRequest.new(url, "DELETE", {}, custom_headers).with_query(params)
	req.timeout = request_timeout
	req.max_retries = max_retries
	req.retry_backoff_base = retry_backoff_base
	req.cancel_token = cancel_token
	return await send_request(req)
#endregion


#region File Transfer (Upload & Atomic Download)
## POST multipart/form-data 单文件上传。
func upload_file(
	url: String,
	field_name: String,
	file_bytes: PackedByteArray,
	filename: String,
	mime_type: String,
	custom_headers: PackedStringArray = [],
	timeout_sec: float = 15.0,
	cancel_token: CancellationToken = null
) -> Result:
	if _disposed:
		return Result.err_ex(NetworkError.CLIENT_DISPOSED, "Upload aborted: NetworkClient is disposed.", {}, false, null, FrameworkError.CATEGORY_STATE)

	if file_bytes.is_empty():
		return Result.err_ex(NetworkError.INVALID_PARAM, "Upload failed: file_bytes cannot be empty.", {"url": url, "filename": filename}, false, null, FrameworkError.CATEGORY_PARAM)

	var resolved_url := RequestQueue.resolve_url(_base_url, url)
	if resolved_url.is_empty() or not (resolved_url.begins_with("http://") or resolved_url.begins_with("https://")):
		return Result.err_ex(NetworkError.INVALID_URL, "Upload failed: invalid URL '%s'." % url, {"url": url}, false, null, FrameworkError.CATEGORY_PARAM)

	if cancel_token != null and cancel_token.is_cancelled():
		return Result.err_ex(NetworkError.CANCELLED, "Upload cancelled before start: %s" % cancel_token.get_reason(), {"url": resolved_url}, false, null, FrameworkError.CATEGORY_CANCELLED)

	var safe_field := field_name.strip_edges() if not field_name.strip_edges().is_empty() else "file"
	var safe_filename := filename.strip_edges() if not filename.strip_edges().is_empty() else "upload.bin"
	var safe_mime := mime_type.strip_edges() if not mime_type.strip_edges().is_empty() else "application/octet-stream"

	var boundary := "----GodotFormBoundary%d_%d" % [Time.get_ticks_msec(), _next_transfer_id]
	var crlf := "\r\n"
	var body := PackedByteArray()
	var part_header := (
		"--%s%s"
		+ "Content-Disposition: form-data; name=\"%s\"; filename=\"%s\"%s"
		+ "Content-Type: %s%s%s"
	) % [boundary, crlf, safe_field, safe_filename, crlf, safe_mime, crlf, crlf]
	body.append_array(part_header.to_utf8_buffer())
	body.append_array(file_bytes)
	body.append_array(crlf.to_utf8_buffer())
	body.append_array(("--%s--%s" % [boundary, crlf]).to_utf8_buffer())

	var multipart_headers := PackedStringArray([
		"Content-Type: multipart/form-data; boundary=%s" % boundary,
		"Content-Length: %d" % body.size(),
	])
	multipart_headers.append_array(custom_headers)
	var headers := RequestQueue.build_headers(_default_headers, multipart_headers, _auth_token, false)

	_next_transfer_id += 1
	var transfer_id := _next_transfer_id
	var launch_epoch := _transfer_epoch

	var hr := HTTPRequest.new()
	hr.timeout = maxf(0.0, timeout_sec)
	NodeUtils.mount_required(hr, self, "HTTPUpload_%d" % transfer_id)
	_active_transfers[transfer_id] = {"hr": hr, "timer": null, "tmp_path": ""}

	var err := hr.request_raw(resolved_url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_cleanup_transfer(transfer_id, false)
		return Result.err_ex(
			NetworkError.REQUEST_START_FAILED,
			"Upload failed: could not start request (err=%d)." % err,
			{"url": resolved_url, "engine_error": err},
			true,
			err,
			FrameworkError.CATEGORY_IO
		)

	var wait_res := await _await_transfer(hr, cancel_token, launch_epoch)
	_cleanup_transfer(transfer_id, false)

	if wait_res["cancelled"]:
		var reason: String = wait_res["reason"]
		return Result.err_ex(NetworkError.CANCELLED, "Upload cancelled: %s" % reason, {"url": resolved_url}, false, null, FrameworkError.CATEGORY_CANCELLED)

	var response: Array = wait_res["response"]
	var result_code: int = response[0]
	var status_code: int = response[1]
	var resp_body: PackedByteArray = response[3]
	var ctx := {"url": resolved_url, "filename": safe_filename, "result_code": result_code, "status_code": status_code}

	if result_code != HTTPRequest.RESULT_SUCCESS:
		var code_str := NetworkError.TIMEOUT if result_code == HTTPRequest.RESULT_TIMEOUT else NetworkError.TRANSPORT_ERROR
		var cat := FrameworkError.CATEGORY_TIMEOUT if result_code == HTTPRequest.RESULT_TIMEOUT else FrameworkError.CATEGORY_IO
		return Result.err_ex(code_str, "Upload failed: transport error %d (HTTP %d)." % [result_code, status_code], ctx, true, result_code, cat)

	if status_code < 200 or status_code >= 300:
		var http_err_code := _classify_http_error(status_code)
		return Result.err_ex(http_err_code, "Upload failed: HTTP %d." % status_code, ctx, status_code >= 500 or status_code == 429, status_code, FrameworkError.CATEGORY_IO)

	if resp_body.is_empty() or status_code == 204:
		return Result.ok({})

	var text := resp_body.get_string_from_utf8().strip_edges()
	if text.is_empty():
		return Result.ok({})

	var json := JSON.new()
	if json.parse(text) != OK:
		return Result.err_ex(NetworkError.PARSE_ERROR, "Upload succeeded (HTTP %d) but response is not valid JSON." % status_code, ctx, false, null, FrameworkError.CATEGORY_VALIDATION)

	return Result.ok(json.data)


## 异步流式下载文件，采用 .tmp 临时文件落盘并在校验通过后原子重命名至 save_path。
func download_file(
	url: String,
	save_path: String,
	on_progress: Callable = Callable(),
	custom_headers: PackedStringArray = [],
	cancel_token: CancellationToken = null
) -> Result:
	return await _download_file_internal(url, save_path, "", on_progress, custom_headers, cancel_token)


## 异步流式下载文件，在 .tmp 临时文件上校验 MD5 通过后才原子替换至 save_path。
func download_file_with_md5(
	url: String,
	save_path: String,
	expected_md5: String,
	on_progress: Callable = Callable(),
	custom_headers: PackedStringArray = [],
	cancel_token: CancellationToken = null
) -> Result:
	if expected_md5.strip_edges().is_empty():
		return Result.err_ex(
			NetworkError.INVALID_PARAM,
			"Download with MD5 failed: expected_md5 cannot be empty.",
			{"url": url, "save_path": save_path},
			false,
			null,
			FrameworkError.CATEGORY_PARAM
		)
	return await _download_file_internal(url, save_path, expected_md5.strip_edges(), on_progress, custom_headers, cancel_token)
#endregion


#region Diagnostics & Cancellation
func cancel_all_requests(reason: String = "All network requests cancelled.") -> void:
	_abort_all_transfers(reason)
	if _queue != null:
		_queue.cancel_all(reason)


func get_diagnostics() -> Dictionary:
	var queue_diag := _queue.get_diagnostics() if _queue != null else {}
	return {
		"base_url": _base_url,
		"has_auth_token": not _auth_token.is_empty(),
		"default_header_count": _default_headers.size(),
		"has_unauthorized_handler": _unauthorized_handler.is_valid(),
		"active_transfers": _active_transfers.size(),
		"queue": queue_diag,
	}
#endregion


#region Internal Atomic Download & Transfer Helpers
func _download_file_internal(
	url: String,
	save_path: String,
	expected_md5: String,
	on_progress: Callable,
	custom_headers: PackedStringArray,
	cancel_token: CancellationToken
) -> Result:
	if _disposed:
		return Result.err_ex(NetworkError.CLIENT_DISPOSED, "Download aborted: NetworkClient is disposed.", {}, false, null, FrameworkError.CATEGORY_STATE)

	var clean_save_path := save_path.strip_edges()
	if clean_save_path.is_empty():
		return Result.err_ex(NetworkError.INVALID_PARAM, "Download failed: save_path cannot be empty.", {"url": url}, false, null, FrameworkError.CATEGORY_PARAM)

	var resolved_url := RequestQueue.resolve_url(_base_url, url)
	if resolved_url.is_empty() or not (resolved_url.begins_with("http://") or resolved_url.begins_with("https://")):
		return Result.err_ex(NetworkError.INVALID_URL, "Download failed: invalid URL '%s'." % url, {"url": url, "save_path": clean_save_path}, false, null, FrameworkError.CATEGORY_PARAM)

	if cancel_token != null and cancel_token.is_cancelled():
		return Result.err_ex(NetworkError.CANCELLED, "Download cancelled before start: %s" % cancel_token.get_reason(), {"url": resolved_url, "save_path": clean_save_path}, false, null, FrameworkError.CATEGORY_CANCELLED)

	# 1. 确保父目录存在并校验写权限
	var dir_res := FileUtils.ensure_dir_exists(clean_save_path.get_base_dir())
	if dir_res.is_err():
		return Result.err_ex(
			NetworkError.IO_ERROR,
			"Download failed: cannot create parent directory for '%s' (%s)." % [clean_save_path, dir_res.error_message()],
			{"url": resolved_url, "save_path": clean_save_path},
			false,
			dir_res.error,
			FrameworkError.CATEGORY_IO
		)

	_next_transfer_id += 1
	var transfer_id := _next_transfer_id
	var launch_epoch := _transfer_epoch
	var tmp_path := "%s.%d%s" % [clean_save_path, transfer_id, FileUtils.TMP_SUFFIX]

	var hr := HTTPRequest.new()
	hr.timeout = 0.0
	hr.use_threads = true
	hr.download_file = tmp_path
	NodeUtils.mount_required(hr, self, "HTTPDownload_%d" % transfer_id)

	var headers := RequestQueue.build_headers(_default_headers, custom_headers, _auth_token, false)

	var timer: Timer = null
	if on_progress.is_valid():
		timer = Timer.new()
		timer.wait_time = 0.2
		timer.autostart = true
		timer.one_shot = false
		NodeUtils.mount_required(timer, self, "HTTPDownloadTimer_%d" % transfer_id)
		timer.timeout.connect(func() -> void:
			if is_instance_valid(hr) and on_progress.is_valid():
				on_progress.call(hr.get_downloaded_bytes(), hr.get_body_size())
		)

	_active_transfers[transfer_id] = {"hr": hr, "timer": timer, "tmp_path": tmp_path}

	var start_err := hr.request(resolved_url, headers, HTTPClient.METHOD_GET)
	if start_err != OK:
		_cleanup_transfer(transfer_id, true)
		return Result.err_ex(
			NetworkError.REQUEST_START_FAILED,
			"Download failed: could not start HTTPRequest (err=%d)." % start_err,
			{"url": resolved_url, "save_path": clean_save_path, "engine_error": start_err},
			true,
			start_err,
			FrameworkError.CATEGORY_IO
		)

	var wait_res := await _await_transfer(hr, cancel_token, launch_epoch)

	var final_downloaded := hr.get_downloaded_bytes() if is_instance_valid(hr) else 0
	var final_total := hr.get_body_size() if is_instance_valid(hr) else 0

	# 先释放 HTTPRequest 与 Timer（确保底层关闭 tmp_path 文件句柄后再执行删除或重命名）
	_cleanup_transfer(transfer_id, false)

	if wait_res["cancelled"]:
		FileUtils.remove_file(tmp_path)
		var reason: String = wait_res["reason"]
		return Result.err_ex(
			NetworkError.CANCELLED,
			"Download cancelled: %s" % reason,
			{"url": resolved_url, "save_path": clean_save_path},
			false,
			null,
			FrameworkError.CATEGORY_CANCELLED
		)

	var response: Array = wait_res["response"]
	var result_code: int = response[0]
	var status_code: int = response[1]
	var ctx := {"url": resolved_url, "save_path": clean_save_path, "result_code": result_code, "status_code": status_code}

	if result_code != HTTPRequest.RESULT_SUCCESS:
		FileUtils.remove_file(tmp_path)
		var code_str := NetworkError.TIMEOUT if result_code == HTTPRequest.RESULT_TIMEOUT else NetworkError.TRANSPORT_ERROR
		var cat := FrameworkError.CATEGORY_TIMEOUT if result_code == HTTPRequest.RESULT_TIMEOUT else FrameworkError.CATEGORY_IO
		return Result.err_ex(
			code_str,
			"Download failed: transport error %d (HTTP %d)." % [result_code, status_code],
			ctx,
			true,
			result_code,
			cat
		)

	if status_code < 200 or status_code >= 300:
		FileUtils.remove_file(tmp_path)
		var http_err_code := _classify_http_error(status_code)
		return Result.err_ex(
			http_err_code,
			"Download failed: HTTP %d for '%s'." % [status_code, resolved_url],
			ctx,
			status_code >= 500 or status_code == 429,
			status_code,
			FrameworkError.CATEGORY_IO
		)

	# 补发 100% 完成进度回调，避免短时下载结束时 UI 进度停留在中间值
	if on_progress.is_valid():
		if final_downloaded <= 0:
			final_downloaded = maxi(0, FileUtils.get_file_size(tmp_path))
		on_progress.call(final_downloaded, maxi(final_downloaded, final_total))

	# 2. 若要求 MD5 校验，在提升为正式文件前直接对 .tmp 文件校验，保护原文件不被破坏
	if not expected_md5.is_empty():
		var md5_res := FileUtils.verify_md5(tmp_path, expected_md5)
		if md5_res.is_err():
			FileUtils.remove_file(tmp_path)
			return Result.err_ex(
				NetworkError.HASH_MISMATCH,
				"Download MD5 mismatch for '%s': %s" % [clean_save_path, md5_res.error_message()],
				{"url": resolved_url, "save_path": clean_save_path, "expected_md5": expected_md5},
				true,
				md5_res.error,
				FrameworkError.CATEGORY_VALIDATION
			)

	# 3. 事务级原子重命名（带 Windows Swap 备份回滚保护）
	var rename_res := FileUtils.rename_file(tmp_path, clean_save_path)
	if rename_res.is_err():
		FileUtils.remove_file(tmp_path)
		return Result.err_ex(
			NetworkError.IO_ERROR,
			"Download failed: atomic rename from '%s' to '%s' failed (%s)." % [
				tmp_path, clean_save_path, rename_res.error_message()
			],
			ctx,
			false,
			rename_res.error,
			FrameworkError.CATEGORY_IO
		)

	return Result.ok(clean_save_path)


func _await_transfer(hr: HTTPRequest, cancel_token: CancellationToken, launch_epoch: int) -> Dictionary:
	var state := {
		"done": false,
		"cancelled": false,
		"reason": "",
		"response": [],
	}

	var on_completed := func(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
		if state["done"]:
			return
		state["done"] = true
		state["response"] = [result, response_code, headers, body]
		_transfer_changed.emit()

	hr.request_completed.connect(on_completed)

	var on_token_cancelled := Callable()
	if cancel_token != null:
		on_token_cancelled = func(reason: String) -> void:
			if state["done"]:
				return
			state["done"] = true
			state["cancelled"] = true
			state["reason"] = reason
			if is_instance_valid(hr):
				hr.cancel_request()
			_transfer_changed.emit()
		cancel_token.cancelled.connect(on_token_cancelled)

	while not state["done"] and not _disposed and launch_epoch == _transfer_epoch:
		if cancel_token != null and cancel_token.is_cancelled():
			state["cancelled"] = true
			state["reason"] = cancel_token.get_reason()
			if is_instance_valid(hr):
				hr.cancel_request()
			break
		await _transfer_changed

	if is_instance_valid(hr) and hr.request_completed.is_connected(on_completed):
		hr.request_completed.disconnect(on_completed)
	if cancel_token != null and on_token_cancelled.is_valid() and cancel_token.cancelled.is_connected(on_token_cancelled):
		cancel_token.cancelled.disconnect(on_token_cancelled)

	if _disposed or launch_epoch != _transfer_epoch:
		state["cancelled"] = true
		if state["reason"].is_empty():
			state["reason"] = "Transfer aborted by client cancellation or shutdown."

	return state


func _cleanup_transfer(transfer_id: int, remove_tmp: bool) -> void:
	if not _active_transfers.has(transfer_id):
		return
	var entry: Dictionary = _active_transfers[transfer_id]
	_active_transfers.erase(transfer_id)

	var timer: Variant = entry.get("timer")
	if is_instance_valid(timer):
		(timer as Timer).stop()
		NodeUtils.safe_free(timer)

	var hr: Variant = entry.get("hr")
	if is_instance_valid(hr):
		(hr as HTTPRequest).cancel_request()
		(hr as HTTPRequest).download_file = ""
		NodeUtils.safe_free(hr)

	var tmp_path: String = entry.get("tmp_path", "")
	if remove_tmp and not tmp_path.is_empty():
		FileUtils.remove_file(tmp_path)


func _abort_all_transfers(reason: String) -> void:
	_transfer_epoch += 1
	var ids := _active_transfers.keys()
	for transfer_id in ids:
		_cleanup_transfer(transfer_id, true)
	_transfer_changed.emit()
	if _logger != null and not ids.is_empty():
		_logger.info("Network", "Aborted %d active file transfers: %s" % [ids.size(), reason])


static func _classify_http_error(status_code: int) -> String:
	if status_code == 401:
		return NetworkError.HTTP_UNAUTHORIZED
	if status_code == 429:
		return NetworkError.HTTP_RATE_LIMITED
	if status_code == 408:
		return NetworkError.TIMEOUT
	if status_code >= 500:
		return NetworkError.HTTP_SERVER_ERROR
	return NetworkError.HTTP_CLIENT_ERROR
#endregion
