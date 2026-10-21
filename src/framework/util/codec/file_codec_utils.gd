class_name FileCodecUtils
extends RefCounted

## 图像与纹理二进制编解码纯函数工具类。[br]
##
## [b]核心设计（第一性原理）：[/b][br]
## 1. [b]零状态与零瞬态对象分配[/b]：废除冗余的多态子类继承树，全静态方法直达底层缓冲操作；[br]
## 2. [b]O(1) 文件头魔数嗅探（Magic Number Sniffing）[/b]：通过前 12 字节文件头精准识别 PNG / JPG / WebP / BMP / KTX / SVG，
##    杜绝盲目试错解码引发的 CPU 浪费与 Godot C++ 底层错误日志刷屏；[br]
## 3. [b]跨介质路径安全解码[/b]：自动区分包内编译资源（[code]res://[/code]）与外部沙盒无后缀缓存（[code]user://[/code]），
##    确保导出包（[code].ctex[/code]）与自定义扩展名缓存文件均能可靠加载。


#region Public API

## 将 [Image] 或 [Texture2D] 编码为压缩图像二进制字节流。[br]
## [param value] 支持 [Image] 或 [Texture2D]（及其派生类）。[br]
## [param format] 目标容器格式：[code]"png"[/code]（默认）、[code]"jpg"[/code] / [code]"jpeg"[/code]、[code]"webp"[/code]。[br]
## [param quality] 有损压缩质量（0.0 ~ 1.0，仅对 jpg 及有损 webp 生效，默认 0.85）。[br]
## 成功时 [member Result.value] 为 [PackedByteArray]。
static func encode(value: Variant, format: String = "png", quality: float = 0.85) -> Result:
	if value is Image:
		return encode_image(value as Image, format, quality)
	if value is Texture2D:
		return encode_texture(value as Texture2D, format, quality)
	return Result.err("FileCodecUtils.encode failed: unsupported value type (expected Image or Texture2D).")


## 将 [Image] 编码为二进制字节流。[br]
## [param image] 非空的源 [Image] 实例。[br]
## [param format] [code]"png"[/code]（默认）、[code]"jpg"[/code] / [code]"jpeg"[/code]、[code]"webp"[/code]（无损）、[code]"webp_lossy"[/code]（有损）。[br]
## [param quality] 有损压缩质量（0.0 ~ 1.0）。[br]
## 成功时 [member Result.value] 为 [PackedByteArray]。
static func encode_image(image: Image, format: String = "png", quality: float = 0.85) -> Result:
	if image == null or image.is_empty():
		return Result.err("FileCodecUtils.encode_image failed: image is null or empty.")

	var fmt := format.strip_edges().to_lower()
	if fmt.is_empty():
		fmt = "png"

	var clamped_quality := clampf(quality, 0.01, 1.0)
	var bytes := PackedByteArray()

	match fmt:
		"png":
			bytes = image.save_png_to_buffer()
		"jpg", "jpeg":
			bytes = image.save_jpg_to_buffer(clamped_quality)
		"webp":
			bytes = image.save_webp_to_buffer(false)
		"webp_lossy":
			bytes = image.save_webp_to_buffer(true, clamped_quality)
		_:
			return Result.err("FileCodecUtils.encode_image failed: unsupported format '%s'." % fmt)

	if bytes.is_empty():
		return Result.err("FileCodecUtils.encode_image failed: buffer encoding returned empty.")
	return Result.ok(bytes)


## 将 [Texture2D] 编码为二进制字节流。[br]
## 成功时 [member Result.value] 为 [PackedByteArray]。
static func encode_texture(texture: Texture2D, format: String = "png", quality: float = 0.85) -> Result:
	if texture == null:
		return Result.err("FileCodecUtils.encode_texture failed: texture is null.")
	var image := texture.get_image()
	if image == null or image.is_empty():
		return Result.err("FileCodecUtils.encode_texture failed: texture has no readable CPU image data.")
	return encode_image(image, format, quality)


## 从二进制字节流还原 [Image]（基于文件头魔数 O(1) 精准分发）。[br]
## 成功时 [member Result.value] 为 [Image]。
static func decode_image(bytes: PackedByteArray) -> Result:
	if bytes.is_empty():
		return Result.err("FileCodecUtils.decode_image failed: bytes are empty.")

	var fmt := _sniff_format(bytes)
	if fmt.is_empty():
		return Result.err("FileCodecUtils.decode_image failed: unrecognized image magic header (size=%d)." % bytes.size())

	var image := Image.new()
	var err: Error = ERR_FILE_UNRECOGNIZED

	match fmt:
		"png":
			err = image.load_png_from_buffer(bytes)
		"jpg":
			err = image.load_jpg_from_buffer(bytes)
		"webp":
			err = image.load_webp_from_buffer(bytes)
		"bmp":
			err = image.load_bmp_from_buffer(bytes)
		"ktx":
			err = image.load_ktx_from_buffer(bytes)
		"svg":
			err = image.load_svg_from_buffer(bytes)

	if err != OK or image.is_empty():
		return Result.err("FileCodecUtils.decode_image failed: corrupted %s buffer (err=%s)." % [fmt, error_string(err)])
	return Result.ok(image)


