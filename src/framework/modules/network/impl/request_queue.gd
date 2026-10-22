class_name RequestQueue
extends RefCounted

## 网络请求有界并发队列与连接池调度器（私有实现，仅供 [NetworkClient] 使用）。[br]
##
## 核心职责：[br]
## 1. [b]有界并发与 FIFO 等待队列[/b]：限制同时飞行的 [HTTPRequest] 数量（默认 6），超出部分排队等待，空闲节点按容量上限（默认 8）池化复用或裁剪；[br]
## 2. [b]带随机抖动（Jitter）的指数退避重试[/b]：针对底层网络错误、超时、HTTP 408 / 429 / 5xx 自动阶梯退避重试，HTTP 4xx 立即失败；[br]
## 3. [b]零死锁协作式取消[/b]：解决 Godot [method HTTPRequest.cancel_request] 不触发 [signal HTTPRequest.request_completed] 的引擎限制，支持在排队期、请求期、退避期 0ms 响应 [CancellationToken] 与 [method dispose]；[br]
## 4. [b]401 鉴权并发合并刷新（Single-Flight Refresh）[/b]：收到 HTTP 401 时可调用外部刷新处理器，多并发请求共享单次刷新结果并透明重放一次。

signal _slot_changed
signal _inflight_changed
signal _auth_refresh_completed(refreshed: bool)

const RETRYABLE_RESULTS: Array[int] = [
	HTTPRequest.RESULT_CANT_CONNECT,
	HTTPRequest.RESULT_CANT_RESOLVE,
	HTTPRequest.RESULT_CONNECTION_ERROR,
	HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR,
	HTTPRequest.RESULT_REQUEST_FAILED,
	HTTPRequest.RESULT_TIMEOUT,
]

const RETRYABLE_STATUS_CODES: Array[int] = [
	408, ## Request Timeout
	429, ## Too Many Requests
]

#region Configuration & State
var max_concurrent_requests: int = 6
var max_pool_size: int = 8

var _host: Node
var _logger: BaseFrameworkLogger
var _free_pool: Array[HTTPRequest] = []
var _inflight_requests: Dictionary = {} ## int (req_id) -> HTTPRequest
var _wait_queue: Array[int] = []        ## FIFO ticket queue

var _active_count: int = 0
var _next_node_id: int = 0
var _next_ticket_id: int = 0
var _cancel_epoch: int = 0
var _disposed: bool = false
var _is_refreshing_auth: bool = false
var _last_auth_refresh_ok: bool = false

## 运行时统计指标
var _total_executed: int = 0
var _total_succeeded: int = 0
var _total_failed: int = 0
var _total_retried: int = 0
var _total_cancelled: int = 0
#endregion


#region Lifecycle
func _init(host: Node, logger: BaseFrameworkLogger = null) -> void:
	_host = host
	_logger = logger


func set_logger(logger: BaseFrameworkLogger) -> void:
	_logger = logger


## 取消当前所有排队中与飞行中的请求（队列本身保持可用）。
func cancel_all(reason: String = "All network requests cancelled.") -> void:
	_cancel_epoch += 1
	_wait_queue.clear()
	for req_id in _inflight_requests.keys():
		var hr: HTTPRequest = _inflight_requests[req_id]
		if is_instance_valid(hr):
			hr.cancel_request()
	_inflight_changed.emit()
	_slot_changed.emit()
	if _is_refreshing_auth:
		_auth_refresh_completed.emit(false)
	_log_info("Cancelled all active/queued requests: %s" % reason)


## 永久销毁队列并释放所有池化与飞行中的 HTTPRequest 节点。
func dispose() -> void:
	if _disposed:
		return
	_disposed = true
	_cancel_epoch += 1
	_wait_queue.clear()

	for req_id in _inflight_requests.keys():
		var hr: HTTPRequest = _inflight_requests[req_id]
		if is_instance_valid(hr):
			hr.cancel_request()
			NodeUtils.safe_free(hr)
	_inflight_requests.clear()
	_active_count = 0

	for hr in _free_pool:
		NodeUtils.safe_free(hr)
	_free_pool.clear()

	_inflight_changed.emit()
	_slot_changed.emit()
	if _is_refreshing_auth:
		_is_refreshing_auth = false
		_auth_refresh_completed.emit(false)


