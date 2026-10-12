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
		if FileAccess.file_exists(plugin_path):
			return PackedStringArray([plugin_path])
		return PackedStringArray()

	func _get_name() -> String:
		return _plugin_name
