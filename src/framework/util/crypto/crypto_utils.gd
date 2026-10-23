class_name CryptoUtils
extends RefCounted

## 工业级无状态密码学、认证加密（AEAD 级防篡改）、消息签名与内存压缩纯函数工具类。[br]
##
## [b]核心设计（第一性原理）：[/b][br]
## 1. [b]纯内存无状态原语（Zero-State Pure Functions）[/b]：与磁盘 I/O（[FileUtils]）完全正交解耦，专职处理内存态 [PackedByteArray] / [String] / [Dictionary] 的加解密与摘要计算；[br]
## 2. [b]Encrypt-then-MAC 认证加密信封（Authenticated Encryption）[/b]：采用 [code]AES-256-CBC + PKCS#7 Padding + 16B 随机 IV + HMAC-SHA256[/code] 组合信封（魔数 [code]FWKE[/code]），
##    任何 1 比特密文篡改或错误密钥均在解密前被恒定时间签名比对 100% 拦截，彻底杜绝 Padding Oracle 与乱码脏数据解析；[br]
## 3. [b]精确帧头内存压缩（Framed ZSTD Compression）[/b]：内置携带 8 字节原始长度头的 [code]FWKZ[/code] 压缩帧封装，支持 $O(1)$ 精确缓冲预分配解压，打通「先压缩、后加密」的正交数据管线；[br]
## 4. [b]设备指纹密钥派生（Device-Bound Key Derivation）[/b]：支持混入应用盐值与硬件唯一标识（[method OS.get_unique_id]）进行双轮 HMAC-SHA256 密钥派生，防御跨设备拷贝替档。


#region Constants & Error Codes

const CIPHER_MAGIC: String = "FWKE" ## 认证加密二进制信封魔数（Framework Encrypted，4 字节）。
const COMPRESS_MAGIC: String = "FWKZ" ## 内存压缩帧二进制魔数（Framework ZSTD，4 字节）。

const AES_KEY_SIZE: int = 32 ## AES-256 标准密钥长度（32 字节 / 256 位）。
const AES_BLOCK_SIZE: int = 16 ## AES 分组块与 CBC IV 长度（16 字节 / 128 位）。
const HMAC_SHA256_SIZE: int = 32 ## HMAC-SHA256 摘要长度（32 字节 / 256 位）。

const _CIPHER_HEADER_SIZE: int = 4 + AES_BLOCK_SIZE ## 4B Magic + 16B IV = 20 字节。
const _CIPHER_MIN_SIZE: int = _CIPHER_HEADER_SIZE + AES_BLOCK_SIZE + HMAC_SHA256_SIZE ## 最小合法密文长度（68 字节）。
const _COMPRESS_HEADER_SIZE: int = 13 ## 4B Magic + 1B Mode + 8B OriginalSize = 13 字节。
const _MAX_DECOMPRESS_BYTES: int = 256 * 1024 * 1024 ## 单次内存解压安全上限（256 MB，防 Zip Bomb 内存耗尽攻击）。
const _KDF_DEFAULT_SALT: String = "framework_kdf_v1"

const ERR_EMPTY_KEY: String = "Crypto.EmptyKey"
const ERR_INVALID_PARAM: String = "Crypto.InvalidParam"
const ERR_ENCRYPT_FAILED: String = "Crypto.EncryptFailed"
const ERR_DECRYPT_FAILED: String = "Crypto.DecryptFailed"
const ERR_TAMPERED: String = "Crypto.Tampered"
const ERR_SIGNATURE_MISMATCH: String = "Crypto.SignatureMismatch"
const ERR_COMPRESS_FAILED: String = "Crypto.CompressFailed"
const ERR_DECOMPRESS_FAILED: String = "Crypto.DecompressFailed"

#endregion


#region Public API - Hashing, HMAC & Constant-Time Verification

## 计算二进制或文本数据的 16 字节原始 MD5 摘要。
static func md5_bytes(data: Variant) -> PackedByteArray:
	var raw := _to_bytes(data)
	if raw.is_empty():
		return "".md5_buffer()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(raw)
	return ctx.finish()