func get_diagnostics() -> Dictionary:
	return {
		"disposed": _disposed,
		"active_requests": _active_count,
		"queued_requests": _wait_queue.size(),
		"free_pool_size": _free_pool.size(),
		"max_concurrent": max_concurrent_requests,
		"max_pool_size": max_pool_size,
		"total_executed": _total_executed,
		"total_succeeded": _total_succeeded,
		"total_failed": _total_failed,
		"total_retried": _total_retried,
		"total_cancelled": _total_cancelled,
	}
#endregion


#region Core Execution Pipeline
## 执行 [NetworkRequest]，支持有界并发排队、指数退避重试、401 刷新重放与取消令牌。
func execute(
	request: NetworkRequest,
	base_url: String = "",
	auth_token_getter: Callable = Callable(),
	default_headers: Dictionary = {},
	unauthorized_handler: Callable = Callable(),
	auth_token_setter: Callable = Callable(),
	signing_secret: String = "",
	timestamp_ms_getter: Callable = Callable()
) -> Result:
	if _disposed or not is_instance_valid(_host):
		return Result.err_ex(
			NetworkError.CLIENT_DISPOSED,
			"Request aborted: NetworkClient is disposed.",
			{},
			false,
			null,
			FrameworkError.CATEGORY_STATE
		)

	if request == null:
		return Result.err_ex(
			NetworkError.INVALID_PARAM,
			"Request failed: NetworkRequest is null.",
			{},
			false,
			null,
			FrameworkError.CATEGORY_PARAM
		)

	var resolved_url := resolve_url(base_url, request.url, request.query_params)
	if resolved_url.is_empty() or not (resolved_url.begins_with("http://") or resolved_url.begins_with("https://")):
		return Result.err_ex(
			NetworkError.INVALID_URL,
			"Request failed: invalid or relative URL without base_url ('%s')." % request.url,
			{"url": request.url, "base_url": base_url},
			false,
			null,
			FrameworkError.CATEGORY_PARAM
		)

	var token := request.cancel_token
	if token != null and token.is_cancelled():
		_total_cancelled += 1
		return _make_cancelled_error(resolved_url, token.get_reason())

	var launch_epoch := _cancel_epoch

	# 1. 进入有界并发门控（超出并发上限时 FIFO 排队）
	var slot_acquired := await _acquire_slot(token, launch_epoch)
	if not slot_acquired:
		_total_cancelled += 1
		var reason := token.get_reason() if (token != null and token.is_cancelled()) else "Cancelled while waiting in request queue."
		return _make_cancelled_error(resolved_url, reason)

	_total_executed += 1
	var max_retries := maxi(0, request.max_retries)
	var backoff_base := maxf(0.05, request.retry_backoff_base)
	var auth_replayed := false
	var last_error_result: Result = null

	var attempt := 0
	while attempt <= max_retries:
		if _disposed or launch_epoch != _cancel_epoch or (token != null and token.is_cancelled()):
			_release_slot()
			_total_cancelled += 1
			var reason := token.get_reason() if (token != null and token.is_cancelled()) else "Request cancelled."
			return _make_cancelled_error(resolved_url, reason)

		var current_token_str: String = auth_token_getter.call() if auth_token_getter.is_valid() else ""
		var attempt_res := await _execute_single_attempt(
			request,
			resolved_url,
			current_token_str,
			default_headers,
			attempt,
			launch_epoch,
			signing_secret,
			timestamp_ms_getter
		)

		if attempt_res.is_ok():
			_release_slot()
			_total_succeeded += 1
			return attempt_res

		last_error_result = attempt_res
		var err_code := attempt_res.error_code()

		if err_code == NetworkError.CANCELLED:
			_release_slot()
			_total_cancelled += 1
			return attempt_res

		# 2. HTTP 401 鉴权失效：若配置了刷新拦截器且尚未重放过，先释放并发槽位防死锁，单飞刷新后再重新获取槽位重放
		if err_code == NetworkError.HTTP_UNAUTHORIZED and not auth_replayed and unauthorized_handler.is_valid():
			auth_replayed = true
			_release_slot()
			var refreshed := await _try_refresh_auth(unauthorized_handler, auth_token_setter, token, launch_epoch)
			if not refreshed:
				if _disposed or launch_epoch != _cancel_epoch or (token != null and token.is_cancelled()):
					_total_cancelled += 1
					var cancel_msg := token.get_reason() if (token != null and token.is_cancelled()) else "Cancelled during 401 token refresh."
					return _make_cancelled_error(resolved_url, cancel_msg)
				_total_failed += 1
				return last_error_result

			var reacquired := await _acquire_slot(token, launch_epoch)
			if not reacquired:
				_total_cancelled += 1
				var cancel_msg := token.get_reason() if (token != null and token.is_cancelled()) else "Cancelled while re-acquiring slot after 401 refresh."
				return _make_cancelled_error(resolved_url, cancel_msg)

			_log_info("Token refreshed on 401; replaying request: %s %s" % [request.method, resolved_url])
			continue

		# 3. 判定是否可重试
		if not attempt_res.is_retryable() or attempt >= max_retries:
			break

		attempt += 1
		_total_retried += 1
		var jitter := randf_range(0.85, 1.15)
		var delay_sec := backoff_base * pow(2.0, float(attempt - 1)) * jitter
		_log_warn(
			"Retrying request (%d/%d) after %.2fs: %s %s (%s)" % [
				attempt, max_retries, delay_sec, request.method, resolved_url, attempt_res.error_message()
			]
		)

		var sleep_ok := await _sleep_cancellable(delay_sec, token, launch_epoch)
		if not sleep_ok:
			_release_slot()
			_total_cancelled += 1
			var reason := token.get_reason() if (token != null and token.is_cancelled()) else "Cancelled during retry backoff."
			return _make_cancelled_error(resolved_url, reason)

	_release_slot()
	_total_failed += 1
	return last_error_result if last_error_result != null else Result.err_code(NetworkError.TRANSPORT_ERROR, "Request failed.")
