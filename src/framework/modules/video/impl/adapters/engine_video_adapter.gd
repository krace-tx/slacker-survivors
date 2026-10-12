class_name EngineVideoAdapter
extends VideoPlayerAdapter

## Godot 引擎内置原生软解播放适配器（Theora 零依赖保底）。[br]
##
## 当运行环境未安装任何外部插件或运行在轻量测试/纯净环境时，作为零依赖的安全保底方案。[br]
## 支持开源免专利的 Ogg Theora ([code].ogv[/code]) 格式。

const THEORA_CLASS: StringName = &"VideoStreamTheora"
const SUPPORTED_EXTENSIONS: Array[String] = ["ogv", "ogg"]


func is_available() -> bool:
	return ClassDB.class_exists(THEORA_CLASS)


func get_adapter_name() -> String:
	return "Godot Engine Native (Theora)"


func can_handle(file_path: String) -> bool:
	var ext := file_path.get_extension().to_lower()
	return ext in SUPPORTED_EXTENSIONS


func create_stream(file_path: String) -> Result:
	var ext := file_path.get_extension().to_lower()
	if not can_handle(file_path):
		return Result.err_code(
			VideoError.CODEC_UNSUPPORTED,
			"Native Godot engine player only supports .ogv (Theora). Received: .%s. Install EIRTeam.FFmpeg to play modern MP4/WebM files." % ext
		)
	
	if not is_available():
		return Result.err_code(
			VideoError.ENGINE_STREAM_MISSING,
			"VideoStreamTheora class is unavailable in this engine build."
		)
	
	var stream := VideoStreamTheora.new()
	stream.file = file_path
	return Result.ok(stream)