## 计算二进制或文本数据的 32 位小写十六进制 MD5 摘要。
static func md5_hex(data: Variant) -> String:
	return md5_bytes(data).hex_encode()


## 计算二进制或文本数据的 32 字节原始 SHA-256 摘要。
static func sha256_bytes(data: Variant) -> PackedByteArray:
	var raw := _to_bytes(data)
	if raw.is_empty():
		return "".sha256_buffer()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(raw)
	return ctx.finish()


## 计算二进制或文本数据的 64 位小写十六进制 SHA-256 摘要。
static func sha256_hex(data: Variant) -> String:
	return sha256_bytes(data).hex_encode()


## 计算基于 SHA-256 的 HMAC 消息认证码（返回 32 字节 [PackedByteArray]）。[br]
## [param key] 签名密钥（支持 [String] 或 [PackedByteArray]，不可为空）。[br]
## [param data] 待签名负载（支持 [String] 或 [PackedByteArray]，允许为空负载）。
static func hmac_sha256(key: Variant, data: Variant) -> Result:
	var key_bytes := _to_bytes(key)
	if key_bytes.is_empty():
		return Result.err_ex(
			ERR_EMPTY_KEY,
			"HMAC-SHA256 failed: key cannot be empty.",
			{},
			false,
			null,
			FrameworkError.CATEGORY_PARAM
		)

	var msg_bytes := _to_bytes(data)
	var digest := _compute_hmac_sha256_raw(key_bytes, msg_bytes)
	if digest.size() != HMAC_SHA256_SIZE:
		return Result.err_ex(
			ERR_INVALID_PARAM,
			"HMAC-SHA256 failed: unexpected digest length (%d)." % digest.size(),
			{},
			false,
			null,
			FrameworkError.CATEGORY_VALIDATION
		)
	return Result.ok(digest)


## 计算基于 SHA-256 的 64 位小写十六进制 HMAC 签名字符串。[br]
## 成功时 [member Result.value] 为 [String]。
static func hmac_sha256_hex(key: Variant, data: Variant) -> Result:
	var res := hmac_sha256(key, data)
	if res.is_err():
		return res
	var digest: PackedByteArray = res.value as PackedByteArray
	return Result.ok(digest.hex_encode())


## 恒定时间校验数据的 HMAC-SHA256 十六进制签名是否匹配（防御时序侧信道攻击）。[br]
## 成功时返回 [code]Result.ok(true)[/code]；不匹配时返回携带 [constant ERR_SIGNATURE_MISMATCH] 的失败结果。
static func verify_hmac_sha256(key: Variant, data: Variant, expected_hex: String) -> Result:
	var clean_expected := expected_hex.strip_edges().to_lower()
	if clean_expected.length() != HMAC_SHA256_SIZE * 2 or not clean_expected.is_valid_hex_number(false):
		return Result.err_ex(
			ERR_SIGNATURE_MISMATCH,
			"HMAC verification failed: expected signature is not a valid 64-char hex string.",
			{},
			false,
			null,
			FrameworkError.CATEGORY_VALIDATION
		)

	var mac_res := hmac_sha256(key, data)
	if mac_res.is_err():
		return mac_res

	var actual_bytes: PackedByteArray = mac_res.value as PackedByteArray
	var expected_bytes := clean_expected.hex_decode()
	if not constant_time_compare(actual_bytes, expected_bytes):
		return Result.err_ex(
			ERR_SIGNATURE_MISMATCH,
			"HMAC signature mismatch: data may have been tampered with.",
			{},
			false,
			ERR_FILE_CORRUPT,
			FrameworkError.CATEGORY_VALIDATION
		)

	return Result.ok(true)


## 恒定时间字节数组相等性比对（防时序分析攻击）。
static func constant_time_compare(trusted: PackedByteArray, received: PackedByteArray) -> bool:
	if trusted.size() != received.size():
		return false
	if trusted.is_empty():
		return true
	var crypto := Crypto.new()
	return crypto.constant_time_compare(trusted, received)


## 生成指定字节数的密码学安全随机字节流（CSPRNG）。
static func random_bytes(byte_count: int = 16) -> PackedByteArray:
	if byte_count <= 0:
		return PackedByteArray()
	var crypto := Crypto.new()
	return crypto.generate_random_bytes(byte_count)


