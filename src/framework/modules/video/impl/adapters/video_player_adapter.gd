class_name VideoPlayerAdapter
extends RefCounted

## 视频播放适配器基类接口。[br]
## 负责隔离底层具体视频解码插件与 Godot 原生 VideoStreamPlayer 的兼容性差异。


## 查询该适配器在当前运行环境（操作系统/GDExtension 注册表）中是否可用。
func is_available() -> bool:
	return false


## 获取当前适配器的显示名称。
func get_adapter_name() -> String:
	return "BaseAdapter"


## 评估该适配器是否能够处理指定路径的视频文件。
func can_handle(file_path: String) -> bool:
	return false


## 为指定文件创建适配的 [VideoStream] 资源实例。[br]
## @return 返回 [Result] 对象。成功时 value 为有效 [VideoStream]，失败返回明确错误信息。
func create_stream(file_path: String) -> Result:
	return Result.err_code("Video.NotImplemented", "Base adapter cannot instantiate video streams.")
