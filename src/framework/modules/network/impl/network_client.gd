class_name NetworkClient
extends BaseNetworkClient

## HTTP 传输客户端：请求队列、超时、指数退避重试、鉴权头；统一返回 [Result]。
## 调用方必须 [code]await[/code]；[param url] 传完整地址，环境差异由业务配置。
## 网络层失败或 5xx 才重试；4xx 立即失败。
##
## 请求载荷封装见 [NetworkRequest]，执行队列与重试调度见 [RequestQueue]。

#region State
## 单次请求超时（秒）。
var request_timeout: float = 5.0
## 网络层失败时的最大重试次数（不含首次）。
var max_retries: int = 2
## 退避基数（秒）：第 N 次重试等待 [code]base * 2^(N-1)[/code]。
var retry_backoff_base: float = 0.3

var _auth_token: String = ""
var _queue: RequestQueue
#endregion

#region Lifecycle
func _init() -> void:
	_queue = RequestQueue.new(self)


func initialize() -> Result:
	return Result.ok()
#endregion

#region Public API
## 设置鉴权 Token；后续请求自动带 [code]Authorization: Bearer[/code]。
func set_auth_token(token: String) -> void:
	_auth_token = token


## GET。[param url] 为完整地址。
func get_request(url: String, params: Dictionary = {}) -> Result:
	var req := NetworkRequest.new(url, "GET", params)
	req.timeout = request_timeout
	req.max_retries = max_retries
	req.retry_backoff_base = retry_backoff_base
	return await _queue.execute(req, _auth_token)


## POST。[param url] 为完整地址。
func post_request(url: String, body: Dictionary = {}) -> Result:
	var req := NetworkRequest.new(url, "POST", body)
	req.timeout = request_timeout
	req.max_retries = max_retries
	req.retry_backoff_base = retry_backoff_base
	return await _queue.execute(req, _auth_token)


## POST multipart 单文件上传。[param url] 为完整地址。成功 value 为 JSON 或空 Dictionary。
func upload_file(url: String, field_name: String, file_bytes: PackedByteArray, filename: String, mime_type: String, custom_headers: PackedStringArray = [], timeout_sec: float = 15.0) -> Result:
	if file_bytes.is_empty():
		return Result.err("Upload failed: file bytes are empty.")

	var boundary := "----GodotFormBoundary%d" % Time.get_ticks_msec()
	var crlf := "\r\n"
	var body := PackedByteArray()
	var header := (
		"--%s%s"
		+ "Content-Disposition: form-data; name=\"%s\"; filename=\"%s\"%s"
		+ "Content-Type: %s%s%s"
	) % [boundary, crlf, field_name, filename, crlf, mime_type, crlf, crlf]
	body.append_array(header.to_utf8_buffer())
	body.append_array(file_bytes)
	body.append_array(crlf.to_utf8_buffer())
	body.append_array(("--%s--%s" % [boundary, crlf]).to_utf8_buffer())

	var headers := PackedStringArray([
		"Content-Type: multipart/form-data; boundary=%s" % boundary,
		"Content-Length: %d" % body.size(),
	])
	headers.append_array(custom_headers)
	if not _auth_token.is_empty():
		headers.append("Authorization: Bearer %s" % _auth_token)

	var hr := HTTPRequest.new()
	hr.timeout = timeout_sec
	NodeUtils.mount_required(hr, self, "HTTPUpload_%d" % get_child_count())

	var err := hr.request_raw(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		hr.queue_free()
		return Result.err("Upload failed: could not start request (%d)." % err)

	var response: Array = await hr.request_completed
	hr.queue_free()

	var result_code: int = response[0]
	var status_code: int = response[1]
	var resp_body: PackedByteArray = response[3]

	if result_code != HTTPRequest.RESULT_SUCCESS:
		return Result.err("Upload failed: transport error %d (HTTP %d)." % [result_code, status_code])

	var parsed: Variant = JSON.parse_string(resp_body.get_string_from_utf8())
	if status_code < 200 or status_code >= 300:
		return Result.err("Upload failed: HTTP %d." % status_code)

	return Result.ok(parsed if parsed != null else {})


## 下载到本地。[param url] 为完整地址。[param on_progress] 可选 [code](downloaded, total)[/code]。成功 value 为 [param save_path]。
func download_file(url: String, save_path: String, on_progress: Callable = Callable(), custom_headers: PackedStringArray = []) -> Result:
	var hr := HTTPRequest.new()
	hr.timeout = 0
	hr.use_threads = true
	hr.download_file = save_path
	NodeUtils.mount_required(hr, self, "HTTPDownload_%d" % get_child_count())

	var headers := PackedStringArray(["Content-Type: application/json"])
	headers.append_array(custom_headers)

	var err := hr.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		hr.queue_free()
		return Result.err("Download failed: could not start request (%d)." % err)

	var timer: Timer = null
	if on_progress.is_valid():
		timer = Timer.new()
		timer.wait_time = 0.2
		timer.autostart = true
		timer.one_shot = false
		NodeUtils.mount_required(timer, self, "HTTPDownloadTimer_%d" % get_child_count())
		timer.timeout.connect(func():
			if is_instance_valid(hr):
				on_progress.call(
					hr.get_downloaded_bytes(),
					hr.get_body_size()
				)
		)

	var response: Array = await hr.request_completed

	if is_instance_valid(timer):
		timer.stop()
		timer.queue_free()
	if is_instance_valid(hr):
		hr.queue_free()

	var result_code: int = response[0]
	var status_code: int = response[1]

	if result_code != HTTPRequest.RESULT_SUCCESS:
		return Result.err("Download failed: transport error %d (HTTP %d)." % [result_code, status_code])

	if status_code < 200 or status_code >= 300:
		return Result.err("Download failed: HTTP %d." % status_code)

	return Result.ok(save_path)


## 下载后校验 MD5；不匹配则删文件并失败。
func download_file_with_md5(url: String, save_path: String, expected_md5: String) -> Result:
	if url.is_empty() or expected_md5.is_empty():
		return Result.err("Download failed: url or md5 is empty.")

	var save_dir := save_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(save_dir):
		if DirAccess.make_dir_recursive_absolute(save_dir) != OK:
			return Result.err("Download failed: could not create directory '%s'." % save_dir)

	var res := await download_file(url, save_path)
	if res.is_err():
		return res

	if not FileAccess.file_exists(save_path):
		return Result.err("Download failed: file missing at '%s'." % save_path)

	var file_md5 := FileAccess.get_md5(save_path)
	if file_md5 != expected_md5:
		DirAccess.remove_absolute(save_path)
		return Result.err("Download failed: md5 mismatch (expected %s, got %s)." % [expected_md5, file_md5])

	return Result.ok(save_path)
#endregion
