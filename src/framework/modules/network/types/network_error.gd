class_name NetworkError
extends RefCounted

## 网络模块标准化错误码常量定义（Network Error Codes）。[br]
##
## 严格遵循 Framework [code]{Module}.{Reason}[/code] 错误码规范，配合 [Result] 与 [FrameworkError] 使用。

## 请求 URL 为空、格式非法或无法解析
const INVALID_URL: String = "Network.InvalidUrl"

## 请求参数非法（如上传字节为空、下载保存路径为空、MD5 校验码为空等）
const INVALID_PARAM: String = "Network.InvalidParam"

## Godot HTTPRequest 启动请求失败（如忙状态、无效主机或底层句柄异常）
const REQUEST_START_FAILED: String = "Network.RequestStartFailed"

## 底层网络传输错误（DNS 解析失败、连接拒绝、连接断开、TLS/SSL 握手失败等）
const TRANSPORT_ERROR: String = "Network.TransportError"

## 单次请求或文件传输等待超时（HTTPRequest.RESULT_TIMEOUT 或 HTTP 408）
const TIMEOUT: String = "Network.Timeout"

## 请求被调用方通过 CancellationToken 取消，或因客户端关闭（dispose）被中止
const CANCELLED: String = "Network.Cancelled"

## HTTP 401 未授权或会话 Token 已过期（且自动刷新未配置或刷新失败）
const HTTP_UNAUTHORIZED: String = "Network.HttpUnauthorized"

## HTTP 429 请求过于频繁（触发服务端限流）
const HTTP_RATE_LIMITED: String = "Network.HttpRateLimited"

## HTTP 4xx 客户端请求错误（不含 401、408、429，不可自动重试）
const HTTP_CLIENT_ERROR: String = "Network.HttpClientError"

## HTTP 5xx 服务端内部或网关错误（可按指数退避策略自动重试）
const HTTP_SERVER_ERROR: String = "Network.HttpServerError"

## 响应体 JSON 反序列化失败（服务端返回了损坏的 JSON 或非预期格式）
const PARSE_ERROR: String = "Network.ParseError"

## 文件下载落盘、创建父目录或 .tmp 原子重命名失败等本地磁盘 I/O 错误
const IO_ERROR: String = "Network.IOError"

## 下载文件的实际 MD5 哈希值与预期值不匹配（资产损坏或被篡改）
const HASH_MISMATCH: String = "Network.HashMismatch"

## 网络客户端未初始化、正在关闭或已被销毁
const CLIENT_DISPOSED: String = "Network.ClientDisposed"
