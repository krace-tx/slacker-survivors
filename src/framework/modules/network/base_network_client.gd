@abstract
class_name BaseNetworkClient
extends Node

## 网络通信客户端契约（Network Client Contract）。[br]
##
## 本抽象基类作为业务层发起 HTTP 请求与网络文件传输的唯一规范入口，核心职责：[br]
## - [b]有界并发连接池调度[/b]：基于并发上限与等待队列管理 [HTTPRequest] 节点池，自动复用、限流与裁剪；[br]
## - [b]带抖动指数退避重试[/b]：对网络抖动、超时、429 限流与 5xx 错误按策略自动退避重发，4xx 客户端错误立即失败；[br]
## - [b]统一鉴权与 401 刷新拦截[/b]：自动注入 Bearer Token 与全局公共 Header，支持 401 令牌刷新后透明重放；[br]
## - [b]事务级原子文件传输[/b]：流式下载至 [code].tmp[/code] 临时文件，完成状态码与 MD5 强校验后原子重命名落盘，杜绝残卷污染；[br]
## - [b]异步取消守卫[/b]：全链路支持 [CancellationToken]，配合 [TaskScope] 在 UI/场景退出时立即中止飞行请求。[br]
##
## 业务代码应统一通过 [code]App.net[/code] 访问本契约提供的方法。


#region Configuration & Authentication
## 设置全局 API 基础地址（如 [code]"https://api.game.com"[/code]）。[br]
##
## 设置后，向请求接口传入相对路径（如 [code]"/v1/leaderboard"[/code]）时将自动拼接该前缀；
## 若传入完整 URL（以 [code]http://[/code] 或 [code]https://[/code] 开头）则忽略此基础地址。
@abstract
func set_base_url(base_url: String) -> void


## 获取当前配置的全局 API 基础地址。
@abstract
func get_base_url() -> String


## 设置全局通用的用户会话鉴权令牌（Bearer Token）。[br]
##
## 设置后，所有由本服务调度的请求与文件传输将在 Header 自动附带 [code]Authorization: Bearer <token>[/code]。[br]
## 传入空字符串时将注销并移除该全局鉴权头。[br]
##
## [param token] 远端服务端颁发的用户 Token 字符串。
@abstract
func set_auth_token(token: String) -> void


## 获取当前已设置的 Bearer Token（未设置时返回空字符串）。
@abstract
func get_auth_token() -> String


## 设置全局默认请求头（如客户端版本号 [code]X-Client-Version[/code]、语言标识等）。[br]
##
## [param key] Header 名称（如 [code]"X-Client-Version"[/code]）。[br]
## [param value] Header 值（传空字符串时等同于移除该 Header）。
@abstract
func set_default_header(key: String, value: String) -> void


## 移除指定的全局默认请求头。
@abstract
func remove_default_header(key: String) -> void


## 清空所有自定义的全局默认请求头（不影响 [method set_auth_token] 设置的鉴权令牌）。
@abstract
func clear_default_headers() -> void


## 配置全局 HTTP 请求防篡改签名密钥（HMAC-SHA256）与可选的权威毫秒时钟源。[br]
##
## 设置非空 [param secret] 后，所有允许签名（[member NetworkRequest.sign_request] 为 [code]true[/code]）的请求在每次发送尝试时
## 将自动通过 [method CryptoUtils.sign_http_request] 注入 [code]X-Timestamp[/code]、[code]X-Nonce[/code]、[code]X-Content-SHA256[/code] 与 [code]X-Signature[/code] 请求头。[br]
##
## [param secret] 客户端 HMAC 签名密钥（传入空字符串等同于关闭全局签名）。[br]
## [param timestamp_ms_getter] 可选的毫秒时间戳获取回调 [code]func() -> int[/code]（推荐传入 [code]App.clock.now_msec[/code]）。
@abstract
func set_request_signing(secret: String, timestamp_ms_getter: Callable = Callable()) -> void


## 清除全局 HTTP 请求防篡改签名密钥与时钟源配置。
@abstract
func clear_request_signing() -> void


