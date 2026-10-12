class_name VideoPlayerAdapter
extends RefCounted

## 视频播放适配器抽象基类（Video Player Adapter Abstract Contract）。[br]
##
## 隔离具体底层视频解码插件（如 GDExtension FFmpeg、Android ExoPlayer、iOS AVPlayer 或引擎原生 Theora）
## 与上层通用门面驱动间的兼容性与协议差异。[br]
##
## 各平台与技术栈通过继承本类实现专属解码与播放管线。


## 初始化装配钩子：在此处完成对依赖项的注入或单例检测。
func setup() -> void:
	pass


## 释放销毁钩子：在系统关闭或热重载时释放外部动态库持有的句柄。
func dispose() -> void:
	pass


## 查询该适配器在当前运行宿主（操作系统、GDExtension 注册表或单例表）中是否可用就绪。
func is_available() -> bool:
	return false


## 获取当前适配器的显示名称（用于日志诊断与后台探测打印）。
func get_adapter_name() -> String:
	return "BaseAdapter"


## 评估该适配器是否具备处理指定文件路径或容器扩展名的能力。
func can_handle(_file_path: String) -> bool:
	return false


## 为指定视频文件构建匹配的 [VideoStream] 资源实例。[br]
## @return 返回 [Result] 对象。成功时包含有效 [VideoStream] 实例；失败时携带标准 [VideoError] 错误码。
func create_stream(_file_path: String) -> Result:
	return Result.err_code(VideoError.NOT_IMPLEMENTED, "Base adapter cannot instantiate video streams.")


## 查询当前适配器是否属于移动端系统级硬件全屏播放器（Android/iOS）。
func is_mobile_native() -> bool:
	return false


## 查询当前适配器是否支持通过 [Texture2D] 暴露逐帧画面（以用于材质贴图或自定义视口）。
func supports_texture_output() -> bool:
	return true
