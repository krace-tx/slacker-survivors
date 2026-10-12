class_name MemoryUtils
extends RefCounted

## 内存与资源体积估算工具类。[br]
##
## 提供针对 Godot 各种 [Resource]（纹理、CPU 图像、音频流等）以及通用 [Variant] 类型的
## 静态显存/内存占用估算算法。按类型静态推算，不回读显存、不拷 CPU 缓冲。

#region Constants & Enums
## 未知资源类型的占位估算体积（256KB），避免上限被架空
const UNKNOWN_BYTES: int = 256 * 1024
#endregion

#region Public API
## 估算任意 [Variant] 数据在内存中的占用字节数。[br]
## 支持 [Resource]、[PackedByteArray]、[Image]、[Dictionary]、[Array]、[String] 等所有通用类型。
static func estimate_bytes(data: Variant) -> int:
	if data == null:
		return 0
	if data is Resource:
		var info := inspect(data as Resource)
		return int(info.bytes) if info.known else UNKNOWN_BYTES
	if data is PackedByteArray:
		return (data as PackedByteArray).size()
	if data is Image:
		return _image_bytes(data as Image)
	if data is String or data is StringName:
		return str(data).length()
	if data is Dictionary or data is Array:
		var json_str := JSON.stringify(data)
		return json_str.length() if not json_str.is_empty() else UNKNOWN_BYTES
	return 64 # 基础标量数据


## 单份 [Resource] 资源的估算字节数。[br]
## 返回 [code]{ bytes: int, known: bool, type: String }[/code]。
static func inspect(res: Resource) -> Dictionary:
	if res == null or not is_instance_valid(res):
		return {bytes = 0, known = false, type = ""}

	var type_name := res.get_class()

	# 1. 图集子图：显存由引用的底层大图承担，避免重复计算
	if res is AtlasTexture:
		return {bytes = 0, known = true, type = type_name}

	# 2. 纹理类（包括 CompressedTexture2D）
	if res is Texture2D:
		return {bytes = _texture_bytes(res as Texture2D), known = true, type = type_name}

	# 3. CPU 原始图像
	if res is Image:
		return {bytes = _image_bytes(res as Image), known = true, type = type_name}

	# 4. 音频流系列 (WAV / MP3 / OGG)
	if res is AudioStreamWAV:
		return {bytes = (res as AudioStreamWAV).data.size(), known = true, type = type_name}
	if res is AudioStreamMP3:
		return {bytes = (res as AudioStreamMP3).data.size(), known = true, type = type_name}
	if res is AudioStreamOggVorbis:
		var ogg := res as AudioStreamOggVorbis
		var bytes := ogg.packet_sequence.packet_data.size() if ogg.packet_sequence else 0
		return {bytes = bytes, known = true, type = type_name}

	# 5. 其余不可直接推算的资源类型（如 PackedScene、Shader、Material 等）
	return {bytes = 0, known = false, type = type_name}
#endregion

#region Internal
static func _texture_bytes(tex: Texture2D) -> int:
	var w := tex.get_width()
	var h := tex.get_height()
	if w <= 0 or h <= 0:
		return 0

	# 基础未压缩 RGBA8 显存基线
	var base_bytes := w * h * 4

	# 若启用了 Mipmaps，显存会产生约 33% (1/3) 的链式几何级数膨胀
	if tex.has_method("has_mipmaps") and tex.has_mipmaps():
		return int(base_bytes * 1.333)
	return base_bytes


static func _image_bytes(img: Image) -> int:
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return 0

	# 通过格式推算每个像素的等效字节数（支持浮点与压缩格式）
	var bpp_ratio := _bytes_per_pixel(img.get_format())
	var total := int(w * h * bpp_ratio)

	if img.has_mipmaps():
		total = int(total * 1.333)
	return total


static func _bytes_per_pixel(fmt: Image.Format) -> float:
	match fmt:
		# 1 字节系列
		Image.FORMAT_L8, Image.FORMAT_R8:
			return 1.0
		# 2 字节系列
		Image.FORMAT_LA8, Image.FORMAT_RG8, Image.FORMAT_RGBA4444, Image.FORMAT_RGB565:
			return 2.0
		# 3 字节系列
		Image.FORMAT_RGB8:
			return 3.0
		# 4 字节系列（常规未压缩 / 32位单通道浮点）
		Image.FORMAT_RGBA8, Image.FORMAT_RF:
			return 4.0
		# 高动态 HDR 浮点系列
		Image.FORMAT_RGF:
			return 8.0
		Image.FORMAT_RGBF:
			return 12.0
		Image.FORMAT_RGBAF:
			return 16.0

		# VRAM 硬件块压缩格式（GPU 贴图常见）
		Image.FORMAT_DXT1, Image.FORMAT_ETC, Image.FORMAT_ETC2_R11:
			return 0.5 # 4bpp
		Image.FORMAT_DXT3, Image.FORMAT_DXT5, Image.FORMAT_ETC2_RGBA8, Image.FORMAT_ASTC_4x4:
			return 1.0 # 8bpp
		Image.FORMAT_ASTC_8x8:
			return 0.25 # 2bpp

		_:
			return 4.0 # 默认兜底按 RGBA8
#endregion