#endregion


#region Single Attempt & Safe Cancellation
func _execute_single_attempt(
	request: NetworkRequest,
	resolved_url: String,
	auth_token: String,
	default_headers: Dictionary,
	attempt: int,
	launch_epoch: int,
	signing_secret: String = "",
	timestamp_ms_getter: Callable = Callable()
) -> Result:
	var hr := _acquire_node()
	if hr == null:
		return Result.err_ex(
			NetworkError.CLIENT_DISPOSED,
			"Cannot acquire HTTPRequest node: host is unavailable.",
			{"url": resolved_url},
			false,
			null,
			FrameworkError.CATEGORY_STATE
		)

	hr.timeout = maxf(0.0, request.timeout)
	var http_method := _map_http_method(request.method)
	var payload_str := _serialize_body(request.method, request.body)
	var has_body := not payload_str.is_empty() or request.method == "POST" or request.method == "PUT" or request.method == "PATCH"
	var attempt_custom_headers := request.headers.duplicate()
	var effective_secret := request.signing_secret if not request.signing_secret.is_empty() else signing_secret
	if request.sign_request and not effective_secret.is_empty():
		var ts_ms: int = int(timestamp_ms_getter.call()) if timestamp_ms_getter.is_valid() else -1
		var sig_res := CryptoUtils.sign_http_request(effective_secret, request.method, resolved_url, payload_str, ts_ms)
		if sig_res.is_ok():
			var sig_info: Dictionary = sig_res.value as Dictionary
			attempt_custom_headers.append("X-Timestamp: %s" % str(sig_info.get("timestamp", "")))
			attempt_custom_headers.append("X-Nonce: %s" % str(sig_info.get("nonce", "")))
			attempt_custom_headers.append("X-Content-SHA256: %s" % str(sig_info.get("content_sha256", "")))
			attempt_custom_headers.append("X-Signature: %s" % str(sig_info.get("signature", "")))

	var headers := build_headers(default_headers, attempt_custom_headers, auth_token, has_body)

	var req_id := _next_ticket_id
	_next_ticket_id += 1
	_inflight_requests[req_id] = hr

	var state := {
		"done": false,
		"cancelled": false,
		"response": [],
	}

	var on_completed := func(result: int, response_code: int, resp_headers: PackedStringArray, body: PackedByteArray) -> void:
		if state["done"]:
			return
		state["done"] = true
		state["response"] = [result, response_code, resp_headers, body]
		_inflight_changed.emit()

	hr.request_completed.connect(on_completed)

	var start_err := hr.request(resolved_url, headers, http_method, payload_str)
	if start_err != OK:
		if hr.request_completed.is_connected(on_completed):
			hr.request_completed.disconnect(on_completed)
		_inflight_requests.erase(req_id)
		_release_node(hr)
		return Result.err_ex(
			NetworkError.REQUEST_START_FAILED,
			"Failed to start HTTPRequest (err=%d) for '%s'." % [start_err, resolved_url],
			{"url": resolved_url, "method": request.method, "engine_error": start_err, "attempt": attempt},
			true,
			start_err,
			FrameworkError.CATEGORY_IO
		)

	var token := request.cancel_token
	var on_token_cancelled := Callable()
	if token != null:
		on_token_cancelled = func(_reason: String) -> void:
			if state["done"]:
				return
			state["done"] = true
			state["cancelled"] = true
			if is_instance_valid(hr):
				hr.cancel_request()
			_inflight_changed.emit()
		token.cancelled.connect(on_token_cancelled)

	while not state["done"] and not _disposed and launch_epoch == _cancel_epoch:
		if token != null and token.is_cancelled():
			state["cancelled"] = true
			if is_instance_valid(hr):
				hr.cancel_request()
			break
		await _inflight_changed

	if is_instance_valid(hr) and hr.request_completed.is_connected(on_completed):
		hr.request_completed.disconnect(on_completed)
	if token != null and on_token_cancelled.is_valid() and token.cancelled.is_connected(on_token_cancelled):
		token.cancelled.disconnect(on_token_cancelled)

	_inflight_requests.erase(req_id)

	if _disposed or launch_epoch != _cancel_epoch or state["cancelled"] or (token != null and token.is_cancelled()):
		if is_instance_valid(hr):
			hr.cancel_request()
			_release_node(hr)
		var reason := token.get_reason() if (token != null and token.is_cancelled()) else "Request cancelled."
		return _make_cancelled_error(resolved_url, reason)

	_release_node(hr)

	var response: Array = state["response"]
	var result_code: int = response[0]
	var status_code: int = response[1]
	var raw_body: PackedByteArray = response[3]
	var ctx := {
		"url": resolved_url,
		"method": request.method,
		"result_code": result_code,
		"status_code": status_code,
		"attempt": attempt,
	}

	# 1. 底层传输层错误判定
	if result_code != HTTPRequest.RESULT_SUCCESS:
		if result_code == HTTPRequest.RESULT_TIMEOUT:
			return Result.err_ex(
				NetworkError.TIMEOUT,
				"Request timed out after %.1fs: %s %s" % [request.timeout, request.method, resolved_url],
				ctx,
				true,
				result_code,
				FrameworkError.CATEGORY_TIMEOUT
			)
		var can_retry := result_code in RETRYABLE_RESULTS
		return Result.err_ex(
			NetworkError.TRANSPORT_ERROR,
			"Network transport error (%d) for %s %s." % [result_code, request.method, resolved_url],
			ctx,
			can_retry,
			result_code,
			FrameworkError.CATEGORY_IO
		)

	# 2. HTTP 状态码分类判定
	if status_code == 401:
		return Result.err_ex(
			NetworkError.HTTP_UNAUTHORIZED,
			"HTTP 401 Unauthorized for %s %s." % [request.method, resolved_url],
			ctx,
			false,
			status_code,
			FrameworkError.CATEGORY_STATE
		)

	if status_code == 429:
		return Result.err_ex(
			NetworkError.HTTP_RATE_LIMITED,
			"HTTP 429 Too Many Requests for %s %s." % [request.method, resolved_url],
			ctx,
			true,
			status_code,
			FrameworkError.CATEGORY_IO
		)

	if status_code == 408:
		return Result.err_ex(
			NetworkError.TIMEOUT,
			"HTTP 408 Request Timeout for %s %s." % [request.method, resolved_url],
			ctx,
			true,
			status_code,
			FrameworkError.CATEGORY_TIMEOUT
		)

	if status_code >= 500:
		return Result.err_ex(
			NetworkError.HTTP_SERVER_ERROR,
			"HTTP %d Server Error for %s %s." % [status_code, request.method, resolved_url],
			ctx,
			true,
			status_code,
			FrameworkError.CATEGORY_IO
		)

	if status_code < 200 or status_code >= 300:
		return Result.err_ex(
			NetworkError.HTTP_CLIENT_ERROR,
			"HTTP %d Client Error for %s %s." % [status_code, request.method, resolved_url],
			ctx,
			false,
			status_code,
			FrameworkError.CATEGORY_GENERAL
		)

	# 3. 2xx 响应体解析
	if raw_body.is_empty() or status_code == 204 or request.method == "HEAD":
		return Result.ok({} if request.expect_json else "")

	var text := raw_body.get_string_from_utf8()
	if not request.expect_json:
		return Result.ok(text)

	var stripped := text.strip_edges()
	if stripped.is_empty():
		return Result.ok({})

	var json := JSON.new()
	var parse_err := json.parse(stripped)
	if parse_err != OK:
		ctx["parse_line"] = json.get_error_line()
		ctx["parse_reason"] = json.get_error_message()
		return Result.err_ex(
			NetworkError.PARSE_ERROR,
			"Invalid JSON in 2xx response from '%s' (line %d: %s)." % [
				resolved_url, json.get_error_line(), json.get_error_message()
			],
			ctx,
			false,
			parse_err,
			FrameworkError.CATEGORY_VALIDATION
		)

	return Result.ok(json.data)
