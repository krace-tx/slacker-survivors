class_name NetworkRequest
extends RefCounted

## 网络请求配置对象（公开数据契约）。[br]
##
## 描述单次 HTTP 请求的目标地址、HTTP 方法、Query 参数、消息体、自定义请求头、
## 超时与指数退避重试策略，以及协作式取消令牌（[CancellationToken]）。

## 目标 URL（支持完整 [code]http(s)://[/code] 地址，或配合 [method BaseNetworkClient.set_base_url] 使用的相对路径）
var url: String = ""

## HTTP 请求方法（支持 [code]"GET"[/code]、[code]"POST"[/code]、[code]"PUT"[/code]、[code]"DELETE"[/code]、[code]"PATCH"[/code]、[code]"HEAD"[/code]）
var method: String = "GET"

## URL 查询参数字典（系统自动进行 URL-Encoding 并安全拼接至 URL [code]?key=value[/code]）
var query_params: Dictionary = {}

## 请求体数据（用于 [code]POST[/code]/[code]PUT[/code]/[code]PATCH[/code] 等携带消息体的请求）
var body: Variant = {}

## 单次请求附加的自定义 HTTP Header 数组（如 [code]["X-Request-Id: xxx"][/code]）
var headers: PackedStringArray = []

## 单次尝试超时上限（秒，[code]<= 0.0[/code] 表示不限时）
var timeout: float = 5.0

## 网络波动、超时、429 限流或 5xx 错误时的最大自动重试次数（不含首次请求，[code]0[/code] 表示不重试）
var max_retries: int = 2

## 指数退避基数（秒）：第 N 次重试等待 [code]base * 2^(N-1) * jitter[/code]
var retry_backoff_base: float = 0.3

## 是否将 2xx 非空响应体按 JSON 解析（设为 [code]false[/code] 时直接返回 UTF-8 原始文本字符串）
var expect_json: bool = true

## 可选的协作式取消令牌（绑定 [TaskScope] 后可在场景/UI 退出时自动中止请求与退避等待）
var cancel_token: CancellationToken = null

## 是否启用 HMAC-SHA256 请求防篡改签名（默认 [code]true[/code]，当客户端配置了全局签名密钥或单次 [member signing_secret] 时生效）
var sign_request: bool = true

## 单次请求专属的 HMAC-SHA256 签名密钥（为空时自动沿用 [method BaseNetworkClient.set_request_signing] 设置的全局密钥）
var signing_secret: String = ""


func _init(
	p_url: String = "",
	p_method: String = "GET",
	p_body: Variant = {},
	p_headers: PackedStringArray = []
) -> void:
	url = p_url.strip_edges()
	method = p_method.strip_edges().to_upper()
	if method.is_empty():
		method = "GET"
	body = p_body
	headers = p_headers.duplicate()


#region Fluent Builders
## 链式设置 URL 查询参数字典。
func with_query(p_query: Dictionary) -> NetworkRequest:
	query_params = p_query.duplicate()
	return self


## 链式设置请求体数据。
func with_body(p_body: Variant) -> NetworkRequest:
	body = p_body
	return self


## 链式设置单次请求自定义 Header。
func with_headers(p_headers: PackedStringArray) -> NetworkRequest:
	headers = p_headers.duplicate()
	return self


## 链式设置单次尝试超时时间（秒）。
func with_timeout(p_timeout_sec: float) -> NetworkRequest:
	timeout = maxf(0.0, p_timeout_sec)
	return self


## 链式设置最大重试次数与指数退避基数（秒）。
func with_retries(p_max_retries: int, p_backoff_base: float = 0.3) -> NetworkRequest:
	max_retries = maxi(0, p_max_retries)
	retry_backoff_base = maxf(0.05, p_backoff_base)
	return self


## 链式设置是否期望 JSON 响应。
func with_expect_json(p_expect_json: bool) -> NetworkRequest:
	expect_json = p_expect_json
	return self


## 链式绑定协作式取消令牌。
func with_cancel_token(p_token: CancellationToken) -> NetworkRequest:
	cancel_token = p_token
	return self


## 链式开启或关闭 HMAC-SHA256 请求防篡改签名（可选指定单次专属密钥）。
func with_signature(p_enabled: bool = true, p_custom_secret: String = "") -> NetworkRequest:
	sign_request = p_enabled
	signing_secret = p_custom_secret.strip_edges()
	return self
#endregion
