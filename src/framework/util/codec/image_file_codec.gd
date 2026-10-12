class_name ImageFileCodec
extends FileCodec

## [Image] 与 png / jpg / webp 字节的编解码。[br]
##
## 默认格式 png。[method decode] 不看扩展名，按缓冲依次试 png、jpg、webp。[br]
## [method decode_path] 走 [method Image.load]，由引擎按路径识别格式。

## 把 [Image] 编成字节。[br]
## [param format]：[code]png[/code]（默认）、[code]jpg[/code] / [code]jpeg[/code]、[code]webp[/code]。[br]
## 成功时 [member Result.value] 为 [PackedByteArray]。
func encode(value: Variant, format: String) -> Result:
	if not value is Image:
		return Result.err("ImageFileCodec.encode failed: value is not Image.")
	var image := value as Image
	if image.is_empty():
		return Result.err("ImageFileCodec.encode failed: image is empty.")

	var fmt := format.strip_edges().to_lower()
	if fmt.is_empty():
		fmt = "png"

	var bytes := PackedByteArray()
	match fmt:
		"png":
			bytes = image.save_png_to_buffer()
		"jpg", "jpeg":
			bytes = image.save_jpg_to_buffer()
		"webp":
			bytes = image.save_webp_to_buffer()
		_:
			return Result.err("ImageFileCodec.encode failed: unsupported format (%s)." % fmt)

	if bytes.is_empty():
		return Result.err("ImageFileCodec.encode failed: encode returned empty.")
	return Result.ok(bytes)


## 从字节还原 [Image]。成功时 [member Result.value] 为 [Image]。
func decode(bytes: PackedByteArray) -> Result:
	if bytes.is_empty():
		return Result.err("ImageFileCodec.decode failed: bytes are empty.")

	var image := Image.new()
	var err := image.load_png_from_buffer(bytes)
	if err != OK:
		err = image.load_jpg_from_buffer(bytes)
	if err != OK:
		err = image.load_webp_from_buffer(bytes)
	if err != OK:
		return Result.err("ImageFileCodec.decode failed: unrecognized image buffer.")
	return Result.ok(image)


## 从路径还原 [Image]，不先把整文件读进 [PackedByteArray]。[br]
## [param path] 如 [code]user://[/code] / [code]res://[/code]。
func decode_path(path: String) -> Result:
	if path.is_empty():
		return Result.err("ImageFileCodec.decode_path failed: path is empty.")

	var image := Image.new()
	var err := image.load(path)
	if err != OK:
		return Result.err("ImageFileCodec.decode_path failed: cannot load '%s' (err=%s)." % [path, error_string(err)])
	return Result.ok(image)
