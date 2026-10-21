class_name ResourceCodecUtils
extends RefCounted

## 自定义 [Resource] 与 [Dictionary] 的递归编解码与深拷贝工具类。[br]
##
## [b]核心设计（第一性原理）：[/b][br]
## 1. [b]预编译属性模具缓存（Pre-compiled Schema Cache）[/b]：每个 [Script] 全生命周期仅反射解析 1 次属性列表，
##    后续所有实例的 [method encode] / [method decode] / [method clone] 均走 O(1) 哈希查表，消除重复跨界反射开销；[br]
## 2. [b]零配置无限层级嵌套推导[/b]：利用属性静态类型与 Godot 4.7 容器原生自省（[method Array.get_typed_script]、
##    [method Dictionary.get_typed_value_script]），自顶向下直接传递 [Script] 模具，自动还原全局类、内部类（Inner Class）、
##    [code]Array[T][/code]、[code]Dictionary[K, V][/code] 及引擎内置结构体，彻底废除手写 [code]script_paths[/code] 映射字典；[br]
## 3. [b]最小信息熵多态染色（Smart Type Tagging）[/b]：当子对象实际类型与属性静态声明类型一致时，不写入任何多余字段（保持 100% 纯净 JSON）；
##    仅在发生多态子类赋值或存入弱类型容器时，自动按需标记 [constant TYPE_KEY]；[br]
## 4. [b]安全实例化沙箱与环路熔断[/b]：强制白名单校验 [code]res://[/code] 路径并在实例化前静态验证 [Resource] 继承链，
##    内置调用栈祖先环路检测（Cycle Detection）与最大递归深度保护，杜绝外部脚本注入与循环引用死锁。


#region Constants & Static Caches

const TYPE_KEY := "_type" ## 多态子类或弱类型容器内记录全局类名（或受控 res:// 路径）的保留键。
const LEGACY_SCRIPT_PATH_KEY := "_script_path" ## 兼容旧版存档格式的脚本路径保留键。
const MAX_DEPTH := 32 ## 最大递归嵌套深度保护。

const _BUILTIN_SKIP_NAMES: Dictionary = {
	"resource_local_to_scene": true,
	"resource_name": true,
	"resource_path": true,
	"script": true,
	TYPE_KEY: true,
	LEGACY_SCRIPT_PATH_KEY: true,
}

## 预编译属性 Schema 缓存：int (script_instance_id) or String (native_class) -> { "fields": Array[Dictionary], "map": Dictionary }
static var _schema_cache: Dictionary = {}
## 全局类名 -> 脚本路径映射：StringName (class_name) -> String (res://...)
static var _class_path_cache: Dictionary = {}
## 脚本路径 -> 全局类名反向映射：String (res://...) -> StringName (class_name)
static var _path_class_cache: Dictionary = {}
## 已完成安全基类校验的脚本路径缓存：String (class_name or path) -> String (verified res:// path)
## 注意：仅缓存 String 路径而不直接强引用 Script 对象，避免进程退出时触发 Godot Resource 残留告警。
static var _verified_path_cache: Dictionary = {}
static var _class_registry_ready: bool = false

#endregion


#region Public API

## 将 [param resource] 递归编码为纯净 [Dictionary]（JSON 友好结构）。[br]
## - 嵌套的 [Resource]、[BaseParams]、[Array]、[Dictionary] 与引擎值结构体（[Vector2]、[Color]、[Rect2] 等）会自动递归转换；[br]
## - [param extra_skip_names]：仅本次调用额外跳过的属性名列表；[br]
## - [param force_root_type]：是否在顶层字典强制写入 [constant TYPE_KEY]（默认 [code]false[/code] 保持纯净）。
static func encode(
	resource: Resource,
	extra_skip_names: Array[String] = [],
	force_root_type: bool = false
) -> Dictionary:
	if resource == null:
		return {}
	var expected_script: Script = null if force_root_type else (resource.get_script() as Script)
	var ancestors: Array[int] = []
	return _encode_resource(resource, expected_script, extra_skip_names, ancestors, 0)


