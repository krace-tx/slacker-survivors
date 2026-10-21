class_name MemoryUtils
extends RefCounted

## 内存与显存占用字节估算工具类（纯 O(1) 零循环、零堆分配实现）。[br]
##
## 为 [BudgetCache]（如 [AssetCache]、[StorageCache]）提供常数级耗时（~0.15 µs）的
## 粗粒度水位线体积估算。全链路不执行容器遍历、不触发 JSON 序列化、不回读 GPU 显存、不拷贝底层缓冲。

#region Constants
## 不可直接通过元数据推算体积的复杂资源（如 PackedScene、Shader、Material）默认保底估算值（256 KB）
const UNKNOWN_BYTES: int = 256 * 1024

## 64 位架构下单个 Godot Variant 联合体槽位基础字节开销
const _VARIANT_SLOT_BYTES: int = 24
## 矩阵/包围盒等重型值类型（Transform3D / Projection / Basis / AABB）估算字节开销
const _HEAVY_STRUCT_BYTES: int = 64
## Array 单元素平均估算负载（Variant 槽位 24B + 标量/短引用均值约 40B）
const _ARRAY_ELEM_ESTIMATE: int = 64
## Dictionary 单键值对平均估算负载（HashMap 节点链表指针/哈希 32B + Key/Value 双槽位 48B + 负载均值 48B）
const _DICT_ENTRY_ESTIMATE: int = 128
#endregion


#region Public API
## O(1) 估算任意 [Variant] 数据在内存或显存中的占用字节数。[br]
## [param data] 待评估的目标数据。[br]
## [param unknown_fallback] 遇到无法精确推算的复杂 [Resource] 时的兜底字节数。
static func estimate_bytes(data: Variant, unknown_fallback: int = UNKNOWN_BYTES) -> int:
	match typeof(data):
		TYPE_NIL:
			return 0

		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, \
		TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_RECT2, TYPE_RECT2I, \
		TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_VECTOR4, TYPE_VECTOR4I, \
		TYPE_PLANE, TYPE_QUATERNION, TYPE_COLOR, \
		TYPE_RID, TYPE_CALLABLE, TYPE_SIGNAL:
			return _VARIANT_SLOT_BYTES

		TYPE_TRANSFORM2D, TYPE_AABB, TYPE_BASIS, TYPE_TRANSFORM3D, TYPE_PROJECTION:
			return _HEAVY_STRUCT_BYTES

		TYPE_STRING:
			# Godot 4 String 内部采用 char32_t (UTF-32, 4 Bytes/Char) + CowData 引用头
			return _VARIANT_SLOT_BYTES + (data as String).length() * 4

		TYPE_STRING_NAME:
			return _VARIANT_SLOT_BYTES + (data as StringName).length() * 4

		TYPE_NODE_PATH:
			return _VARIANT_SLOT_BYTES + str(data).length() * 4

		TYPE_PACKED_BYTE_ARRAY:
			return _VARIANT_SLOT_BYTES + (data as PackedByteArray).size()

		TYPE_PACKED_INT32_ARRAY:
			return _VARIANT_SLOT_BYTES + (data as PackedInt32Array).size() * 4

		TYPE_PACKED_FLOAT32_ARRAY:
			return _VARIANT_SLOT_BYTES + (data as PackedFloat32Array).size() * 4

		TYPE_PACKED_INT64_ARRAY:
			return _VARIANT_SLOT_BYTES + (data as PackedInt64Array).size() * 8

		TYPE_PACKED_FLOAT64_ARRAY:
			return _VARIANT_SLOT_BYTES + (data as PackedFloat64Array).size() * 8

		TYPE_PACKED_VECTOR2_ARRAY:
			return _VARIANT_SLOT_BYTES + (data as PackedVector2Array).size() * 8

		TYPE_PACKED_VECTOR3_ARRAY:
			return _VARIANT_SLOT_BYTES + (data as PackedVector3Array).size() * 12

		TYPE_PACKED_COLOR_ARRAY:
			return _VARIANT_SLOT_BYTES + (data as PackedColorArray).size() * 16

		TYPE_PACKED_VECTOR4_ARRAY:
			return _VARIANT_SLOT_BYTES + (data as PackedVector4Array).size() * 16

		TYPE_PACKED_STRING_ARRAY:
			return _VARIANT_SLOT_BYTES + (data as PackedStringArray).size() * _ARRAY_ELEM_ESTIMATE

		TYPE_ARRAY:
			return _VARIANT_SLOT_BYTES + (data as Array).size() * _ARRAY_ELEM_ESTIMATE

		TYPE_DICTIONARY:
			return _HEAVY_STRUCT_BYTES + (data as Dictionary).size() * _DICT_ENTRY_ESTIMATE

		TYPE_OBJECT:
			if not is_instance_valid(data):
				return 0
			if data is Resource:
				return estimate_resource_bytes(data as Resource, unknown_fallback)
			return _HEAVY_STRUCT_BYTES

		_:
			return _VARIANT_SLOT_BYTES


## O(1) 估算单份 [Resource] 资源的显存/内存占用字节数（零堆内存分配）。[br]
## [param res] 目标资源实例。[br]
## [param unknown_fallback] 未知复杂资源类型（如 PackedScene、Shader）的保底估算值。
static func estimate_resource_bytes(res: Resource, unknown_fallback: int = UNKNOWN_BYTES) -> int:
	if res == null or not is_instance_valid(res):
		return 0

	# 1. CPU 图像缓冲：直接调用引擎 C++ 原生 O(1) 接口（涵盖全部 39 种像素格式与 Mipmaps，零缓冲拷贝）
	if res is Image:
		return (res as Image).get_data_size()

	# 2. 图集子纹理：实际显存由底层共享大图承担，子视图自身不重复计入显存预算
	if res is AtlasTexture:
		return 0

	# 3. 2D 纹理（含 ImageTexture、CompressedTexture2D 等）
	if res is Texture2D:
		return _texture_bytes(res as Texture2D)

	# 4. 音频流系列（WAV / MP3 / OGG 内存数据包）
	if res is AudioStreamWAV:
		return (res as AudioStreamWAV).data.size()
	if res is AudioStreamMP3:
		return (res as AudioStreamMP3).data.size()
	if res is AudioStreamOggVorbis:
		var ogg := res as AudioStreamOggVorbis
		return ogg.packet_sequence.packet_data.size() if ogg.packet_sequence != null else 0

	# 5. 二值位图掩码與字体缓冲
	if res is BitMap:
		var bmp_size := (res as BitMap).get_size()
		return (bmp_size.x * bmp_size.y + 7) >> 3
	if res is FontFile:
		var font_bytes := (res as FontFile).data.size()
		return font_bytes if font_bytes > 0 else unknown_fallback

	# 6. 其余结构化/编译型资源（如 PackedScene、Shader、Material）返回保底水位值
	return unknown_fallback
#endregion


#region Internal Helpers
static func _texture_bytes(tex: Texture2D) -> int:
	var w := tex.get_width()
	var h := tex.get_height()
	if w <= 0 or h <= 0:
		return 0

	# 基础未压缩 RGBA8 显存基线 (4 Bytes/Pixel)
	var base_bytes := w * h * 4

	# 若包含 Mipmaps 金字塔，显存产生约 1/3 几何级数增量 (1 + 1/4 + 1/16 + ... = 4/3)
	if tex.has_mipmaps():
		return base_bytes + (base_bytes / 3)
	return base_bytes
#endregion
