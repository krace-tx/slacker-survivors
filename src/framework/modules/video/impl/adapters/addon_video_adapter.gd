class_name AddonVideoAdapter
extends VideoPlayerAdapter

## 开源专业视频插件适配器（GDExtension FFmpeg / Native Video / GDE GoZen）。[br]
##
## 动态探测并桥接 [code]addons/[/code] 中安装的专业开源插件（如 [code]EIRTeam.FFmpeg[/code]、[code]GDE GoZen[/code]、[code]Native Video[/code] 等）。[br]
## 采用动态反射探测 [code]ClassDB[/code]，若环境未编译或未安装该扩展，绝不抛出语法错误或崩溃。

## 社区主流开源 GDExtension 插件的类名候选列表
const KNOWN_EXTENSION_CLASSES: Array[StringName] = [
	&"FFmpegVideoStream",           # EIRTeam.FFmpeg
	&"VideoStreamFFmpeg",          # 变体 FFmpeg
	&"GoZenVideoStream",           # GDE GoZen (Codeberg / itch.io)
	&"NativeVideoStream",          # Clay Tercek Native Video (AVFoundation / Media Foundation)
	&"PlatformMediaVideoStream",   # Platform Media Streams
	&"VLCMediaStream",             # godot-vlc
	&"GDExtensionVideoStream",     # 通用 GDExtension 视频基类
]

## 支持的常见工业级视频格式扩展名
const SUPPORTED_EXTENSIONS: Array[String] = [
	"mp4", "m4v", "mkv", "avi", "mov", "webm", "flv", "wmv", "ts", "ogv"
]


func is_available() -> bool:
	for class_name_item in KNOWN_EXTENSION_CLASSES:
		if ClassDB.class_exists(class_name_item):
			return true
	return false


func get_adapter_name() -> String:
	var detected_class := _get_available_class()
	if detected_class != &"":
		return "Open-Source GDExtension (%s)" % String(detected_class)
	return "Open-Source GDExtension (Not Installed)"


func can_handle(file_path: String) -> bool:
	if not is_available():
		return false
	var ext := file_path.get_extension().to_lower()
	return ext in SUPPORTED_EXTENSIONS


func create_stream(file_path: String) -> Result:
	# 策略 1：如果插件注册了 ResourceFormatLoader，直接通过 ResourceLoader 加载
	if ResourceLoader.exists(file_path, "VideoStream"):
		var loaded_res := ResourceLoader.load(file_path, "VideoStream")
		if loaded_res != null and loaded_res is VideoStream:
			return Result.ok(loaded_res as VideoStream)
	
	# 策略 2：通过 ClassDB 反射实例化候选类并绑定视频文件
	var target_class := _get_available_class()
	if target_class == &"":
		return Result.err_code(
			"Video.AddonNotInstalled",
			"No compatible GDExtension video plugin detected in ClassDB. Please install EIRTeam.FFmpeg or GDE GoZen into addons/ to play MP4/MKV videos."
		)
	
	var stream: Object = ClassDB.instantiate(target_class)
	if stream == null or not (stream is VideoStream):
		return Result.err_code(
			"Video.InstantiationFailed",
			"Failed to instantiate VideoStream from class '%s'." % String(target_class)
		)
	
	# 设置视频文件路径（兼容属性与方法设置两种形式）
	if "file" in stream:
		stream.set("file", file_path)
	elif stream.has_method("set_file"):
		stream.call("set_file", file_path)
	
	return Result.ok(stream as VideoStream)


func _get_available_class() -> StringName:
	for class_name_item in KNOWN_EXTENSION_CLASSES:
		if ClassDB.class_exists(class_name_item):
			return class_name_item
	return &""