## 将 [param encoded] 字典递归还原为强类型 [Resource] 实例。[br]
## - [param target_type]：目标根类型，支持直接传入类名/脚本（如 [code]HeroConfig[/code] 或内部类）、类名字符串（如 [code]"HeroConfig"[/code]）或留空（自动读取字典内嵌的 [constant TYPE_KEY]）；[br]
## - 所有嵌套子对象、强类型数组 [code]Array[T][/code]、强类型字典 [code]Dictionary[K, V][/code] 均由模具自动推导还原。
static func decode(encoded: Dictionary, target_type: Variant = null) -> Resource:
	var target_script: Script = target_type as Script if target_type is Script else null
	var target_class: StringName = StringName(target_type) if (target_type is String or target_type is StringName) else &""

	if encoded == null or encoded.is_empty():
		var empty_inst := _instantiate_target(target_script, target_class, {})
		return empty_inst if empty_inst != null else Resource.new()

	var resource := _instantiate_target(target_script, target_class, encoded)
	if resource == null:
		resource = Resource.new()
	_decode_into_resource(resource, encoded, 0)
	return resource


## 将 [param encoded] 字典的数据就地递归填充到已存在的 [param target] 实例中。[br]
## 返回是否成功执行填充。
static func decode_into(target: Resource, encoded: Dictionary) -> bool:
	if target == null or encoded == null or encoded.is_empty():
		return false
	_decode_into_resource(target, encoded, 0)
	return true


## 原生内存深拷贝 [Resource] 实例。[br]
## 直接基于预编译 Schema 在内存中递归复制整棵对象树，无需经过 Dictionary 序列化中转，100% 保留子类类型与容器强类型元信息。
static func clone(resource: Resource) -> Resource:
	if resource == null:
		return null
	var ancestors: Array[int] = []
	return _clone_resource(resource, ancestors, 0)


## 清空内部反射与脚本缓存（仅在编辑器热重载脚本或单元测试重置时按需调用）。
static func clear_caches() -> void:
	_schema_cache.clear()
	_class_path_cache.clear()
	_path_class_cache.clear()
	_verified_path_cache.clear()
	_class_registry_ready = false

#endregion


#region Core Operator 1: Encode (Strong Variant -> JSON Variant)

static func _encode_resource(
	resource: Resource,
	expected_script: Script,
	extra_skip_names: Array[String],
	ancestors: Array[int],
	depth: int
) -> Dictionary:
	if resource == null or depth > MAX_DEPTH:
		return {}

	var inst_id := resource.get_instance_id()
	if inst_id in ancestors:
		push_warning("ResourceCodecUtils.encode: Circular reference detected on Resource (id=%d), breaking cycle." % inst_id)
		return {}

	ancestors.push_back(inst_id)

	var encoded: Dictionary = {}
	var actual_script: Script = resource.get_script() as Script

	# 最小信息熵法则：仅当实际脚本与父属性静态声明的预期脚本不一致（多态子类或弱类型容器）时，才写入 _type
	if actual_script != null and actual_script != expected_script:
		var type_tag := _get_type_tag_for_script(actual_script)
		if not type_tag.is_empty():
			encoded[TYPE_KEY] = String(type_tag)

	var has_extra_skips := not extra_skip_names.is_empty()
	var schema := _get_schema(resource)
	var fields: Array = schema["fields"]

	for field: Dictionary in fields:
		var prop_name: String = field["name"]
		if has_extra_skips and prop_name in extra_skip_names:
			continue
		var val: Variant = resource.get(prop_name)
		var field_expected_script: Script = _resolve_script(field["class_name"]) if field["type"] == TYPE_OBJECT else null
		encoded[prop_name] = _encode_value(val, field_expected_script, extra_skip_names, ancestors, depth + 1)

	ancestors.pop_back()
	return encoded