#endregion


#region URL & Header Builders
## 拼接 base_url、路径与 URL-Encoded Query 参数。
static func resolve_url(base_url: String, path_or_url: String, query_params: Dictionary = {}) -> String:
	var raw := path_or_url.strip_edges()
	if raw.is_empty():
		return ""

	var final_url := raw
	if not (raw.begins_with("http://") or raw.begins_with("https://")):
		var clean_base := base_url.strip_edges().trim_suffix("/")
		if clean_base.is_empty():
			return ""
		if raw.begins_with("/"):
			final_url = clean_base + raw
		else:
			final_url = clean_base + "/" + raw

	if not query_params.is_empty():
		var http_client := HTTPClient.new()
		var query_str := http_client.query_string_from_dict(query_params)
		if not query_str.is_empty():
			if final_url.contains("?"):
				if final_url.ends_with("?") or final_url.ends_with("&"):
					final_url += query_str
				else:
					final_url += "&" + query_str
			else:
				final_url += "?" + query_str

	return final_url


## 组装请求 Header，按优先级合并默认头、单次自定义头与 Bearer Token。
static func build_headers(
	default_headers: Dictionary,
	custom_headers: PackedStringArray,
	auth_token: String,
	include_json_content_type: bool = true
) -> PackedStringArray:
	var header_map: Dictionary = {}
	var key_case_map: Dictionary = {}

	if include_json_content_type:
		header_map["content-type"] = "application/json"
		key_case_map["content-type"] = "Content-Type"

	for k in default_headers.keys():
		var key_str := str(k).strip_edges()
		var val_str := str(default_headers[k]).strip_edges()
		if not key_str.is_empty() and not val_str.is_empty():
			var lower := key_str.to_lower()
			header_map[lower] = val_str
			key_case_map[lower] = key_str

	for line in custom_headers:
		var colon_idx := line.find(":")
		if colon_idx > 0:
			var k := line.substr(0, colon_idx).strip_edges()
			var v := line.substr(colon_idx + 1).strip_edges()
			var lower := k.to_lower()
			header_map[lower] = v
			key_case_map[lower] = k

	if not auth_token.is_empty() and not header_map.has("authorization"):
		header_map["authorization"] = "Bearer %s" % auth_token
		key_case_map["authorization"] = "Authorization"

	var result := PackedStringArray()
	for lower_key in header_map.keys():
		result.append("%s: %s" % [key_case_map[lower_key], header_map[lower_key]])
	return result
