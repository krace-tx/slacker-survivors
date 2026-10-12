class_name NetworkRequest
extends RefCounted

## 网络请求配置对象（数据载荷）。[br]
## 描述单次 HTTP 请求的目标 URL、请求方法、消息体、自定义 Header 以及超时/重试策略。

var url: String = ""
var method: String = "GET"
var body: Dictionary = {}
var headers: PackedStringArray = []
var timeout: float = 5.0
var max_retries: int = 2
var retry_backoff_base: float = 0.3


func _init(p_url: String = "", p_method: String = "GET", p_body: Dictionary = {}, p_headers: PackedStringArray = []) -> void:
	url = p_url
	method = p_method
	body = p_body
	headers = p_headers