static func _encode_value(
	value: Variant,
	expected_script: Script,
	extra_skip_names: Array[String],
	ancestors: Array[int],
	depth: int
) -> Variant:
	if value == null or depth > MAX_DEPTH:
		return null

	if value is Resource:
		return _encode_resource(value as Resource, expected_script, extra_skip_names, ancestors, depth)

	if value is BaseParams:
		return (value as BaseParams).to_dict(true)

	if value is Array:
		var arr := value as Array
		var elem_script: Script = arr.get_typed_script()
		if elem_script == null and not arr.get_typed_class_name().is_empty():
			elem_script = _resolve_script(arr.get_typed_class_name())

		var out_arr: Array = []
		out_arr.resize(arr.size())
		for i in arr.size():
			out_arr[i] = _encode_value(arr[i], elem_script, extra_skip_names, ancestors, depth + 1)
		return out_arr

	if value is Dictionary:
		var dict := value as Dictionary
		var k_script: Script = dict.get_typed_key_script()
		var v_script: Script = dict.get_typed_value_script()
		if v_script == null and not dict.get_typed_value_class_name().is_empty():
			v_script = _resolve_script(dict.get_typed_value_class_name())

		var out_dict: Dictionary = {}
		for k in dict:
			var ek: Variant = _encode_value(k, k_script, extra_skip_names, ancestors, depth + 1)
			var ev: Variant = _encode_value(dict[k], v_script, extra_skip_names, ancestors, depth + 1)
			out_dict[ek] = ev
		return out_dict

	return _encode_primitive(value)