#endregion


#region Bounded Slot, Pool & Auth Refresh Helpers
func _acquire_slot(token: CancellationToken, launch_epoch: int) -> bool:
	if _disposed or launch_epoch != _cancel_epoch or (token != null and token.is_cancelled()):
		return false

	if _active_count < max_concurrent_requests and _wait_queue.is_empty():
		_active_count += 1
		return true

	var ticket := _next_ticket_id
	_next_ticket_id += 1
	_wait_queue.append(ticket)

	var on_token_cancel := Callable()
	if token != null:
		on_token_cancel = func(_reason: String) -> void:
			_wait_queue.erase(ticket)
			_slot_changed.emit()
		token.cancelled.connect(on_token_cancel)

	while not _disposed and launch_epoch == _cancel_epoch:
		if token != null and token.is_cancelled():
			break
		if _active_count < max_concurrent_requests and not _wait_queue.is_empty() and _wait_queue[0] == ticket:
			_wait_queue.pop_front()
			_active_count += 1
			if token != null and on_token_cancel.is_valid() and token.cancelled.is_connected(on_token_cancel):
				token.cancelled.disconnect(on_token_cancel)
			return true
		await _slot_changed

	_wait_queue.erase(ticket)
	if token != null and on_token_cancel.is_valid() and token.cancelled.is_connected(on_token_cancel):
		token.cancelled.disconnect(on_token_cancel)
	if not _disposed and _active_count < max_concurrent_requests and not _wait_queue.is_empty():
		_slot_changed.emit()
	return false


