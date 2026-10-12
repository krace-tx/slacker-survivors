class_name AddonVideoAdapter
extends VideoPlayerAdapter

## 开源专业视频插件适配器（GDExtension FFmpeg）。[br]
##
## 桥接 [code]addons/ffmpeg[/code] 中构建的 GDExtension FFmpeg 工业级编解码底座。[br]
## 支持在桌面端（macOS / Windows / Linux）无缝解码播放 MP4、MKV、AVI、MOV、WebM、FLV 等全格式高清视频流。

## 本工程官方配置与打包的 FFmpeg GDExtension 核心类名
const EXTENSION_CLASS: StringName = &"FFmpegVideoStream"

## 支持的工业级视频格式扩展名
const SUPPORTED_EXTENSIONS: Array[String] = [
	"mp4", "m4v", "mkv", "avi", "mov", "webm", "flv", "wmv", "ts"
]


func is_available() -> bool:
	return ClassDB.class_exists(EXTENSION_CLASS)


func get_adapter_name() -> String:
	if is_available():
		return "FFmpeg GDExtension (%s)" % String(EXTENSION_CLASS)
	return "FFmpeg GDExtension (Not Installed)"


func can_handle(file_path: String) -> bool:
	if not is_available():
		return false
	var ext := file_path.get_extension().to_lower()
	return ext in SUPPORTED_EXTENSIONS


func create_stream(file_path: String) -> Result:
	# 策略 1：如果插件注册了 ResourceFormatLoader，直接通过 ResourceLoader 载入流
	if ResourceLoader.exists(file_path, "VideoStream"):
		var loaded_res := ResourceLoader.load(file_path, "VideoStream")
		if loaded_res != null and loaded_res is VideoStream:
			return Result.ok(loaded_res as VideoStream)
	
	# 策略 2：通过 ClassDB 直接实例化官方 FFmpeg 视频流并配置资源路径
	if not is_available():
		return Result.err_code(
			VideoError.ADDON_NOT_INSTALLED,
			"FFmpeg GDExtension plugin (%s) is not loaded in ClassDB. Ensure addons/ffmpeg is installed." % String(EXTENSION_CLASS)
		)
	
	var stream: Object = ClassDB.instantiate(EXTENSION_CLASS)
	if stream == null or not (stream is VideoStream):
		return Result.err_code(
			VideoError.INSTANTIATION_FAILED,
			"Failed to instantiate VideoStream from class '%s'." % String(EXTENSION_CLASS)
		)
	
	stream.set("file", file_path)
	return Result.ok(stream as VideoStream)