## 生成指定随机字节数对应的十六进制随机字符串（如 [code]byte_count = 16[/code] 返回 32 字符 hex）。
static func random_hex(byte_count: int = 16) -> String:
	return random_bytes(byte_count).hex_encode()

#endregion


#region Public API - Key Derivation & Request Signing

## 从口令与盐值派生标准 32 字节（256-bit）密钥。[br]
## [param passphrase] 主口令或应用密钥（不可为空）。[br]
## [param salt] 可选领域盐值（如存档 `key_id` 或模块名）。[br]
## [param bind_device] 若设为 [code]true[/code]，自动混入当前设备硬件唯一指纹（[method OS.get_unique_id]），
##                     使加密存档仅能在当前机器解密，阻止跨设备拷贝替档。
static func derive_key_bytes(
	passphrase: String,
	salt: String = "",
	bind_device: bool = false
) -> Result:
	var clean_pass := passphrase.strip_edges()
	if clean_pass.is_empty():
		return Result.err_ex(
			ERR_EMPTY_KEY,
			"Key derivation failed: passphrase cannot be empty.",
			{},
			false,
			null,
			FrameworkError.CATEGORY_PARAM
		)

	var effective_salt := _KDF_DEFAULT_SALT + ":" + salt.strip_edges()
	if bind_device:
		var device_id := OS.get_unique_id().strip_edges()
		effective_salt += ":dev=" + (device_id if not device_id.is_empty() else OS.get_name())

	var round1 := _compute_hmac_sha256_raw(effective_salt.to_utf8_buffer(), clean_pass.to_utf8_buffer())
	var round2 := _compute_hmac_sha256_raw(round1, (clean_pass + ":" + effective_salt).to_utf8_buffer())
	return Result.ok(round2)


## 派生 64 位小写十六进制密钥口令字符串（可直接传入 [method StorageItem.with_encryption] 或 [method FileUtils.write_encrypted]）。
static func derive_passphrase(
	passphrase: String,
	salt: String = "",
	bind_device: bool = false
) -> String:
	var res := derive_key_bytes(passphrase, salt, bind_device)
	if res.is_err():
		return ""
	var key_bytes: PackedByteArray = res.value as PackedByteArray
	return key_bytes.hex_encode()


## 为 HTTP 网络请求生成防篡改、防重放的规范化 HMAC-SHA256 签名。[br]
## 规范化签名原文格式：[code]"{METHOD}\n{PATH_OR_URL}\n{TIMESTAMP_MS}\n{NONCE}\n{BODY_SHA256}"[/code]。[br]
## 成功时 [member Result.value] 为包含 [code]signature[/code]、[code]timestamp[/code]、[code]nonce[/code]、[code]content_sha256[/code] 的字典。
static func sign_http_request(
	secret: String,
	method: String,
	path_or_url: String,
	body_payload: Variant = "",
	timestamp_ms: int = -1,
	nonce: String = ""
) -> Result:
	var clean_secret := secret.strip_edges()
	if clean_secret.is_empty():
		return Result.err_ex(
			ERR_EMPTY_KEY,
			"HTTP request signing failed: secret cannot be empty.",
			{},
			false,
			null,
			FrameworkError.CATEGORY_PARAM
		)

	var ts := timestamp_ms if timestamp_ms >= 0 else int(Time.get_unix_time_from_system() * 1000.0)
	var final_nonce := nonce.strip_edges() if not nonce.strip_edges().is_empty() else random_hex(12)
	var body_hash := sha256_hex(body_payload)
	var canonical := "%s\n%s\n%d\n%s\n%s" % [
		method.strip_edges().to_upper(),
		path_or_url.strip_edges(),
		ts,
		final_nonce,
		body_hash,
	]

	var sig_res := hmac_sha256_hex(clean_secret, canonical)
	if sig_res.is_err():
		return sig_res

	var sig_hex: String = sig_res.value as String
	return Result.ok({
		"signature": sig_hex,
		"timestamp": str(ts),
		"nonce": final_nonce,
		"content_sha256": body_hash,
	})

