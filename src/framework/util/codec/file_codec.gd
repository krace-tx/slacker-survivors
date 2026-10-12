@abstract
class_name FileCodec
extends RefCounted

## 一族引擎内置类型的二进制编解码。[br]
##
## 由 [FileCodecUtils] 按 [enum FileCodecType] 分发，调用方不要直接 new 子类。[br]
## 磁盘上是 [PackedByteArray]（如 png / jpg），不是 Godot [code].tres[/code]。[br]
## [method decode_path] 默认先 [method FileUtils.read_bytes] 再 [method decode]；能按路径解码的类型再覆盖。

## 把引擎对象编成二进制。[br]
## [param value] 本 codec 对应的类型；[param format] 容器格式，空则用该类型默认值。[br]
## 成功时 [member Result.value] 为 [PackedByteArray]。
@abstract
func encode(value: Variant, format: String) -> Result


## 把二进制解成本 codec 对应的引擎对象。[br]
## 成功时 [member Result.value] 为对应实例。
@abstract
func decode(bytes: PackedByteArray) -> Result


## 从磁盘路径解码。[br]
## [param path] 如 [code]user://[/code] / [code]res://[/code]。[br]
## 默认读出全部字节后走 [method decode]。
func decode_path(path: String) -> Result:
	if path.is_empty():
		return Result.err("FileCodec.decode_path failed: path is empty.")
	var loaded := FileUtils.read_bytes(path)
	if loaded.is_err():
		return loaded
	return decode(loaded.value)