static func _encode_primitive(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return {"x": value.x, "y": value.y}
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return {"x": value.x, "y": value.y, "z": value.z}
		TYPE_RECT2, TYPE_RECT2I:
			return {"x": value.position.x, "y": value.position.y, "w": value.size.x, "h": value.size.y}
		TYPE_COLOR:
			return (value as Color).to_html(true)
		TYPE_STRING_NAME:
			return String(value)
		TYPE_PACKED_BYTE_ARRAY:
			var bytes := value as PackedByteArray
			return "" if bytes.is_empty() else Marshalls.raw_to_base64(bytes)
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, \
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, \
		TYPE_PACKED_STRING_ARRAY:
			return Array(value)
		TYPE_PACKED_VECTOR2_ARRAY:
			var vecs := value as PackedVector2Array
			var out: Array = []
			out.resize(vecs.size())
			for i in vecs.size():
				out[i] = {"x": vecs[i].x, "y": vecs[i].y}
			return out
		_:
			return value

#endregion


#region Core Operator 2: Decode (JSON Variant + TypeMold -> Strong Variant)

static func _decode_into_resource(resource: Resource, encoded: Dictionary, depth: int) -> void:
	if resource == null or encoded.is_empty() or depth > MAX_DEPTH:
		return

	var schema := _get_schema(resource)
	var field_map: Dictionary = schema["map"]

	for raw_key in encoded:
		var prop_name := str(raw_key)
		if prop_name == TYPE_KEY or prop_name == LEGACY_SCRIPT_PATH_KEY:
			continue
		if not field_map.has(prop_name):
			continue

		var field: Dictionary = field_map[prop_name]
		var current_val: Variant = resource.get(prop_name)
		var raw_val: Variant = encoded[raw_key]
		var expected_script: Script = current_val.get_script() as Script if current_val is Object else null
		var decoded_val: Variant = _decode_value(
			raw_val,
			field["type"],
			expected_script,
			field["class_name"],
			current_val,
			field,
			depth + 1
		)
		resource.set(prop_name, decoded_val)


static func _decode_value(
	raw: Variant,
	expected_type: int,
	expected_script: Script,
	expected_class: StringName,
	current_template: Variant,
	field_meta: Dictionary,
	depth: int
) -> Variant:
	if raw == null or depth > MAX_DEPTH:
		return null

	# 1. 目标是 Resource 对象（强类型属性 TYPE_OBJECT，或弱类型容器中携带了 _type / _script_path 的字典）
	if expected_type == TYPE_OBJECT or (raw is Dictionary and _has_type_tag(raw as Dictionary)):
		if raw is Resource:
			return raw
		if raw is Dictionary:
			var raw_dict := raw as Dictionary
			# 若目标属性上已有默认 Resource 实例且字典未指定不同的多态子类，则直接就地填充
			if current_template is Resource and not _has_conflicting_type_tag(raw_dict, current_template as Resource):
				_decode_into_resource(current_template as Resource, raw_dict, depth)
				return current_template

			var sub_res := _instantiate_target(expected_script, expected_class, raw_dict)
			if sub_res == null:
				sub_res = Resource.new()
			_decode_into_resource(sub_res, raw_dict, depth)
			return sub_res
		return current_template

	# 2. 目标是 Array（通过容器原生 get_typed_script 直接向下传递 Script 引用，完美支持全局类与内部类 Inner Class）
	if expected_type == TYPE_ARRAY or (expected_type == TYPE_NIL and raw is Array):
		if not (raw is Array):
			return current_template if current_template is Array else []

		var raw_arr := raw as Array
		var elem_type: int = TYPE_NIL
		var elem_class: StringName = &""
		var elem_script: Script = null

		if current_template is Array and (current_template as Array).is_typed():
			var tpl_arr := current_template as Array
			elem_type = tpl_arr.get_typed_builtin()
			elem_script = tpl_arr.get_typed_script()
			elem_class = _get_type_tag_for_script(elem_script) if elem_script != null else tpl_arr.get_typed_class_name()
		elif not field_meta.is_empty():
			elem_type = field_meta.get("elem_type", TYPE_NIL)
			elem_class = field_meta.get("elem_class", &"")
			if elem_type == TYPE_OBJECT and not elem_class.is_empty():
				elem_script = _resolve_script(elem_class)

		var decoded_items: Array = []
		decoded_items.resize(raw_arr.size())
		for i in raw_arr.size():
			decoded_items[i] = _decode_value(raw_arr[i], elem_type, elem_script, elem_class, null, {}, depth + 1)

		# 优先使用目标属性上的原生定型数组模板复制并安全赋值
		if current_template is Array and (current_template as Array).is_typed():
			var typed_out: Array = (current_template as Array).duplicate()
			typed_out.clear()
			typed_out.assign(decoded_items)
			return typed_out

		# 后备构造：注意 Godot 4 要求仅当 elem_type == TYPE_OBJECT 时才可传 class_name 与 script
		if elem_type != TYPE_NIL:
			var base_cls: StringName = &""
			var script_arg: Script = null
			if elem_type == TYPE_OBJECT:
				base_cls = elem_script.get_instance_base_type() if elem_script != null else (elem_class if not elem_class.is_empty() else &"Resource")
				script_arg = elem_script
			var constructed := Array([], elem_type, base_cls, script_arg)
			constructed.assign(decoded_items)
			return constructed

		return decoded_items

	# 3. 目标是 Dictionary（支持 Godot 4.4+ Dictionary[K, V] 原生定型字典及普通嵌套字典）
	if expected_type == TYPE_DICTIONARY or (expected_type == TYPE_NIL and raw is Dictionary):
		if not (raw is Dictionary):
			return current_template if current_template is Dictionary else {}

		var raw_dict := raw as Dictionary
		var k_type: int = TYPE_NIL
		var k_script: Script = null
		var k_class: StringName = &""
		var v_type: int = TYPE_NIL
		var v_script: Script = null
		var v_class: StringName = &""

		if current_template is Dictionary and (current_template as Dictionary).is_typed():
			var tpl_dict := current_template as Dictionary
			k_type = tpl_dict.get_typed_key_builtin()
			k_script = tpl_dict.get_typed_key_script()
			k_class = _get_type_tag_for_script(k_script) if k_script != null else tpl_dict.get_typed_key_class_name()

			v_type = tpl_dict.get_typed_value_builtin()
			v_script = tpl_dict.get_typed_value_script()
			v_class = _get_type_tag_for_script(v_script) if v_script != null else tpl_dict.get_typed_value_class_name()

		var decoded_dict: Dictionary = {}
		for rk in raw_dict:
			var k: Variant = _decode_value(rk, k_type, k_script, k_class, null, {}, depth + 1)
			var v: Variant = _decode_value(raw_dict[rk], v_type, v_script, v_class, null, {}, depth + 1)
			decoded_dict[k] = v

		if current_template is Dictionary and (current_template as Dictionary).is_typed():
			var typed_dict: Dictionary = (current_template as Dictionary).duplicate()
			typed_dict.clear()
			typed_dict.assign(decoded_dict)
			return typed_dict

		return decoded_dict

	# 4. 引擎内置值类型与基础标量还原
	return _decode_primitive(raw, expected_type)


static func _decode_primitive(raw: Variant, expected_type: int) -> Variant:
	match expected_type:
		TYPE_BOOL:
			if raw is bool:
				return raw
			if raw is String:
				var s := (raw as String).strip_edges().to_lower()
				return s == "true" or s == "1" or s == "yes"
			return bool(raw)
		TYPE_INT:
			return int(raw) if (raw is float or raw is int or raw is String or raw is bool) else 0
		TYPE_FLOAT:
			return float(raw) if (raw is float or raw is int or raw is String) else 0.0
		TYPE_STRING:
			return str(raw) if raw != null else ""
		TYPE_STRING_NAME:
			return StringName(str(raw)) if raw != null else &""
		TYPE_VECTOR2:
			return _decode_vector2(raw)
		TYPE_VECTOR2I:
			var v2 := _decode_vector2(raw)
			return Vector2i(int(roundf(v2.x)), int(roundf(v2.y)))
		TYPE_VECTOR3:
			return _decode_vector3(raw)
		TYPE_VECTOR3I:
			var v3 := _decode_vector3(raw)
			return Vector3i(int(roundf(v3.x)), int(roundf(v3.y)), int(roundf(v3.z)))
		TYPE_RECT2:
			return _decode_rect2(raw)
		TYPE_RECT2I:
			var r2 := _decode_rect2(raw)
			return Rect2i(
				Vector2i(int(roundf(r2.position.x)), int(roundf(r2.position.y))),
				Vector2i(int(roundf(r2.size.x)), int(roundf(r2.size.y)))
			)
		TYPE_COLOR:
			return _decode_color(raw)
		TYPE_PACKED_BYTE_ARRAY:
			if raw is PackedByteArray:
				return raw
			if raw is String:
				var s := raw as String
				return PackedByteArray() if s.is_empty() else Marshalls.base64_to_raw(s)
			if raw is Array:
				return PackedByteArray(raw)
			return PackedByteArray()
		TYPE_PACKED_INT32_ARRAY:
			return PackedInt32Array(raw) if raw is Array else (raw if raw is PackedInt32Array else PackedInt32Array())
		TYPE_PACKED_INT64_ARRAY:
			return PackedInt64Array(raw) if raw is Array else (raw if raw is PackedInt64Array else PackedInt64Array())
		TYPE_PACKED_FLOAT32_ARRAY:
			return PackedFloat32Array(raw) if raw is Array else (raw if raw is PackedFloat32Array else PackedFloat32Array())
		TYPE_PACKED_FLOAT64_ARRAY:
			return PackedFloat64Array(raw) if raw is Array else (raw if raw is PackedFloat64Array else PackedFloat64Array())
		TYPE_PACKED_STRING_ARRAY:
			return PackedStringArray(raw) if raw is Array else (raw if raw is PackedStringArray else PackedStringArray())
		TYPE_PACKED_VECTOR2_ARRAY:
			if raw is PackedVector2Array:
				return raw
			if raw is Array:
				var raw_arr := raw as Array
				var out := PackedVector2Array()
				out.resize(raw_arr.size())
				for i in raw_arr.size():
					out[i] = _decode_vector2(raw_arr[i])
				return out
			return PackedVector2Array()
		_:
			return raw


static func _decode_vector2(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Vector2i:
		return Vector2(value.x, value.y)
	if value is Dictionary:
		var d := value as Dictionary
		var x = d.get("x", d.get("width", d.get("w", 0.0)))
		var y = d.get("y", d.get("height", d.get("h", 0.0)))
		return Vector2(float(x), float(y))
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	if value is String:
		var cleaned := (value as String).trim_prefix("Vector2i").trim_prefix("Vector2").trim_prefix("(").trim_suffix(")")
		var parts := cleaned.split(",")
		if parts.size() >= 2:
			return Vector2(float(parts[0].strip_edges()), float(parts[1].strip_edges()))
	return Vector2.ZERO


static func _decode_vector3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Vector3i:
		return Vector3(value.x, value.y, value.z)
	if value is Dictionary:
		var d := value as Dictionary
		return Vector3(float(d.get("x", 0.0)), float(d.get("y", 0.0)), float(d.get("z", 0.0)))
	if value is Array and (value as Array).size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


static func _decode_rect2(value: Variant) -> Rect2:
	if value is Rect2:
		return value
	if value is Rect2i:
		return Rect2(value.position, value.size)
	if value is Dictionary:
		var d := value as Dictionary
		if d.has("position") and d.has("size"):
			return Rect2(_decode_vector2(d["position"]), _decode_vector2(d["size"]))
		var x := float(d.get("x", 0.0))
		var y := float(d.get("y", 0.0))
		var w := float(d.get("w", d.get("width", 0.0)))
		var h := float(d.get("h", d.get("height", 0.0)))
		return Rect2(x, y, w, h)
	if value is Array and (value as Array).size() >= 4:
		return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	return Rect2()


static func _decode_color(value: Variant) -> Color:
	if value is Color:
		return value
	if value is String:
		var s := (value as String).strip_edges()
		if Color.html_is_valid(s):
			return Color.html(s)
		return Color.from_string(s, Color.WHITE)
	if value is Dictionary:
		var d := value as Dictionary
		return Color(float(d.get("r", 1.0)), float(d.get("g", 1.0)), float(d.get("b", 1.0)), float(d.get("a", 1.0)))
	if value is Array and (value as Array).size() >= 3:
		var a := float(value[3]) if (value as Array).size() >= 4 else 1.0
		return Color(float(value[0]), float(value[1]), float(value[2]), a)
	return Color.WHITE

#endregion


#region Core Operator 3: Direct Memory Clone (Zero-Serialization Deep Copy)

static func _clone_resource(src: Resource, ancestors: Array[int], depth: int) -> Resource:
	if src == null or depth > MAX_DEPTH:
		return null

	var inst_id := src.get_instance_id()
	if inst_id in ancestors:
		push_warning("ResourceCodecUtils.clone: Circular reference detected on Resource (id=%d), breaking cycle." % inst_id)
		return null

	ancestors.push_back(inst_id)

	var script: Script = src.get_script() as Script
	var dst: Resource = null
	if script != null and script.can_instantiate():
		dst = script.new() as Resource
	else:
		var cls_name := src.get_class()
		if ClassDB.class_exists(cls_name) and ClassDB.can_instantiate(cls_name):
			dst = ClassDB.instantiate(cls_name) as Resource
	if dst == null:
		dst = Resource.new()

	var schema := _get_schema(src)
	var fields: Array = schema["fields"]
	for field: Dictionary in fields:
		var prop_name: String = field["name"]
		dst.set(prop_name, _clone_value(src.get(prop_name), ancestors, depth + 1))

	ancestors.pop_back()
	return dst


static func _clone_value(val: Variant, ancestors: Array[int], depth: int) -> Variant:
	if val == null or depth > MAX_DEPTH:
		return null
	if val is Resource:
		return _clone_resource(val as Resource, ancestors, depth)
	if val is BaseParams:
		return (val as BaseParams).clone()
	if val is Array:
		var src_arr := val as Array
		var dst_arr: Array = src_arr.duplicate()
		dst_arr.clear()
		var items: Array = []
		items.resize(src_arr.size())
		for i in src_arr.size():
			items[i] = _clone_value(src_arr[i], ancestors, depth + 1)
		dst_arr.assign(items)
		return dst_arr
	if val is Dictionary:
		var src_dict := val as Dictionary
		var dst_dict: Dictionary = src_dict.duplicate()
		dst_dict.clear()
		var temp: Dictionary = {}
		for k in src_dict:
			temp[_clone_value(k, ancestors, depth + 1)] = _clone_value(src_dict[k], ancestors, depth + 1)
		dst_dict.assign(temp)
		return dst_dict
	return val

#endregion


#region Pre-compiled Schema & Safe Sandboxed Instantiation

## 获取或构建指定 [Resource] 的预编译属性 Schema（全生命周期仅解析一次）。
static func _get_schema(resource: Resource) -> Dictionary:
	var cache_key: Variant = _get_schema_cache_key(resource)
	if _schema_cache.has(cache_key):
		return _schema_cache[cache_key]

	var fields: Array[Dictionary] = []
	var field_map: Dictionary = {}

	for prop: Dictionary in resource.get_property_list():
		var name_str: String = prop.get("name", "")
		if name_str.is_empty() or name_str.begins_with("_") or _BUILTIN_SKIP_NAMES.has(name_str):
			continue
		var usage: int = prop.get("usage", 0)
		if (usage & (PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_SCRIPT_VARIABLE)) == 0:
			continue

		var prop_type: int = prop.get("type", TYPE_NIL)
		var prop_class: StringName = &""
		var elem_type: int = TYPE_NIL
		var elem_class: StringName = &""

		if prop_type == TYPE_OBJECT:
			var hint_str := str(prop.get("hint_string", ""))
			var cls_str := str(prop.get("class_name", ""))
			prop_class = StringName(hint_str if not hint_str.is_empty() else cls_str)
		elif prop_type == TYPE_ARRAY:
			var hint: int = prop.get("hint", PROPERTY_HINT_NONE)
			if hint == PROPERTY_HINT_ARRAY_TYPE or hint == PROPERTY_HINT_TYPE_STRING:
				var hint_str := str(prop.get("hint_string", ""))
				var colon_idx := hint_str.find(":")
				if colon_idx != -1:
					var prefix := hint_str.substr(0, colon_idx)
					var slash_idx := prefix.find("/")
					elem_type = int(prefix.substr(0, slash_idx if slash_idx != -1 else prefix.length()))
					if elem_type == TYPE_OBJECT:
						elem_class = StringName(hint_str.substr(colon_idx + 1))

		var meta := {
			"name": name_str,
			"type": prop_type,
			"class_name": prop_class,
			"elem_type": elem_type,
			"elem_class": elem_class,
		}
		fields.append(meta)
		field_map[name_str] = meta

	var schema := {"fields": fields, "map": field_map}
	_schema_cache[cache_key] = schema
	return schema


static func _get_schema_cache_key(resource: Resource) -> Variant:
	var script: Script = resource.get_script() as Script
	if script != null:
		# 使用 Script 实例唯一 ID 作为缓存键，O(1) 整数哈希且天然区分同一文件内的外部类与多个内部类（Inner Class）
		return script.get_instance_id()
	return resource.get_class()


## 根据显式目标 Script、类名或字典内的类型标签安全实例化 [Resource]。
static func _instantiate_target(target_script: Script, target_class: StringName, encoded: Dictionary) -> Resource:
	# 1. 字典内显式携带了多态子类标签时，优先按标签解析（支持多态向下还原）
	var embedded_tag := _extract_type_tag(encoded)
	if not embedded_tag.is_empty():
		var tagged_script := _resolve_script(embedded_tag)
		if tagged_script != null:
			return tagged_script.new() as Resource
		if ClassDB.class_exists(embedded_tag) and ClassDB.can_instantiate(embedded_tag) \
				and ClassDB.is_parent_class(embedded_tag, &"Resource"):
			return ClassDB.instantiate(embedded_tag) as Resource

	# 2. 调用方或父容器直接传入了 Script 引用（支持全局类与内部类 Inner Class）
	if target_script != null and _is_safe_resource_script(target_script):
		return target_script.new() as Resource

	# 3. 调用方或父属性传入了类名或脚本路径字符串
	if not target_class.is_empty():
		var resolved_script := _resolve_script(target_class)
		if resolved_script != null:
			return resolved_script.new() as Resource
		if ClassDB.class_exists(target_class) and ClassDB.can_instantiate(target_class) \
				and (target_class == &"Resource" or ClassDB.is_parent_class(target_class, &"Resource")):
			return ClassDB.instantiate(target_class) as Resource

	return null


## 将类名（如 &"HeroConfig"）或受控路径（如 &"res://..."）解析为经过安全基类验证的 [Script]。
static func _resolve_script(identifier: StringName) -> Script:
	if identifier.is_empty():
		return null
	var key := String(identifier)
	if _verified_path_cache.has(key):
		return ResourceLoader.load(_verified_path_cache[key]) as Script

	_ensure_class_registry()

	var path := ""
	if _class_path_cache.has(identifier):
		path = _class_path_cache[identifier]
	elif key.begins_with("res://") and not key.contains("..") and key.ends_with(".gd"):
		path = key

	if path.is_empty() or not ResourceLoader.exists(path):
		return null

	var loaded := ResourceLoader.load(path)
	if loaded is Script and _is_safe_resource_script(loaded as Script):
		_verified_path_cache[key] = path
		return loaded as Script

	return null


## 静态校验 [Script] 是否可安全实例化且严格继承自 [Resource]（必须在 .new() 之前调用）。
static func _is_safe_resource_script(script: Script) -> bool:
	if script == null or not script.can_instantiate():
		return false
	var base_type := script.get_instance_base_type()
	return base_type == &"Resource" or ClassDB.is_parent_class(base_type, &"Resource")


static func _ensure_class_registry() -> void:
	if _class_registry_ready:
		return
	_class_registry_ready = true
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		var cls_name := StringName(entry.get("class", ""))
		var path := String(entry.get("path", ""))
		if not cls_name.is_empty() and not path.is_empty():
			_class_path_cache[cls_name] = path
			_path_class_cache[path] = cls_name


static func _get_type_tag_for_script(script: Script) -> StringName:
	if script == null:
		return &""
	var global_name := script.get_global_name()
	if not global_name.is_empty():
		return global_name
	_ensure_class_registry()
	var path := script.resource_path
	if _path_class_cache.has(path):
		return _path_class_cache[path]
	return StringName(path)


static func _has_type_tag(dict: Dictionary) -> bool:
	return dict.has(TYPE_KEY) or dict.has(LEGACY_SCRIPT_PATH_KEY)


static func _extract_type_tag(dict: Dictionary) -> StringName:
	if dict.has(TYPE_KEY):
		return StringName(str(dict[TYPE_KEY]))
	if dict.has(LEGACY_SCRIPT_PATH_KEY):
		return StringName(str(dict[LEGACY_SCRIPT_PATH_KEY]))
	return &""


static func _has_conflicting_type_tag(dict: Dictionary, existing: Resource) -> bool:
	var tag := _extract_type_tag(dict)
	if tag.is_empty():
		return false
	var existing_script: Script = existing.get_script() as Script
	if existing_script == null:
		return true
	return tag != _get_type_tag_for_script(existing_script) and String(tag) != existing_script.resource_path

#endregion