#endregion


#region Public API - AES-256-CBC Authenticated Encryption (Encrypt-then-MAC)

## 使用 AES-256-CBC + PKCS#7 + 随机 IV + HMAC-SHA256 将内存字节流加密为防篡改密文信封。[br]
## [b]信封二进制布局：[/b][code][4B Magic "FWKE"][16B Random IV][N*16B AES-256-CBC Ciphertext][32B HMAC-SHA256][/code]。[br]
## 成功时 [member Result.value] 为加密后的 [PackedByteArray]。
static func encrypt_bytes(plain_bytes: PackedByteArray, passphrase: String) -> Result:
	var clean_pass := passphrase.strip_edges()
	if clean_pass.is_empty():
		return Result.err_ex(
			ERR_EMPTY_KEY,
			"AES-256 encrypt failed: passphrase cannot be empty.",
			{},
			false,
			null,
			FrameworkError.CATEGORY_PARAM
		)

	var enc_key := _derive_subkey(clean_pass, "aes_enc")
	var mac_key := _derive_subkey(clean_pass, "hmac_auth")
	var iv := random_bytes(AES_BLOCK_SIZE)
	var padded := _pkcs7_pad(plain_bytes, AES_BLOCK_SIZE)

	var aes := AESContext.new()
	var start_err := aes.start(AESContext.MODE_CBC_ENCRYPT, enc_key, iv)
	if start_err != OK:
		return Result.err_ex(
			ERR_ENCRYPT_FAILED,
			"AES-256 encrypt failed: AESContext.start returned %d." % start_err,
			{"engine_error": start_err},
			false,
			start_err,
			FrameworkError.CATEGORY_IO
		)

	var cipher_body := aes.update(padded)
	aes.finish()

	if cipher_body.size() != padded.size():
		return Result.err_ex(
			ERR_ENCRYPT_FAILED,
			"AES-256 encrypt failed: incomplete cipher output (%d/%d bytes)." % [cipher_body.size(), padded.size()],
			{},
			false,
			null,
			FrameworkError.CATEGORY_VALIDATION
		)

	var envelope := PackedByteArray()
	envelope.append_array(CIPHER_MAGIC.to_ascii_buffer())
	envelope.append_array(iv)
	envelope.append_array(cipher_body)

	var mac := _compute_hmac_sha256_raw(mac_key, envelope)
	envelope.append_array(mac)
	return Result.ok(envelope)


