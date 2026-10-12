class_name RequestQueue
extends RefCounted

## 网络请求队列与调度执行器（私有实现，仅供 [NetworkService] 使用）。[br]
## 维护空闲 [HTTPRequest] 节点池、超时控制、指数退避重试以及 Bearer Token 注入。

const RETRYABLE_RESULTS: Array[int] = [
	HTTPRequest.RESULT_CANT_CONNECT,
	HTTPRequest.RESULT_CANT_RESOLVE,
	HTTPRequest.RESULT_CONNECTION_ERROR,
	HTTPRequest.RESULT_TIMEOUT,
]

var _host: Node
var _free_pool: Array[HTTPRequest] = []


func _init(host: Node) -> void:
	_host = host


## 执行 [NetworkRequest]，支持失败重试与指数退避。必须 [code]await[/code]；返回 [Result]。
func execute(request: NetworkRequest, auth_token: String = "") -> Result:
	var last_res := Result.err("Request failed: unknown error.")
	var max_retries := request.max_retries
	var backoff_base := request.retry_backoff_base

	for attempt in range(max_retries + 1):
		var hr := _acquire_request()
		hr.timeout = request.timeout

		var headers := PackedStringArray(["Content-Type: application/json"])
		headers.append_array(request.headers)
		if not auth_token.is_empty():
			headers.append("Authorization: Bearer %s" % auth_token)

		var http_method := HTTPClient.METHOD_POST if request.method == "POST" else HTTPClient.METHOD_GET
		var body_json := JSON.stringify(request.body) if request.method == "POST" else ""
		var err := hr.request(request.url, headers, http_method, body_json)
		if err != OK:
			_release_request(hr)
			last_res = Result.err({"message": "Request failed: could not start (%d)." % err, "retryable": true})
		else:
			var response: Array = await hr.request_completed
			_release_request(hr)

			var result: int = response[0]
			var code: int = response[1]
			var raw_body: PackedByteArray = response[3]

			if result in RETRYABLE_RESULTS:
				last_res = Result.err({"message": "Request failed: network error (%d)." % result, "retryable": true})
			elif code >= 500:
				last_res = Result.err({"message": "Request failed: server error (%d)." % code, "retryable": true})
			elif code < 200 or code >= 300:
				last_res = Result.err({"message": "Request failed: HTTP %d." % code, "retryable": false})
			else:
				var parsed: Variant = JSON.parse_string(raw_body.get_string_from_utf8())
				return Result.ok(parsed if parsed != null else {})

		var retryable: bool = last_res.error is Dictionary and (last_res.error as Dictionary).get("retryable", false)
		if not retryable or attempt >= max_retries:
			break

		var tree := _host.get_tree()
		if tree != null:
			await tree.create_timer(backoff_base * pow(2, attempt)).timeout

	var msg: Variant = (last_res.error as Dictionary).get("message", last_res.error) if last_res.error is Dictionary else last_res.error
	return Result.err(msg)


func _acquire_request() -> HTTPRequest:
	if not _free_pool.is_empty():
		return _free_pool.pop_back()
	var hr := HTTPRequest.new()
	NodeUtils.mount_required(hr, _host, "HTTPRequest_%d" % _host.get_child_count())
	return hr


func _release_request(hr: HTTPRequest) -> void:
	_free_pool.append(hr)
