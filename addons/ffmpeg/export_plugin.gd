@tool
extends EditorPlugin

## EIRTeam.FFmpeg 导出辅助插件。
##
## 确保在导出 Windows (win64) 以及其他桌面平台时，
## 底层动态链接库（avcodec, avformat 等）被完整打包并放置在可执行程序同级目录下。

var _export_plugin: FFmpegExportPlugin


func _enter_tree() -> void:
	_export_plugin = FFmpegExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	if _export_plugin != null:
		remove_export_plugin(_export_plugin)
		_export_plugin = null


class FFmpegExportPlugin extends EditorExportPlugin:
	const WIN64_DLLS: Array[String] = [
		"res://addons/ffmpeg/win64/avutil-58.dll",
		"res://addons/ffmpeg/win64/swresample-4.dll",
		"res://addons/ffmpeg/win64/swscale-7.dll",
		"res://addons/ffmpeg/win64/avcodec-60.dll",
		"res://addons/ffmpeg/win64/avformat-60.dll",
		"res://addons/ffmpeg/win64/avfilter-9.dll",
	]

	const LINUX64_SOS: Array[String] = [
		"res://addons/ffmpeg/linux64/libavutil.so.58",
		"res://addons/ffmpeg/linux64/libswresample.so.4",
		"res://addons/ffmpeg/linux64/libswscale.so.7",
		"res://addons/ffmpeg/linux64/libavcodec.so.60",
		"res://addons/ffmpeg/linux64/libavformat.so.60",
		"res://addons/ffmpeg/linux64/libavfilter.so.9",
	]

	func _get_name() -> String:
		return "EIRTeam.FFmpeg"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		if platform is EditorExportPlatformWindows or platform is EditorExportPlatformLinuxBSD:
			return true
		if platform != null and platform.has_method("get_os_name"):
			var name := platform.get_os_name()
			return name == "Windows" or name == "Linux" or name == "LinuxBSD"
		return false

	func _export_begin(features: PackedStringArray, is_debug: bool, path: String, flags: int) -> void:
		if features.has("windows"):
			var tags := PackedStringArray(["windows", "x86_64"])
			for dll in WIN64_DLLS:
				if FileAccess.file_exists(dll):
					add_shared_object(dll, tags, "")
				else:
					push_warning("[EIRTeam.FFmpeg] Warning: Windows dependency '%s' not found." % dll)
			
			var lib_dll := "res://addons/ffmpeg/win64/libgdffmpeg.windows.template_debug.x86_64.dll" if is_debug else "res://addons/ffmpeg/win64/libgdffmpeg.windows.template_release.x86_64.dll"
			if FileAccess.file_exists(lib_dll):
				add_shared_object(lib_dll, tags, "")
		elif features.has("linux") or features.has("linuxbsd"):
			var tags := PackedStringArray(["linux", "x86_64"])
			for so in LINUX64_SOS:
				if FileAccess.file_exists(so):
					add_shared_object(so, tags, "")
				else:
					push_warning("[EIRTeam.FFmpeg] Warning: Linux dependency '%s' not found." % so)
			
			var lib_so := "res://addons/ffmpeg/linux64/libgdffmpeg.linux.template_debug.x86_64.so" if is_debug else "res://addons/ffmpeg/linux64/libgdffmpeg.linux.template_release.x86_64.so"
			if FileAccess.file_exists(lib_so):
				add_shared_object(lib_so, tags, "")