## 验证并解密由 [method encrypt_bytes] 生成的 AES-256-CBC 密文信封。[br]
## 先以恒定时间验证尾部 32 字节 HMAC-SHA256 签名，通过后再执行 AES-256-CBC 解密与 PKCS#7 填充剥离。[br]
## 成功时 [member Result.value] 为还原后的明文 [PackedByteArray]。
static func decrypt_bytes(cipher_bytes: PackedByteArray, passphrase: String) -> Result:
	var clean_pass := passphrase.strip_edges()
	if clean_pass.is_empty():
		return Result.err_ex(
			ERR_EMPTY_KEY,
			"AES-256 decrypt failed: passphrase cannot be empty.",
			{},
			false,
			null,
			FrameworkError.CATEGORY_PARAM
		)

	var total_size := cipher_bytes.size()
	if total_size < _CIPHER_MIN_SIZE:
		return Result.err_ex(
			ERR_DECRYPT_FAILED,
			"AES-256 decrypt failed: cipher buffer too short (%d bytes, min %d)." % [total_size, _CIPHER_MIN_SIZE],
			{"size": total_size},
			false,
			ERR_FILE_CORRUPT,
			FrameworkError.CATEGORY_VALIDATION
		)

	var magic_str := cipher_bytes.slice(0, 4).get_string_from_ascii()
	if magic_str != CIPHER_MAGIC:
		return Result.err_ex(
			ERR_DECRYPT_FAILED,
			"AES-256 decrypt failed: unrecognized cipher magic header.",
			{},
			false,
			ERR_FILE_UNRECOGNIZED,
			FrameworkError.CATEGORY_VALIDATION
		)

	var mac_offset := total_size - HMAC_SHA256_SIZE
	var cipher_payload_len := mac_offset - _CIPHER_HEADER_SIZE
	if cipher_payload_len <= 0 or (cipher_payload_len % AES_BLOCK_SIZE) != 0:
		return Result.err_ex(
			ERR_DECRYPT_FAILED,
			"AES-256 decrypt failed: unaligned cipher block length (%d)." % cipher_payload_len,
			{"cipher_payload_len": cipher_payload_len},
			false,
			ERR_FILE_CORRUPT,
			FrameworkError.CATEGORY_VALIDATION
		)

	var enc_key := _derive_subkey(clean_pass, "aes_enc")
	var mac_key := _derive_subkey(clean_pass, "hmac_auth")

	var signed_portion := cipher_bytes.slice(0, mac_offset)
	var received_mac := cipher_bytes.slice(mac_offset, total_size)
	var expected_mac := _compute_hmac_sha256_raw(mac_key, signed_portion)

	if not constant_time_compare(expected_mac, received_mac):
		return Result.err_ex(
			ERR_TAMPERED,
			"AES-256 decrypt failed: HMAC authentication failed (wrong key or tampered ciphertext).",
			{},
			false,
			ERR_FILE_CORRUPT,
			FrameworkError.CATEGORY_VALIDATION
		)

	var iv := cipher_bytes.slice(4, _CIPHER_HEADER_SIZE)
	var cipher_body := cipher_bytes.slice(_CIPHER_HEADER_SIZE, mac_offset)

	var aes := AESContext.new()
	var start_err := aes.start(AESContext.MODE_CBC_DECRYPT, enc_key, iv)
	if start_err != OK:
		return Result.err_ex(
			ERR_DECRYPT_FAILED,
			"AES-256 decrypt failed: AESContext.start returned %d." % start_err,
			{"engine_error": start_err},
			false,
			start_err,
			FrameworkError.CATEGORY_IO
		)

	var padded_plain := aes.update(cipher_body)
	aes.finish()

	return _pkcs7_unpad(padded_plain, AES_BLOCK_SIZE)


## 将 UTF-8 文本加密并编码为 Base64 字符串。[br]
## 成功时 [member Result.value] 为 Base64 [String]。
static func encrypt_text(plain_text: String, passphrase: String) -> Result:
	var enc_res := encrypt_bytes(plain_text.to_utf8_buffer(), passphrase)
	if enc_res.is_err():
		return enc_res
	var cipher_bytes: PackedByteArray = enc_res.value as PackedByteArray
	return Result.ok(Marshalls.raw_to_base64(cipher_bytes))


## 从 Base64 密文字符串解密还原 UTF-8 文本。[br]
## 成功时 [member Result.value] 为还原后的 [String]。
static func decrypt_text(cipher_base64: String, passphrase: String) -> Result:
	var clean_b64 := cipher_base64.strip_edges()
	if clean_b64.is_empty():
		return Result.err_ex(
			ERR_INVALID_PARAM,
			"Decrypt text failed: cipher_base64 cannot be empty.",
			{},
			false,
			null,
			FrameworkError.CATEGORY_PARAM
		)

	var cipher_bytes := Marshalls.base64_to_raw(clean_b64)
	if cipher_bytes.is_empty():
		return Result.err_ex(
			ERR_DECRYPT_FAILED,
			"Decrypt text failed: invalid base64 input.",
			{},
			false,
			ERR_PARSE_ERROR,
			FrameworkError.CATEGORY_VALIDATION
		)

	var dec_res := decrypt_bytes(cipher_bytes, passphrase)
	if dec_res.is_err():
		return dec_res
	var plain_bytes: PackedByteArray = dec_res.value as PackedByteArray
	return Result.ok(plain_bytes.get_string_from_utf8())


## 判断二进制字节流是否携带 [constant CIPHER_MAGIC]（[code]"FWKE"[/code]）认证加密信封头。
static func is_encrypted_envelope(bytes: PackedByteArray) -> bool:
	if bytes.size() < _CIPHER_MIN_SIZE:
		return false
	return bytes.slice(0, 4).get_string_from_ascii() == CIPHER_MAGIC