func _release_slot() -> void:
	_active_count = maxi(0, _active_count - 1)
	_slot_changed.emit()


func _acquire_node() -> HTTPRequest:
	while not _free_pool.is_empty():
		var candidate: HTTPRequest = _free_pool.pop_back()
		if is_instance_valid(candidate) and not candidate.is_queued_for_deletion():
			return candidate

	if _disposed or not is_instance_valid(_host):
		return null

	_next_node_id += 1
	var hr := HTTPRequest.new()
	NodeUtils.mount_required(hr, _host, "HTTPRequest_Pool_%d" % _next_node_id)
	return hr


func _release_node(hr: HTTPRequest) -> void:
	if not is_instance_valid(hr) or hr.is_queued_for_deletion():
		return
	if _disposed or not is_instance_valid(_host) or _free_pool.size() >= max_pool_size:
		NodeUtils.safe_free(hr)
		return
	hr.download_file = ""
	_free_pool.append(hr)


func _try_refresh_auth(
	handler: Callable,
	auth_token_setter: Callable,
	token: CancellationToken,
	launch_epoch: int
) -> bool:
	if _disposed or launch_epoch != _cancel_epoch or (token != null and token.is_cancelled()):
		return false

	if _is_refreshing_auth:
		var on_wait_cancel := Callable()
		if token != null:
			on_wait_cancel = func(_reason: String) -> void:
				_auth_refresh_completed.emit(_last_auth_refresh_ok)
			token.cancelled.connect(on_wait_cancel)
		while _is_refreshing_auth and not _disposed and launch_epoch == _cancel_epoch:
			if token != null and token.is_cancelled():
				break
			await _auth_refresh_completed
		if token != null and on_wait_cancel.is_valid() and token.cancelled.is_connected(on_wait_cancel):
			token.cancelled.disconnect(on_wait_cancel)
		if _disposed or launch_epoch != _cancel_epoch or (token != null and token.is_cancelled()):
			return false
		return _last_auth_refresh_ok

	_is_refreshing_auth = true
	_last_auth_refresh_ok = false
	var refresh_ok := false
	var res: Variant = await handler.call()
	if res is Result and (res as Result).is_ok():
		refresh_ok = true
		var new_tok: Variant = (res as Result).value
		if new_tok is String and not (new_tok as String).strip_edges().is_empty() and auth_token_setter.is_valid():
			auth_token_setter.call((new_tok as String).strip_edges())
	elif res is String and not (res as String).strip_edges().is_empty():
		refresh_ok = true
		if auth_token_setter.is_valid():
			auth_token_setter.call((res as String).strip_edges())
	elif res is bool and res:
		refresh_ok = true

	_last_auth_refresh_ok = refresh_ok
	_is_refreshing_auth = false
	_auth_refresh_completed.emit(refresh_ok)
	if _disposed or launch_epoch != _cancel_epoch or (token != null and token.is_cancelled()):
		return false
	return refresh_ok