## 从二进制字节流还原 [ImageTexture]。[br]
## 成功时 [member Result.value] 为 [ImageTexture]（[Texture2D] 子类）。
static func decode_texture(bytes: PackedByteArray) -> Result:
	var img_res := decode_image(bytes)
	if img_res.is_err():
		return img_res
	var tex := ImageTexture.create_from_image(img_res.value as Image)
	if tex == null:
		return Result.err("FileCodecUtils.decode_texture failed: cannot create ImageTexture.")
	return Result.ok(tex)


## 从文件路径还原 [Image]。[br]
## - [code]res://[/code] 路径优先兼容已导入资源（防止导出包内原图被编译为 [code].ctex[/code] 后无法通过 [method Image.load] 读取）；[br]
## - [code]user://[/code] 及外部路径通过字节魔数嗅探解码，不受文件后缀名限制（支持 [code].cache[/code] / 无后缀缓存文件）。
static func decode_image_path(path: String) -> Result:
	if path.is_empty():
		return Result.err("FileCodecUtils.decode_image_path failed: path is empty.")

	if path.begins_with("res://") and ResourceLoader.exists(path):
		var res := ResourceLoader.load(path)
		if res is Image:
			return Result.ok(res)
		if res is Texture2D:
			var img := (res as Texture2D).get_image()
			if img != null and not img.is_empty():
				return Result.ok(img)

	var bytes_res := FileUtils.read_bytes(path)
	if bytes_res.is_err():
		return bytes_res
	return decode_image(bytes_res.value as PackedByteArray)


## 从文件路径还原 [Texture2D]。[br]
## - [code]res://[/code] 路径优先走 [ResourceLoader] 直接获取硬件压缩纹理；[br]
## - [code]user://[/code] 及外部路径读取字节并解码为 [ImageTexture]。
static func decode_texture_path(path: String) -> Result:
	if path.is_empty():
		return Result.err("FileCodecUtils.decode_texture_path failed: path is empty.")

	if path.begins_with("res://") and ResourceLoader.exists(path):
		var res := ResourceLoader.load(path)
		if res is Texture2D:
			return Result.ok(res)
		if res is Image:
			return Result.ok(ImageTexture.create_from_image(res as Image))

	var img_res := decode_image_path(path)
	if img_res.is_err():
		return img_res
	return Result.ok(ImageTexture.create_from_image(img_res.value as Image))

#endregion


#region Internal Magic Sniffing

## 基于文件头字节（Magic Bytes）O(1) 识别图像格式，无法识别时返回空字符串。
static func _sniff_format(bytes: PackedByteArray) -> String:
	var size := bytes.size()
	if size < 2:
		return ""

	# 1. PNG: 89 50 4E 47 0D 0A 1A 0A
	if size >= 8 and bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47:
		return "png"

	# 2. JPEG: FF D8 FF
	if size >= 3 and bytes[0] == 0xFF and bytes[1] == 0xD8 and bytes[2] == 0xFF:
		return "jpg"

	# 3. WebP: "RIFF" (52 49 46 46) ... "WEBP" (57 45 42 50)
	if size >= 12 and bytes[0] == 0x52 and bytes[1] == 0x49 and bytes[2] == 0x46 and bytes[3] == 0x46 \
			and bytes[8] == 0x57 and bytes[9] == 0x45 and bytes[10] == 0x42 and bytes[11] == 0x50:
		return "webp"

	# 4. BMP: "BM" (42 4D)
	if bytes[0] == 0x42 and bytes[1] == 0x4D:
		return "bmp"

	# 5. KTX: AB 4B 54 58
	if size >= 12 and bytes[0] == 0xAB and bytes[1] == 0x4B and bytes[2] == 0x54 and bytes[3] == 0x58:
		return "ktx"

	# 6. SVG: 文本头部含 "<svg" 或 "<?xml"
	if size >= 5 and bytes[0] == 0x3C: # '<'
		var head := bytes.slice(0, mini(size, 256)).get_string_from_utf8().strip_edges().to_lower()
		if head.begins_with("<svg") or (head.begins_with("<?xml") and head.contains("<svg")):
			return "svg"

	return ""

#endregion
