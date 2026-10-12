class_name Texture2DFileCodec
extends FileCodec

## [Texture2D] 与 png / jpg / webp 字节的编解码。[br]
##
## 磁盘格式与 [ImageFileCodec] 相同：先编/解 [Image]，再 [method ImageTexture.create_from_image]。[br]
## 部分压缩纹理 [method Texture2D.get_image] 为空，[method encode] 会失败。

## 把 [Texture2D] 编成字节。[br]
## [param format] 同 [method ImageFileCodec.encode]，默认 png。[br]
## 成功时 [member Result.value] 为 [PackedByteArray]。
func encode(value: Variant, format: String) -> Result:
	if not value is Texture2D:
		return Result.err("Texture2DFileCodec.encode failed: value is not Texture2D.")
	var image := (value as Texture2D).get_image()
	if image == null or image.is_empty():
		return Result.err("Texture2DFileCodec.encode failed: texture has no image data.")
	return ImageFileCodec.new().encode(image, format)


## 从字节还原 [ImageTexture]。成功时 [member Result.value] 为 [Texture2D]。
func decode(bytes: PackedByteArray) -> Result:
	var decoded := ImageFileCodec.new().decode(bytes)
	if decoded.is_err():
		return decoded
	return Result.ok(ImageTexture.create_from_image(decoded.value as Image))


## 从路径还原 [ImageTexture]。[param path] 同 [method ImageFileCodec.decode_path]。
func decode_path(path: String) -> Result:
	var decoded := ImageFileCodec.new().decode_path(path)
	if decoded.is_err():
		return decoded
	return Result.ok(ImageTexture.create_from_image(decoded.value as Image))
