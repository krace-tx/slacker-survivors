@tool
extends EditorPlugin

var _export_plugin: AndroidVideoExportPlugin


func _enter_tree() -> void:
	_export_plugin = AndroidVideoExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	if _export_plugin != null:
		remove_export_plugin(_export_plugin)
		_export_plugin = null


class AndroidVideoExportPlugin extends EditorExportPlugin:
	var _plugin_name := "GodotVideoPlayer"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		if platform is EditorExportPlatformAndroid:
			return true
		if platform != null and platform.has_method("get_os_name"):
			return platform.get_os_name() == "Android"
		return false

	func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		var lib_path := "res://addons/video_player_android/godot_video_player.gdap"
		var aar_path := "res://addons/video_player_android/godot_video_player.aar"
		if FileAccess.file_exists(lib_path) and _has_compiled_plugin(aar_path):
			return PackedStringArray([lib_path])
		push_warning("GodotVideoPlayer AAR is missing or has no compiled classes.jar; run addons/video_player_android/build_android.sh before exporting Android.")
		return PackedStringArray()

	func _has_compiled_plugin(aar_path: String) -> bool:
		if not FileAccess.file_exists(aar_path):
			return false
		var zip := ZIPReader.new()
		if zip.open(aar_path) != OK:
			return false
		var classes := zip.read_file("classes.jar")
		zip.close()
		return not classes.is_empty()

	func _get_name() -> String:
		return _plugin_name