#endregion


#region Public API - Framed Memory Compression (ZSTD)

## 将内存字节流压缩并封装为携带精确原始长度头的 [code]FWKZ[/code] 压缩帧。[br]
## [b]二进制布局：[/b][code][4B Magic "FWKZ"][1B Mode][8B UncompressedSize (int64 LE)][CompressedBytes][/code]。[br]
## 成功时 [member Result.value] 为压缩后的 [PackedByteArray]。
static func compress_bytes(
	raw_bytes: PackedByteArray,
	compression_mode: FileAccess.CompressionMode = FileAccess.COMPRESSION_ZSTD
) -> Result:
	var orig_size := raw_bytes.size()
	var comp_body := PackedByteArray()
	if orig_size > 0:
		comp_body = raw_bytes.compress(compression_mode)
		if comp_body.is_empty():
			return Result.err_ex(
				ERR_COMPRESS_FAILED,
				"Memory compress failed: PackedByteArray.compress returned empty for %d bytes." % orig_size,
				{"original_size": orig_size, "mode": compression_mode},
				false,
				null,
				FrameworkError.CATEGORY_IO
			)

	var header := PackedByteArray()
	header.resize(_COMPRESS_HEADER_SIZE)
	var magic_bytes := COMPRESS_MAGIC.to_ascii_buffer()
	for i in 4:
		header[i] = magic_bytes[i]
	header.encode_u8(4, int(compression_mode) & 0xFF)
	header.encode_s64(5, orig_size)

	header.append_array(comp_body)
	return Result.ok(header)


## 从 [method compress_bytes] 生成的 [code]FWKZ[/code] 压缩帧中 $O(1)$ 精确解压还原原始字节流。[br]
## 成功时 [member Result.value] 为解压后的 [PackedByteArray]。
static func decompress_bytes(framed_bytes: PackedByteArray) -> Result:
	if not is_compressed_frame(framed_bytes):
		return Result.err_ex(
			ERR_DECOMPRESS_FAILED,
			"Memory decompress failed: missing 'FWKZ' frame header.",
			{"size": framed_bytes.size()},
			false,
			ERR_FILE_UNRECOGNIZED,
			FrameworkError.CATEGORY_VALIDATION
		)

	var mode := framed_bytes.decode_u8(4) as FileAccess.CompressionMode
	var orig_size := framed_bytes.decode_s64(5)
	if orig_size < 0 or orig_size > _MAX_DECOMPRESS_BYTES:
		return Result.err_ex(
			ERR_DECOMPRESS_FAILED,
			"Memory decompress failed: invalid or excessive uncompressed size (%d)." % orig_size,
			{"original_size": orig_size},
			false,
			ERR_FILE_CORRUPT,
			FrameworkError.CATEGORY_VALIDATION
		)

	if orig_size == 0:
		return Result.ok(PackedByteArray())

	var comp_body := framed_bytes.slice(_COMPRESS_HEADER_SIZE, framed_bytes.size())
	if comp_body.is_empty():
		return Result.err_ex(
			ERR_DECOMPRESS_FAILED,
			"Memory decompress failed: compressed payload is empty (expected %d uncompressed bytes)." % orig_size,
			{"original_size": orig_size},
			false,
			ERR_FILE_CORRUPT,
			FrameworkError.CATEGORY_VALIDATION
		)

	var decompressed := comp_body.decompress(orig_size, mode)
	if decompressed.size() != orig_size:
		return Result.err_ex(
			ERR_DECOMPRESS_FAILED,
			"Memory decompress failed: corrupted ZSTD stream (got %d/%d bytes)." % [decompressed.size(), orig_size],
			{"expected_size": orig_size, "actual_size": decompressed.size()},
			false,
			ERR_FILE_CORRUPT,
			FrameworkError.CATEGORY_VALIDATION
		)

	return Result.ok(decompressed)


## 判断字节流是否携带 [constant COMPRESS_MAGIC]（[code]"FWKZ"[/code]）内存压缩帧头。
static func is_compressed_frame(bytes: PackedByteArray) -> bool:
	if bytes.size() < _COMPRESS_HEADER_SIZE:
		return false
	return bytes.slice(0, 4).get_string_from_ascii() == COMPRESS_MAGIC

