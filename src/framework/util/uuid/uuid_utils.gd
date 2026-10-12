class_name UuidUtils
extends RefCounted

## UUID 生成与短码互转。
##
## 生成 RFC 4122 UUID v4；也可把 UUID 无损编码为 22 字符的 base64url 短码（URL 安全、无填充），再还原。
## 随机源为 [Crypto]，纯无状态，不依赖场景树或单例。

#region Constants & Enums
const _UUID_BYTE_COUNT: int = 16
const _HEX_CHAR_COUNT: int = 32
const _SHORT_CODE_LENGTH: int = 22

# RFC 4122 §4.4：第 7 字节高 4 位 = 0100（v4），第 9 字节高 2 位 = 10（variant）。
const _VERSION_BYTE_INDEX: int = 6
const _VARIANT_BYTE_INDEX: int = 8

# 标准 UUID 文本分组：8-4-4-4-12。
const _SEGMENT_LENGTHS: Array[int] = [8, 4, 4, 4, 12]

# RFC 4648 §5：URL 安全字符集。16 字节编码后为 22 字符，补 "==" 才能走标准 base64 解码。
const _BASE64URL_ALPHABET: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
const _BASE64_PADDING: String = "=="
#endregion

#region Public API
## 生成随机 UUID v4，返回小写带连字符的 36 字符标准字符串。[br]
## 形如 [code]f47ac10b-58cc-4372-a567-0e02b2c3d479[/code]。
static func v4() -> String:
	var crypto := Crypto.new()
	var bytes := crypto.generate_random_bytes(_UUID_BYTE_COUNT)
	_apply_v4_bits(bytes)
	return _bytes_to_uuid(bytes)


## 将 UUID 编码为 22 字符 base64url 短码。[br]
## 例：[code]550e8400-e29b-41d4-a716-446655440000[/code] → [code]VQ6EAOKbQdSnFkRmVUQAAA[/code]。[br]
## [param uuid] 去掉连字符后不是 32 位十六进制时返回失败。
static func to_short_code(uuid: String) -> Result:
	var hex := uuid.replace("-", "")
	if hex.length() != _HEX_CHAR_COUNT or not hex.is_valid_hex_number(false):
		return Result.err("Invalid UUID: %s." % uuid)
	var b64 := Marshalls.raw_to_base64(_hex_to_bytes(hex))
	return Result.ok(_to_base64url(b64))


## 将 [method to_short_code] 的短码还原为标准 UUID。[br]
## [param code] 长度/字符集非法，或解码后不是 16 字节时返回失败。
static func from_short_code(code: String) -> Result:
	if not _is_valid_short_code(code):
		return Result.err("Invalid short code: %s." % code)
	var b64 := code.replace("-", "+").replace("_", "/") + _BASE64_PADDING
	var bytes := Marshalls.base64_to_raw(b64)
	if bytes.size() != _UUID_BYTE_COUNT:
		return Result.err("Short code decoded to unexpected size: %s." % code)
	return Result.ok(_bytes_to_uuid(bytes))
#endregion

#region Internal
static func _apply_v4_bits(bytes: PackedByteArray) -> void:
	bytes[_VERSION_BYTE_INDEX] = (bytes[_VERSION_BYTE_INDEX] & 0x0F) | 0x40
	bytes[_VARIANT_BYTE_INDEX] = (bytes[_VARIANT_BYTE_INDEX] & 0x3F) | 0x80


static func _bytes_to_uuid(bytes: PackedByteArray) -> String:
	var hex := bytes.hex_encode()
	var segments := PackedStringArray()
	var cursor := 0
	for length in _SEGMENT_LENGTHS:
		segments.append(hex.substr(cursor, length))
		cursor += length
	return "-".join(segments)


static func _hex_to_bytes(hex: String) -> PackedByteArray:
	var bytes := PackedByteArray()
	var cursor := 0
	while cursor < hex.length():
		bytes.append(hex.substr(cursor, 2).hex_to_int())
		cursor += 2
	return bytes


static func _to_base64url(standard_b64: String) -> String:
	return standard_b64.replace("+", "-").replace("/", "_").rstrip("=")


static func _is_valid_short_code(code: String) -> bool:
	if code.length() != _SHORT_CODE_LENGTH:
		return false
	for ch in code:
		if _BASE64URL_ALPHABET.find(ch) == -1:
			return false
	return true
#endregion
