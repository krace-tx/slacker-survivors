class_name RemoteStorageDriver
extends StorageDriver

## 远端存储驱动：封装核心 HTTP 操作。[br]
##
## 本驱动作为纯粹的 I/O 执行者，不再进行类型嗅探。它完全根据上层透传的 [param kwargs] 
## (尤其是 [code]payload_type[/code]) 来决定走常规的 JSON 请求还是大文件流上传/下载。
## 所有底层实际的网络交互由注入的 [BaseNetworkClient] 提供支持，不依赖全局单例。

var _network_service: BaseNetworkClient


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
	var url := str(key)
	if url.is_empty():
		return Result.ok(false)
	return Result.ok(true)


## 拦截删除操作
func delete(_key: StringName) -> Result:
	return Result.err("Remote hard deletion is disabled by default for security reasons.")
#endregion

#region Async API
## 发起异步读请求（下载文件 或 GET JSON）。[br]
## [b]kwargs 参数约束：[/b][br]
## - [code]payload_type[/code] (String): 载荷类型，[code]"FILE"[/code] 或 [code]"JSON"[/code] (默认)。[br]
## - [code]save_path[/code] (String): 当 [code]payload_type == "FILE"[/code] 时必填，文件落地保存的完整路径。[br]
## - [code]on_progress[/code] (Callable): 可选，文件下载进度回调，签名为 [code]func(downloaded: int, total: int)[/code]。[br]
## - [code]expected_md5[/code] (String): 可选，文件下载完毕后的完整性校验 MD5。
func read_async(key: StringName, kwargs: Dictionary = {}) -> Result:
	if not _network_service:
		return Result.err("NetworkService is not available")
		
	var url := str(key)
	var payload_type: String = kwargs.get("payload_type", "JSON").to_upper()
	
	if payload_type == "FILE":
		var save_path: String = kwargs.get("save_path", "")
		if save_path.is_empty():
			return Result.err("RemoteStorageDriver download requires 'save_path' in kwargs")
			
		var on_progress: Callable = kwargs.get("on_progress", Callable())
		var expected_md5: String = kwargs.get("expected_md5", "")
		
		if not expected_md5.is_empty():
			return await _network_service.download_file_with_md5(url, save_path, expected_md5)
		return await _network_service.download_file(url, save_path, on_progress)
	else:
		return await _network_service.get_request(url)


## 发起异步写请求（上传文件 或 POST/GET JSON）。[br]
## [b]kwargs 参数约束：[/b][br]
## - [code]payload_type[/code] (String): 载荷类型，[code]"FILE"[/code] 或 [code]"JSON"[/code] (默认)。[br]
## - [code]method[/code] (String): 当为 JSON 时，请求方法 [code]"GET"[/code] 或 [code]"POST"[/code] (默认)。[br]
## - [code]filename[/code] (String): 当 [code]payload_type == "FILE"[/code] 时，上传的表单文件名，默认 [code]"upload.bin"[/code]。[br]
## - [code]mime_type[/code] (String): 当 [code]payload_type == "FILE"[/code] 时，上传的 MIME 类型，默认 [code]"application/octet-stream"[/code]。
func write_async(key: StringName, data: Variant, kwargs: Dictionary = {}) -> Result:
	if not _network_service:
		return Result.err("NetworkService is not available")
		
	var url := str(key)
	var method: String = kwargs.get("method", "POST").to_upper()
	var payload_type: String = kwargs.get("payload_type", "JSON").to_upper()
	
	if payload_type == "FILE":
		var file_bytes: PackedByteArray
		if data is PackedByteArray:
			file_bytes = data
		else:
			return Result.err("RemoteStorageDriver file upload expects data to be PackedByteArray")
			
		var filename: String = kwargs.get("filename", "upload.bin")
		var mime_type: String = kwargs.get("mime_type", "application/octet-stream")
		
		return await _network_service.upload_file(url, "file", file_bytes, filename, mime_type)
	else:
		if method == "GET":
			return await _network_service.get_request(url, data)
		else:
			return await _network_service.post_request(url, data)
#endregion
