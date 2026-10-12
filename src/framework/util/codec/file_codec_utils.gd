class_name FileCodecUtils
extends RefCounted

## 引擎内置类型与二进制载荷的编解码入口。[br]
##
## Storage 只搬运 [PackedByteArray]；调度层先走本工具，再交给 [StorageService]。[br]
## 自定义 Resource ↔ Dictionary 用 [ResourceCodecUtils]，不经过这里。[br]
## [method encode] 按对象运行时类型分发；[method decode] / [method decode_path] 必须传 [enum FileCodecType]。

#region Public API
## 把引擎对象编成二进制。[br]
## [param value] 目前支持 [Image]、[Texture2D] 及其子类。[br]
## [param format] 可选：[code]png[/code]（默认）、[code]jpg[/code]、[code]webp[/code]。[br]
## 成功时 [member Result.value] 为 [PackedByteArray]。
static func encode(value: Variant, format: String = "") -> Result:
	var codec := _codec(_type_of(value))
	if codec == null:
		return Result.err("FileCodecUtils.encode failed: unsupported type.")
	return codec.encode(value, format)


## 把二进制解成引擎对象。[br]
## [param type] 要拿回的类型，如 [code]FileCodecType.TEXTURE_2D[/code]；同一份 png 字节也可解成 [code]FileCodecType.IMAGE[/code]。[br]
## 成功时 [member Result.value] 为对应实例。
static func decode(bytes: PackedByteArray, type: int) -> Result:
	var codec := _codec(type)
	if codec == null:
		return Result.err("FileCodecUtils.decode failed: unsupported type.")
	return codec.decode(bytes)


## 从已落盘的文件解码，避免调用方先整文件读进内存。[br]
## [param path] 如 [code]user://[/code] / [code]res://[/code]；[param type] 同 [method decode]。
static func decode_path(path: String, type: int) -> Result:
	var codec := _codec(type)
	if codec == null:
		return Result.err("FileCodecUtils.decode_path failed: unsupported type.")
	return codec.decode_path(path)
#endregion


#region Internal
## 由对象类型得到 [enum FileCodecType]。
static func _type_of(value: Variant) -> int:
	if value is Image:
		return FileCodecType.IMAGE
	if value is Texture2D:
		return FileCodecType.TEXTURE_2D
	return -1


## 按枚举取出对应 [FileCodec]；未知类型返回 [code]null[/code]。
static func _codec(type: int) -> FileCodec:
	match type:
		FileCodecType.IMAGE:
			return ImageFileCodec.new()
		FileCodecType.TEXTURE_2D:
			return Texture2DFileCodec.new()
		_:
			return null
#endregion