#endregion


#region Internal Cryptographic Helpers

static func _to_bytes(data: Variant) -> PackedByteArray:
	if data is PackedByteArray:
		return data as PackedByteArray
	if data is String or data is StringName:
		return String(data).to_utf8_buffer()
	if data == null:
		return PackedByteArray()
	return str(data).to_utf8_buffer()


static func _derive_subkey(passphrase: String, purpose: String) -> PackedByteArray:
	return _compute_hmac_sha256_raw(
		("framework_subkey:" + purpose).to_utf8_buffer(),
		passphrase.to_utf8_buffer()
	)


## 兼容任意长度消息（含 0 字节空负载）的标准 RFC 2104 HMAC-SHA256 实现。
static func _compute_hmac_sha256_raw(key_bytes: PackedByteArray, msg_bytes: PackedByteArray) -> PackedByteArray:
	if not key_bytes.is_empty() and not msg_bytes.is_empty():
		var crypto := Crypto.new()
		var fast_mac := crypto.hmac_digest(HashingContext.HASH_SHA256, key_bytes, msg_bytes)
		if fast_mac.size() == HMAC_SHA256_SIZE:
			return fast_mac

	# 当 msg_bytes 为空或回退时，按 RFC 2104 标准块大小（64 字节）执行
	const BLOCK_LEN: int = 64
	var norm_key := key_bytes
	if norm_key.size() > BLOCK_LEN:
		norm_key = sha256_bytes(norm_key)

	var o_key_pad := PackedByteArray()
	var i_key_pad := PackedByteArray()
	o_key_pad.resize(BLOCK_LEN)
	i_key_pad.resize(BLOCK_LEN)

	for i in BLOCK_LEN:
		var k_byte: int = norm_key[i] if i < norm_key.size() else 0
		o_key_pad[i] = k_byte ^ 0x5C
		i_key_pad[i] = k_byte ^ 0x36

	i_key_pad.append_array(msg_bytes)
	var inner_hash := sha256_bytes(i_key_pad)
	o_key_pad.append_array(inner_hash)
	return sha256_bytes(o_key_pad)


static func _pkcs7_pad(data: PackedByteArray, block_size: int) -> PackedByteArray:
	var pad_len := block_size - (data.size() % block_size)
	if pad_len <= 0:
		pad_len = block_size
	var out := data.duplicate()
	var old_size := out.size()
	out.resize(old_size + pad_len)
	for i in range(old_size, old_size + pad_len):
		out[i] = pad_len
	return out


static func _pkcs7_unpad(padded: PackedByteArray, block_size: int) -> Result:
	var total := padded.size()
	if total == 0 or (total % block_size) != 0:
		return Result.err_ex(
			ERR_DECRYPT_FAILED,
			"PKCS#7 unpad failed: invalid buffer size (%d)." % total,
			{"size": total},
			false,
			ERR_FILE_CORRUPT,
			FrameworkError.CATEGORY_VALIDATION
		)

	var pad_len: int = padded[total - 1]
	if pad_len < 1 or pad_len > block_size or pad_len > total:
		return Result.err_ex(
			ERR_DECRYPT_FAILED,
			"PKCS#7 unpad failed: invalid padding byte (%d)." % pad_len,
			{"pad_len": pad_len},
			false,
			ERR_FILE_CORRUPT,
			FrameworkError.CATEGORY_VALIDATION
		)

	# 恒定形态遍历全部填充字节，避免提前分支泄露填充长度信息
	var bad_pad: int = 0
	for i in range(total - pad_len, total):
		bad_pad |= (padded[i] ^ pad_len)

	if bad_pad != 0:
		return Result.err_ex(
			ERR_DECRYPT_FAILED,
			"PKCS#7 unpad failed: corrupted padding bytes.",
			{},
			false,
			ERR_FILE_CORRUPT,
			FrameworkError.CATEGORY_VALIDATION
		)

	return Result.ok(padded.slice(0, total - pad_len))

#endregion