func _sleep_cancellable(seconds: float, token: CancellationToken, launch_epoch: int) -> bool:
	if seconds <= 0.0:
		return true
	if _disposed or not is_instance_valid(_host):
		return false
	var tree: SceneTree = _host.get_tree() if _host.is_inside_tree() else (Engine.get_main_loop() as SceneTree)
	if tree == null:
		return false

	var start_msec := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - start_msec) / 1000.0 < seconds:
		if _disposed or launch_epoch != _cancel_epoch or not is_instance_valid(_host):
			return false
		if token != null and token.is_cancelled():
			return false
		await tree.process_frame
	return not _disposed and launch_epoch == _cancel_epoch and (token == null or not token.is_cancelled())


static func _map_http_method(method_str: String) -> HTTPClient.Method:
	match method_str.to_upper():
		"POST":
			return HTTPClient.METHOD_POST
		"PUT":
			return HTTPClient.METHOD_PUT
		"DELETE":
			return HTTPClient.METHOD_DELETE
		"PATCH":
			return HTTPClient.METHOD_PATCH
		"HEAD":
			return HTTPClient.METHOD_HEAD
		_:
			return HTTPClient.METHOD_GET


static func _serialize_body(method_str: String, body: Variant) -> String:
	var upper := method_str.to_upper()
	if upper == "GET" or upper == "HEAD":
		return ""
	if body == null:
		return ""
	if body is Dictionary:
		var d := body as Dictionary
		if d.is_empty():
			return "" if upper == "DELETE" else "{}"
		return JSON.stringify(d)
	if body is Array:
		return JSON.stringify(body)
	if body is String:
		return body as String
	return JSON.stringify(body)


static func _make_cancelled_error(url: String, reason: String) -> Result:
	return Result.err_ex(
		NetworkError.CANCELLED,
		"Request cancelled: %s" % (reason if not reason.is_empty() else "Operation cancelled."),
		{"url": url},
		false,
		null,
		FrameworkError.CATEGORY_CANCELLED
	)


func _log_info(msg: String) -> void:
	if _logger != null:
		_logger.info("Network", msg)


func _log_warn(msg: String) -> void:
	if _logger != null:
		_logger.warn("Network", msg)
#endregion