## 注册 HTTP 401 (Unauthorized) 鉴权失效自动刷新处理器。[br]
##
## 当请求收到 HTTP 401 时，若已注册有效 [param handler]，网络层将自动挂起并调用该处理器一次：[br]
## - [param handler] 签名应为 [code]func() -> Result[/code]（支持异步协程）；[br]
## - 若返回 [code]Result.ok(new_token)[/code]（或内部已调用 [method set_auth_token] 且返回 [code]Result.ok()[/code]），
##   网络层将自动使用新 Token 无感重放原请求一次；[br]
## - 若刷新失败或重放仍返回 401，则向调用方返回 [constant NetworkError.HTTP_UNAUTHORIZED]。
@abstract
func set_unauthorized_handler(handler: Callable) -> void
#endregion


#region HTTP Requests
## 发送通用配置化网络请求（支持完整自定义超时、重试策略、HTTP 方法与取消令牌）。[br]
##
## [b]注意：[/b]本方法为异步方法，调用端必须使用 [code]await[/code] 等待结果。[br]
##
## [param request] 封装了完整请求参数的 [NetworkRequest] 实例。[br]
## @return 返回 [Result]：成功时 [code]result.value[/code] 为解析后的 JSON（[Dictionary] / [Array]）或原始文本；
##         失败时 [code]result.error[/code] 为携带 [NetworkError] 错误码与诊断上下文的 [FrameworkError]。
@abstract
func send_request(request: NetworkRequest) -> Result


## 发起异步 GET 请求。[br]
##
## [b]注意：[/b]本方法为异步方法，调用端必须使用 [code]await[/code] 等待结果。[br]
##
## [param url] 请求目标 URL 或相对路径（支持已含 query 参数）。[br]
## [param params] 键值对字典（系统会自动进行 URL-Encoding 编码并安全拼接在 Query 串中）。[br]
## [param custom_headers] 单次请求附加的自定义 Header（可选）。[br]
## [param cancel_token] 协作式取消令牌（可选，推荐传入 [code]task_scope.get_token()[/code]）。[br]
## @return 返回 [Result] 对象：成功时 [code]result.value[/code] 包含解析后的 Dictionary/Array。
@abstract
func get_request(
	url: String,
	params: Dictionary = {},
	custom_headers: PackedStringArray = [],
	cancel_token: CancellationToken = null
) -> Result


## 发起异步 POST 请求（默认载荷为 JSON 格式）。[br]
##
## [b]注意：[/b]本方法为异步方法，调用端必须使用 [code]await[/code] 等待结果。[br]
##
## [param url] 请求目标 URL 或相对路径。[br]
## [param body] 请求体数据字典，自动序列化为 JSON 字符串发送。[br]
## [param custom_headers] 单次请求附加的自定义 Header（可选）。[br]
## [param cancel_token] 协作式取消令牌（可选）。[br]
## @return 返回 [Result] 对象。
@abstract
func post_request(
	url: String,
	body: Dictionary = {},
	custom_headers: PackedStringArray = [],
	cancel_token: CancellationToken = null
) -> Result


## 发起异步 PUT 请求（默认载荷为 JSON 格式）。[br]
##
## [b]注意：[/b]本方法为异步方法，调用端必须使用 [code]await[/code] 等待结果。[br]
##
## [param url] 请求目标 URL 或相对路径。[br]
## [param body] 请求体数据字典，自动序列化为 JSON 字符串发送。[br]
## [param custom_headers] 单次请求附加的自定义 Header（可选）。[br]
## [param cancel_token] 协作式取消令牌（可选）。[br]
## @return 返回 [Result] 对象。
@abstract
func put_request(
	url: String,
	body: Dictionary = {},
	custom_headers: PackedStringArray = [],
	cancel_token: CancellationToken = null
) -> Result


## 发起异步 DELETE 请求。[br]
##
## [b]注意：[/b]本方法为异步方法，调用端必须使用 [code]await[/code] 等待结果。[br]
##
## [param url] 请求目标 URL 或相对路径。[br]
## [param params] 可选 URL 查询参数字典。[br]
## [param custom_headers] 单次请求附加的自定义 Header（可选）。[br]
## [param cancel_token] 协作式取消令牌（可选）。[br]
## @return 返回 [Result] 对象。
@abstract
func delete_request(
	url: String,
	params: Dictionary = {},
	custom_headers: PackedStringArray = [],
	cancel_token: CancellationToken = null
) -> Result
#endregion


