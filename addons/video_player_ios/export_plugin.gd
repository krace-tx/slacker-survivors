@tool
extends EditorPlugin

var _export_plugin: IOSVideoExportPlugin


func _enter_tree() -> void:
	_export_plugin = IOSVideoExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	if _export_plugin != null:
		remove_export_plugin(_export_plugin)
		_export_plugin = null


class IOSVideoExportPlugin extends EditorExportPlugin:
	var _plugin_name := "AVPlayer"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		if platform is EditorExportPlatformIOS:
			return true
		if platform != null and platform.has_method("get_os_name"):
			return platform.get_os_name() == "iOS"
		return false

	func _get_ios_plugins(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		var plugin_path := "res://addons/video_player_ios/godot_video_player.gdip"
		var binary_path := "res://addons/video_player_ios/godot_video_player.a"
		if FileAccess.file_exists(plugin_path) and _has_registration_entry(binary_path):
			return PackedStringArray([plugin_path])
		push_warning("AVPlayer static library is missing register_avplayer_types; run addons/video_player_ios/build_ios.sh with GODOT_HEADERS before exporting iOS.")
		return PackedStringArray()

	func _has_registration_entry(binary_path: String) -> bool:
		if not FileAccess.file_exists(binary_path):
			return false
		var bytes := FileAccess.get_file_as_bytes(binary_path)
		if bytes.is_empty():
			return false
		return bytes.get_string_from_ascii().contains("register_avplayer_types")

	func _get_name() -> String:
		return _plugin_name
