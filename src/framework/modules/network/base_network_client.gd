@abstract
class_name BaseNetworkClient
extends NodeSubsystem

## 网络通信客户端契约（Network Client Contract）。[br]
##
## 本抽象基类作为业务层发起 HTTP 请求与网络文件传输的唯一规范入口，核心职责：[br]
## - HTTP 连接池调度：基于队列与并发上限管理 [HTTPRequest] 实例，自动复用与销毁；[br]
## - 指数退避重试：对网络抖动、偶发超时请求按策略自动退避重发；[br]
## - 统一鉴权注入：管理用户会话 Bearer Token，并在请求发出时自动向 Header 注入鉴权；[br]
## - 二进制与文件流支持：大文件断点/流式下载与上传（支持进度回调与 MD5 完整性校验）。[br]
##
## 业务代码应统一通过 [code]App.net[/code] 访问本契约提供的方法。


## 返回该子系统的全局唯一注册标识符。
func get_id() -> String:
	return "network"


#region Authentication
## 设置全局通用的用户会话鉴权令牌（Bearer Token）。[br]
##
## 设置后，所有由本服务调度的请求将在 Header 自动附带 [code]Authorization: Bearer <token>[/code]。[br]
## 传入空字符串时将注销并移除该全局鉴权头。[br]
##
## [param token] 远端服务端颁发的用户 Token 字符串。
@abstract
func set_auth_token(token: String) -> void
#endregion


#region HTTP Requests
## 发起异步 GET 请求。[br]
##
## [b]注意：[/b]本方法为异步方法，调用端必须使用 [code]await[/code] 等待结果。[br]
##
## [param url] 请求目标 URL（支持带 query 参数）。[br]
## [param params] 键值对字典（系统会自动进行 URL-Encoding 编码并拼接在 Query 串中）。[br]
## @return 返回 [Result] 对象：成功时 [code]result.value[/code] 包含解析后的 Dictionary/Array 或响应文本。
@abstract
func get_request(url: String, params: Dictionary = {}) -> Result


## 发起异步 POST 请求（默认载荷为 JSON 格式）。[br]
##
## [b]注意：[/b]本方法为异步方法，调用端必须使用 [code]await[/code] 等待结果。[br]
##
## [param url] 请求目标 URL。[br]
## [param body] 请求体数据字典，自动序列化为 JSON 字符串发送。[br]
## @return 返回 [Result] 对象。
@abstract
func post_request(url: String, body: Dictionary = {}) -> Result


## 异步上传二进制文件（基于 multipart/form-data 格式）。[br]
##
## [b]注意：[/b]本方法为异步方法，调用端必须使用 [code]await[/code] 等待结果。[br]
##
## [param url] 上传接口地址。[br]
## [param field_name] 表单字段名称（如 "file"、"avatar"）。[br]
## [param file_bytes] 文件的原始二进制字节流。[br]
## [param filename] 上传的文件名（包含后缀，如 "screenshot.png"）。[br]
## [param mime_type] 文件的 MIME 类型（如 "image/png"、"application/octet-stream"）。[br]
## [param custom_headers] 自定义请求头（可选）。[br]
## [param timeout_sec] 超时时间上限（秒，默认 15.0）。[br]
## @return 返回 [Result] 对象。
@abstract
func upload_file(
	url: String,
	field_name: String,
	file_bytes: PackedByteArray,
	filename: String,
	mime_type: String,
	custom_headers: PackedStringArray = [],
	timeout_sec: float = 15.0
) -> Result


## 异步流式下载文件并保存至指定本地磁盘路径。[br]
##
## 采用临时文件写入模式，下载成功并校验完毕后原子重命名至 [param save_path]，防止断电或意外退出产生损坏残卷。[br]
##
## [param url] 远程下载链接。[br]
## [param save_path] 本地保存绝对路径（以 [code]user://[/code] 开头）。[br]
## [param on_progress] 进度回调函数，签名格式为 [code]func(downloaded_bytes: int, total_bytes: int)[/code]。[br]
## [param custom_headers] 自定义请求头。[br]
## @return 返回 [Result] 对象。
@abstract
func download_file(
	url: String,
	save_path: String,
	on_progress: Callable = Callable(),
	custom_headers: PackedStringArray = []
) -> Result


## 异步下载文件并在落盘完成后执行 MD5 哈希完整性强校验。[br]
##
## 若计算出的文件哈希与期望的 [param expected_md5] 不匹配，系统将自动删除损坏文件并返回错误结果，杜绝资产污染。[br]
##
## [param url] 远程下载链接。[br]
## [param save_path] 本地保存路径。[br]
## [param expected_md5] 预期的 32 位 MD5 十六进制校验码（不区分大小写）。[br]
## @return 返回 [Result] 对象。
@abstract
func download_file_with_md5(url: String, save_path: String, expected_md5: String) -> Result
#endregion