#region File Transfer (Upload & Atomic Download)
## 异步上传二进制文件（基于 multipart/form-data 格式）。[br]
##
## [b]注意：[/b]本方法为异步方法，调用端必须使用 [code]await[/code] 等待结果。[br]
##
## [param url] 上传接口地址或相对路径。[br]
## [param field_name] 表单字段名称（如 [code]"file"[/code]、[code]"avatar"[/code]）。[br]
## [param file_bytes] 文件的原始二进制字节流。[br]
## [param filename] 上传的文件名（包含后缀，如 [code]"screenshot.png"[/code]）。[br]
## [param mime_type] 文件的 MIME 类型（如 [code]"image/png"[/code]、[code]"application/octet-stream"[/code]）。[br]
## [param custom_headers] 自定义请求头（可选）。[br]
## [param timeout_sec] 超时时间上限（秒，默认 15.0）。[br]
## [param cancel_token] 协作式取消令牌（可选）。[br]
## @return 返回 [Result] 对象。
@abstract
func upload_file(
	url: String,
	field_name: String,
	file_bytes: PackedByteArray,
	filename: String,
	mime_type: String,
	custom_headers: PackedStringArray = [],
	timeout_sec: float = 15.0,
	cancel_token: CancellationToken = null
) -> Result


## 异步流式下载文件并事务级原子保存至指定本地磁盘路径。[br]
##
## 采用 [code].tmp[/code] 临时文件写入模式，下载成功并验证 HTTP 2xx 状态码后原子重命名至 [param save_path]；
## 若断网、超时、返回非 2xx 或被取消，将自动清理临时残卷，绝不损坏目标路径已有文件。[br]
##
## [param url] 远程下载链接或相对路径。[br]
## [param save_path] 本地保存路径（如 [code]user://downloads/patch.pck[/code]）。[br]
## [param on_progress] 进度回调函数，签名格式为 [code]func(downloaded_bytes: int, total_bytes: int)[/code]。[br]
## [param custom_headers] 自定义请求头（可选）。[br]
## [param cancel_token] 协作式取消令牌（可选）。[br]
## @return 返回 [Result] 对象：成功时 [code]result.value[/code] 为 [param save_path]。
@abstract
func download_file(
	url: String,
	save_path: String,
	on_progress: Callable = Callable(),
	custom_headers: PackedStringArray = [],
	cancel_token: CancellationToken = null
) -> Result


## 异步流式下载文件并在 [code].tmp[/code] 临时文件上执行 MD5 哈希完整性强校验后原子落盘。[br]
##
## 若计算出的文件哈希与期望的 [param expected_md5] 不匹配，系统将直接删除临时文件并返回 [constant NetworkError.HASH_MISMATCH]，
## 杜绝损坏资产污染目标路径。[br]
##
## [param url] 远程下载链接或相对路径。[br]
## [param save_path] 本地保存路径。[br]
## [param expected_md5] 预期的 32 位 MD5 十六进制校验码（不区分大小写）。[br]
## [param on_progress] 进度回调函数（可选），签名格式为 [code]func(downloaded_bytes: int, total_bytes: int)[/code]。[br]
## [param custom_headers] 自定义请求头（可选）。[br]
## [param cancel_token] 协作式取消令牌（可选）。[br]
## @return 返回 [Result] 对象：成功时 [code]result.value[/code] 为 [param save_path]。
@abstract
func download_file_with_md5(
	url: String,
	save_path: String,
	expected_md5: String,
	on_progress: Callable = Callable(),
	custom_headers: PackedStringArray = [],
	cancel_token: CancellationToken = null
) -> Result
#endregion


#region Lifecycle & Diagnostics
## 立即取消当前所有排队中与飞行中的 HTTP 请求及文件传输。
@abstract
func cancel_all_requests(reason: String = "All network requests cancelled.") -> void


## 获取网络客户端与连接池的运行时诊断指标快照。
@abstract
func get_diagnostics() -> Dictionary
#endregion
